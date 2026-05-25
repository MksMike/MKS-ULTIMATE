//+------------------------------------------------------------------+
//| @file           : TickRecorder.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Services / MKS-ULTIMATE
//| @responsibility : Service que captura ticks crus de um símbolo MT5
//|                   em arquivo .mkstick com header de proveniência.
//|                   Roll-over diário UTC, checkpoint periódico para
//|                   tolerar crash, single-symbol. Materializa
//|                   ADR-024 §regra 2 e §regra 3.
//| @depends_on     : Core/Data/CMksTickFileWriter.mqh,
//|                   Core/Symbol/CMksMt5Symbol.mqh,
//|                   Core/Account/CMksMt5Account.mqh,
//|                   Core/Log/CMksLogger.mqh,
//|                   Core/Types/Tick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Services/MKS-ULTIMATE/TickRecorder.mq5
//+------------------------------------------------------------------+
#property service
#property copyright "MKS-ULTIMATE"
#property version   "1.00"

#include <MKS-ULTIMATE/Core/Data/CMksTickFileWriter.mqh>
#include <MKS-ULTIMATE/Core/Symbol/CMksMt5Symbol.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksMt5Account.mqh>
#include <MKS-ULTIMATE/Core/Log/CMksLogger.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//--- Inputs --------------------------------------------------------
input string InpSymbol            = "XAUUSDm"; // Símbolo a capturar (obrigatório — Service não tem _Symbol)
input int    InpPollMs            = 250;       // Intervalo de polling (ms)
input int    InpCheckpointTicks   = 100;       // Checkpoint a cada N ticks
input int    InpCheckpointSec     = 2;         // Checkpoint a cada T segundos (o que vier primeiro)
input int    InpMaxFileAttempts   = 100;       // Tentativas de sufixo numérico em colisão de nome
input bool   InpLogToFile         = true;      // Grava .log em MKS-ULTIMATE\Logs\

//--- Estado global -------------------------------------------------
ISymbol              *g_iSymbol  = NULL;
IAccount             *g_iAccount = NULL;
CMksTickFileWriter   *g_writer   = NULL;
CMksLogger           *g_logger   = NULL;

string  g_broker;
long    g_account;
string  g_symbol;
int     g_digits;
double  g_tickSize;
double  g_point;
double  g_contractSize;
string  g_logPath = "";

ulong   g_seq = 0;
long    g_lastSeenMsc = 0;
int     g_currentUtcDay = -1;
string  g_currentFilePath = "";

long    g_ticksWritten      = 0;
long    g_ticksSkippedDup   = 0;  // dedup por timeMsc <= último
long    g_ticksSkippedBad   = 0;  // dedup por preço inválido (bid<=0)
int     g_ticksSinceFlush   = 0;
ulong   g_lastCheckpointMs  = 0;

//+------------------------------------------------------------------+
//| Converte segundos UTC em "dia UTC" (epoch / 86400).               |
//+------------------------------------------------------------------+
int UtcDayFromSec(datetime utcSec)
{
   return (int)((long)utcSec / 86400);
}

//+------------------------------------------------------------------+
//| Formata YYYYMMDD a partir de datetime UTC.                        |
//+------------------------------------------------------------------+
string YmdFromUtc(datetime utcSec)
{
   MqlDateTime dt;
   TimeToStruct(utcSec, dt);
   return StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
}

//+------------------------------------------------------------------+
//| Caminho base do .mkstick para o dia UTC corrente.                 |
//| attempt = 0 → nome base; > 0 → sufixo "_<attempt+1>" (ADR-014-like)|
//+------------------------------------------------------------------+
string BuildTickFilePath(const string &symbol, datetime utcDayStart, int attempt)
{
   string ymd = YmdFromUtc(utcDayStart);
   string suffix = (attempt > 0) ? StringFormat("_%d", attempt + 1) : "";
   return StringFormat("MKS-ULTIMATE\\Ticks\\%s_%s%s.mkstick",
                       symbol, ymd, suffix);
}

//+------------------------------------------------------------------+
//| Converte MqlTick em MksTick, atribuindo seq monotônico global.    |
//+------------------------------------------------------------------+
MksTick ToMksTick(const MqlTick &mt)
{
   MksTick t;
   g_seq++;
   t.seq     = g_seq;
   t.timeMsc = mt.time_msc;
   t.bid     = mt.bid;
   t.ask     = mt.ask;
   t.last    = mt.last;
   t.volume  = (long)mt.volume;
   t.flags   = mt.flags;
   return t;
}

//+------------------------------------------------------------------+
//| Abre arquivo .mkstick para o dia UTC corrente. Tenta sufixos      |
//| numéricos em caso de colisão (MKS_ERR_DATA_FILE_EXISTS), mesmo    |
//| padrão do Producer (ADR-014 §4 cláusula 4).                       |
//+------------------------------------------------------------------+
bool OpenWriterForDay(datetime utcDayStart, MksError &err)
{
   if(g_writer != NULL) { delete g_writer; g_writer = NULL; }
   g_writer = new CMksTickFileWriter();

   bool opened = false;
   for(int attempt = 0; attempt < InpMaxFileAttempts; attempt++)
   {
      g_currentFilePath = BuildTickFilePath(g_symbol, utcDayStart, attempt);
      if(g_writer.Open(g_currentFilePath, err))
      {
         opened = true;
         break;
      }
      if(err.code != MKS_ERR_DATA_FILE_EXISTS) break;
      // colisão — tenta próximo sufixo
   }
   if(!opened)
   {
      g_logger.Error("TickRecorder", "writer.Open failed",
         StringFormat("\"path\":\"%s\",\"err\":\"%s\"",
                      MksJsonEscape(g_currentFilePath),
                      MksJsonEscape(err.ToString())));
      return false;
   }

   if(!g_writer.WriteHeader(g_broker, g_account, g_symbol, g_digits,
                            g_tickSize, g_point, g_contractSize, err))
   {
      g_logger.Error("TickRecorder", "writer.WriteHeader failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      return false;
   }

   g_logger.Info("TickRecorder", "mkstick opened",
      StringFormat("\"path\":\"%s\",\"utcDay\":%d",
                   MksJsonEscape(g_currentFilePath),
                   UtcDayFromSec(utcDayStart)));
   return true;
}

//+------------------------------------------------------------------+
//| Fecha o writer corrente patcheando o header final.                |
//+------------------------------------------------------------------+
void CloseCurrentWriter()
{
   if(g_writer == NULL) return;
   MksError err;
   if(!g_writer.Close(err) && g_logger != NULL)
      g_logger.Error("TickRecorder", "writer.Close failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
   delete g_writer;
   g_writer = NULL;
}

//+------------------------------------------------------------------+
//| Faz checkpoint do writer (patcha header sem fechar handle).       |
//+------------------------------------------------------------------+
void Checkpoint()
{
   if(g_writer == NULL) return;
   MksError err;
   if(!g_writer.Checkpoint(err))
      g_logger.Warn("TickRecorder", "checkpoint failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
   g_ticksSinceFlush  = 0;
   g_lastCheckpointMs = GetTickCount();
}

//+------------------------------------------------------------------+
//| Lê ticks acumulados desde g_lastSeenMsc e grava no writer.        |
//| Usa CopyTicks(COPY_TICKS_ALL, fromMsc, count). Dedup por timeMsc. |
//+------------------------------------------------------------------+
void ProcessNewTicks()
{
   if(g_writer == NULL) return;

   MqlTick ticks[];
   // count=0 → MT5 escolhe limite default (4096). fromMsc=0 vira "todos
   // os ticks disponíveis"; usamos g_lastSeenMsc para janela incremental.
   long fromMsc = (g_lastSeenMsc > 0) ? g_lastSeenMsc : 0;
   int n = CopyTicks(g_symbol, ticks, COPY_TICKS_ALL, fromMsc, 0);
   if(n <= 0) return;

   MksError err;
   for(int i = 0; i < n; i++)
   {
      // Dedup: CopyTicks pode retornar o tick com timeMsc==fromMsc.
      if(ticks[i].time_msc <= g_lastSeenMsc)
      {
         g_ticksSkippedDup++;
         continue;
      }

      // Filtro mínimo: tick sem bid/ask válidos é descartado na captura
      // (ADR-006 está no consumo, mas tick com bid=0 e ask=0 é lixo
      // estrutural — provavelmente o slot do CopyTicks veio vazio).
      // Diferente do builder, AQUI o tick pode legitimamente faltar
      // se o broker entregou apenas um lado (TICK_FLAG_BID ou _ASK).
      // Por isso preservamos tick sem dedup pelos flags — só descartamos
      // se ambos forem 0 simultaneamente.
      if(ticks[i].bid <= 0.0 && ticks[i].ask <= 0.0)
      {
         g_ticksSkippedBad++;
         g_lastSeenMsc = ticks[i].time_msc;
         continue;
      }

      MksTick t = ToMksTick(ticks[i]);
      if(!g_writer.WriteTick(t, err))
      {
         g_logger.Error("TickRecorder", "WriteTick failed",
            StringFormat("\"seq\":%I64u,\"err\":\"%s\"",
                         t.seq, MksJsonEscape(err.ToString())));
         return;
      }
      g_lastSeenMsc = ticks[i].time_msc;
      g_ticksWritten++;
      g_ticksSinceFlush++;
   }
}

//+------------------------------------------------------------------+
//| Cleanup global — chamado em qualquer caminho de saída de OnStart. |
//+------------------------------------------------------------------+
void Cleanup()
{
   CloseCurrentWriter();
   if(g_logger   != NULL) { delete g_logger;   g_logger   = NULL; }
   if(g_iSymbol  != NULL) { delete g_iSymbol;  g_iSymbol  = NULL; }
   if(g_iAccount != NULL) { delete g_iAccount; g_iAccount = NULL; }
}

//+------------------------------------------------------------------+
//| OnStart — entry point do Service. Loop com Sleep até IsStopped.   |
//+------------------------------------------------------------------+
void OnStart()
{
   if(StringLen(InpSymbol) == 0)
   {
      Print("TickRecorder: InpSymbol vazio — abortando.");
      return;
   }

   if(!SymbolSelect(InpSymbol, true))
   {
      PrintFormat("TickRecorder: SymbolSelect(%s) falhou (err=%d). "
                  "Adicione o símbolo manualmente ao Market Watch.",
                  InpSymbol, GetLastError());
      return;
   }

   // Composition root: borda permitida pela ADR-013 §2.
   g_iSymbol  = new CMksMt5Symbol(InpSymbol);
   g_iAccount = new CMksMt5Account();
   g_symbol       = InpSymbol;
   g_broker       = g_iAccount.Company();
   g_account      = g_iAccount.Login();
   g_digits       = g_iSymbol.Digits();
   g_tickSize     = g_iSymbol.TickSize();
   g_point        = g_iSymbol.Point();
   g_contractSize = g_iSymbol.ContractSize();

   if(g_digits <= 0 || g_point <= 0.0 || g_tickSize <= 0.0)
   {
      PrintFormat("TickRecorder: ficha técnica inválida — digits=%d point=%.10f tickSize=%.10f",
                  g_digits, g_point, g_tickSize);
      Cleanup();
      return;
   }

   FolderCreate("MKS-ULTIMATE");
   FolderCreate("MKS-ULTIMATE\\Ticks");
   FolderCreate("MKS-ULTIMATE\\Logs");

   // Logger antes de qualquer escrita estruturada.
   datetime startUtc = TimeGMT();
   MqlDateTime sdt;
   TimeToStruct(startUtc, sdt);
   string stamp = StringFormat("%04d%02d%02dT%02d%02d%02d",
                               sdt.year, sdt.mon, sdt.day,
                               sdt.hour, sdt.min, sdt.sec);
   g_logger = new CMksLogger();
   g_logPath = StringFormat("MKS-ULTIMATE\\Logs\\TickRecorder_%s_%s.log",
                            g_symbol, stamp);
   MksError err;
   if(!g_logger.Open(g_logPath, MKS_LOG_INFO, true, InpLogToFile, err))
   {
      PrintFormat("TickRecorder: logger.Open falhou: %s", err.ToString());
      Cleanup();
      return;
   }
   g_logger.WriteHeader(g_broker, g_account, g_symbol, g_digits,
                        "TickRecorder", (long)startUtc * 1000);
   g_logger.Info("TickRecorder", "starting",
      StringFormat("\"symbol\":\"%s\",\"pollMs\":%d,\"checkpointTicks\":%d,\"checkpointSec\":%d",
                   g_symbol, InpPollMs, InpCheckpointTicks, InpCheckpointSec));

   // Abre primeiro arquivo do dia UTC corrente.
   g_currentUtcDay = UtcDayFromSec(startUtc);
   if(!OpenWriterForDay(startUtc, err))
   {
      g_logger.Error("TickRecorder", "initial OpenWriterForDay failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return;
   }

   // Anchor inicial: pega o último tick do mercado para começar dali.
   // Evita reprocessar histórico via CopyTicks(fromMsc=0).
   MqlTick anchor;
   if(SymbolInfoTick(g_symbol, anchor))
      g_lastSeenMsc = anchor.time_msc;

   g_lastCheckpointMs = GetTickCount();

   // Loop principal — Service roda até IsStopped().
   // Sleep entre iterações é OK (Service não compete com OnTick de EA).
   while(!IsStopped())
   {
      // 1. Roll-over UTC.
      datetime nowUtc = TimeGMT();
      int utcDay = UtcDayFromSec(nowUtc);
      if(utcDay != g_currentUtcDay)
      {
         g_logger.Info("TickRecorder", "utc rollover",
            StringFormat("\"oldDay\":%d,\"newDay\":%d,\"ticks\":%I64d",
                         g_currentUtcDay, utcDay, g_ticksWritten));
         CloseCurrentWriter();
         g_currentUtcDay = utcDay;
         if(!OpenWriterForDay(nowUtc, err))
         {
            g_logger.Error("TickRecorder", "rollover OpenWriterForDay failed",
               StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
            break;
         }
      }

      // 2. Processa ticks novos.
      ProcessNewTicks();

      // 3. Checkpoint se atingiu N ticks ou T segundos.
      ulong nowMs = GetTickCount();
      bool needCheckpointByTicks = (g_ticksSinceFlush >= InpCheckpointTicks);
      bool needCheckpointByTime  = ((long)(nowMs - g_lastCheckpointMs) >= InpCheckpointSec * 1000);
      if(g_ticksSinceFlush > 0 && (needCheckpointByTicks || needCheckpointByTime))
         Checkpoint();

      Sleep(InpPollMs);
   }

   // Cleanup ordenado: checkpoint final → close → summary → cleanup.
   if(g_writer != NULL && g_ticksSinceFlush > 0)
      Checkpoint();

   g_logger.Info("TickRecorder", "shutdown summary",
      StringFormat("\"ticksWritten\":%I64d,\"ticksSkippedDup\":%I64d,"
                   "\"ticksSkippedBad\":%I64d,\"lastFilePath\":\"%s\","
                   "\"logPath\":\"%s\"",
                   g_ticksWritten, g_ticksSkippedDup, g_ticksSkippedBad,
                   MksJsonEscape(g_currentFilePath),
                   MksJsonEscape(g_logPath)));

   if(g_logger != NULL) g_logger.Close();
   Cleanup();
}
//+------------------------------------------------------------------+
