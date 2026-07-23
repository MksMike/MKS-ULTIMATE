//+------------------------------------------------------------------+
//| @file           : Replayer.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Experts / MKS-ULTIMATE
//| @responsibility : EA que monta o composition root do framework
//|                   FORA do Strategy Tester e replaya .mkstick pelo
//|                   mesmo CMksRenkoBuilder que rodaria em live.
//|                   Saída: replay.mksbk + replay.log — comparáveis
//|                   byte-a-byte contra live.mksbk/log via fc/b e
//|                   tools/verify-parity.ps1 (slice 24f).
//|                   Materializa ADR-024 §regra 5.
//|                   Versão mínima: source → builder → writer. Broker,
//|                   risk e trade manager entram quando estratégia
//|                   existir (Fase 9), sob o mesmo composition root.
//| @depends_on     : Core/Data/CMksFileTickSource.mqh,
//|                   Core/Data/CMksMultiFileTickSource.mqh,
//|                   Core/Data/CMksBrickFileWriter.mqh,
//|                   Core/Data/CMksBrickWriterSink.mqh,
//|                   Core/Clock/CMksReplayClock.mqh,
//|                   Core/RenkoBuilder/CMksRenkoBuilder.mqh,
//|                   Core/RenkoBuilder/CMksFixedBrickSizer.mqh,
//|                   Core/Log/CMksLogger.mqh,
//|                   Core/Symbol/CMksMt5Symbol.mqh,
//|                   Core/Account/CMksMt5Account.mqh,
//|                   Core/Types/RenkoGeometry.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Experts/MKS-ULTIMATE/Replayer.mq5
//+------------------------------------------------------------------+
#property strict
#property copyright "MKS-ULTIMATE"
#property version   "1.00"

#include <MKS-ULTIMATE/Core/Data/CMksFileTickSource.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksMultiFileTickSource.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksTickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickFileWriter.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickWriterSink.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksMultiSink.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksAuditLogSink.mqh>
#include <MKS-ULTIMATE/Core/Clock/CMksReplayClock.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksRenkoBuilder.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksFixedBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Log/CMksLogger.mqh>
#include <MKS-ULTIMATE/Core/Symbol/CMksMt5Symbol.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksMt5Account.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ITickSource.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//--- Inputs --------------------------------------------------------
input group "=== Fonte de ticks ==="
input string InpTickFilePath  = "MKS-ULTIMATE\\Ticks\\XAUUSDm_20260520.mkstick"; // single-file
input string InpTickFolder    = "";        // multi: pasta com .mkstick (vazia = single)
input string InpSymbolPrefix  = "";        // multi: prefixo de nome (ex: XAUUSDm)

input group "=== Brick (classic, ADR-026) ==="
input double InpBrickSize        = 3.0; // mesmo valor usado pelo Producer
input int    InpInvalidTickLimit    = 10;  // L (ADR-006)
input int    InpThresholdLimit      = 20;  // K (ADR-011)

input group "=== Output ==="
input string InpOutputMksbkPath     = "";  // vazio = auto: replay_<sourceFile>.mksbk
input bool   InpLogToFile           = true;
input bool   InpAlsoWriteAudit      = false; // true = grava audit.tsv (uma linha por brick) para diff humano contra audit do Producer

input group "=== Performance ==="
input int    InpTimerMs             = 1;     // intervalo do OnTimer (1ms = throughput max)
input int    InpTicksPerCycle       = 10000; // máx ticks por chamada do OnTimer

//--- Estado global -------------------------------------------------
ISymbol              *g_iSymbol  = NULL;
IAccount             *g_iAccount = NULL;
ITickSource          *g_source   = NULL;
CMksFileTickSource   *g_singleSource = NULL;  // ownership single
CMksMultiFileTickSource *g_multiSource = NULL; // ownership multi
CMksReplayClock      *g_clock    = NULL;
CMksFixedBrickSizer  *g_sizer    = NULL;
CMksBrickFileWriter  *g_writer     = NULL;
CMksBrickWriterSink  *g_sink       = NULL;
CMksMultiSink        *g_multiSink  = NULL;  // ativo quando audit ligado
CMksAuditLogSink     *g_auditSink  = NULL;  // InpAlsoWriteAudit
CMksRenkoBuilder     *g_builder    = NULL;
CMksLogger           *g_logger     = NULL;

string  g_sourceSymbol  = "";
string  g_sourceBroker  = "";
long    g_sourceAccount = 0;
int     g_sourceDigits  = 0;
string  g_outputPath    = "";
string  g_auditPath     = "";
string  g_logPath       = "";

bool    g_eof           = false;
bool    g_halted        = false;
long    g_ticksConsumed = 0;
long    g_ticksInvalid  = 0;
long    g_ticksK102     = 0;
long    g_ticksK105     = 0; // recoveries de gap estrutural (ADR-011 nota)
ulong   g_startMs       = 0;
bool    g_isMultiMode   = false;

//+------------------------------------------------------------------+
//| Lê proveniência do primeiro .mkstick (header-only, sem consumir   |
//| ticks). Usado para inicializar o composition root antes de abrir  |
//| o source de fato.                                                 |
//+------------------------------------------------------------------+
bool ReadFirstFileProvenance(const string &path, string &broker, long &account,
                              string &symbol, int &digits, MksError &err)
{
   CMksTickFileReader r;
   if(!r.Open(path, err)) return false;
   broker  = r.Broker();
   account = r.AccountLogin();
   symbol  = r.Symbol();
   digits  = r.Digits();
   r.Close();
   return true;
}

//+------------------------------------------------------------------+
//| Lista arquivos .mkstick numa pasta com filtro por prefixo de      |
//| nome. Ordenação cronológica == lexicográfica (ADR-024 §3 — naming |
//| YYYYMMDD garante ordem natural).                                   |
//+------------------------------------------------------------------+
int ListMkstickFolder(const string &folder, const string &symbolPrefix, string &out[])
{
   ArrayResize(out, 0);
   string pattern = folder + "\\" + symbolPrefix + "_*.mkstick";
   string filename;
   long handle = FileFindFirst(pattern, filename);
   if(handle == INVALID_HANDLE) return 0;

   int n = 0;
   do
   {
      if(StringFind(filename, ".mkstick") < 0) continue;
      ArrayResize(out, n + 1);
      out[n] = folder + "\\" + filename;
      n++;
   } while(FileFindNext(handle, filename));
   FileFindClose(handle);

   // Sort lexicográfico — coincide com cronológico pelo naming YYYYMMDD.
   if(n > 1) ArraySort(out);
   return n;
}

//+------------------------------------------------------------------+
//| Auto-nome do .mksbk de saída quando InpOutputMksbkPath está vazio.|
//| Padrão: MKS-ULTIMATE\Bricks\replay_<sourceStem>_<TS>.mksbk        |
//+------------------------------------------------------------------+
string AutoOutputPath(const string &sourceStem)
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   string stamp = StringFormat("%04d%02d%02dT%02d%02d%02d",
                                dt.year, dt.mon, dt.day,
                                dt.hour, dt.min, dt.sec);
   return StringFormat("MKS-ULTIMATE\\Bricks\\replay_%s_%s.mksbk",
                        sourceStem, stamp);
}

//+------------------------------------------------------------------+
//| Extrai stem (nome sem extensão e sem path) de um caminho.         |
//| FIX 2026-05-25: StringFind retorna a PRIMEIRA ocorrência, não a   |
//| última — versão anterior cortava no primeiro `\` e deixava sub-   |
//| pastas no stem (ex: "Ticks\XAUUSDm_..." virava stem). Agora       |
//| varremos do fim para o início para achar o último separador.      |
//+------------------------------------------------------------------+
string PathStem(const string &path)
{
   int len = StringLen(path);
   int lastSep = -1;
   for(int i = len - 1; i >= 0; i--)
   {
      ushort c = StringGetCharacter(path, i);
      if(c == '\\' || c == '/') { lastSep = i; break; }
   }
   string name = (lastSep >= 0) ? StringSubstr(path, lastSep + 1) : path;
   int dot = StringFind(name, ".");
   return (dot > 0) ? StringSubstr(name, 0, dot) : name;
}

//+------------------------------------------------------------------+
//| Cleanup global ordenado.                                          |
//+------------------------------------------------------------------+
void Cleanup()
{
   if(g_builder      != NULL) { delete g_builder;      g_builder      = NULL; }
   if(g_multiSink    != NULL) { delete g_multiSink;    g_multiSink    = NULL; }
   if(g_auditSink    != NULL) { delete g_auditSink;    g_auditSink    = NULL; }
   if(g_sink         != NULL) { delete g_sink;         g_sink         = NULL; }
   if(g_writer       != NULL) { delete g_writer;       g_writer       = NULL; }
   if(g_sizer        != NULL) { delete g_sizer;        g_sizer        = NULL; }
   if(g_clock        != NULL) { delete g_clock;        g_clock        = NULL; }
   if(g_singleSource != NULL) { delete g_singleSource; g_singleSource = NULL; g_source = NULL; }
   if(g_multiSource  != NULL) { delete g_multiSource;  g_multiSource  = NULL; g_source = NULL; }
   if(g_logger       != NULL) { delete g_logger;       g_logger       = NULL; }
   if(g_iSymbol      != NULL) { delete g_iSymbol;      g_iSymbol      = NULL; }
   if(g_iAccount     != NULL) { delete g_iAccount;     g_iAccount     = NULL; }
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_startMs = GetTickCount();
   g_isMultiMode = (StringLen(InpTickFolder) > 0 && StringLen(InpSymbolPrefix) > 0);

   // 1. Determinar arquivo "primeiro" para extrair proveniência canônica.
   string firstPath = "";
   string allPaths[];

   if(g_isMultiMode)
   {
      int n = ListMkstickFolder(InpTickFolder, InpSymbolPrefix, allPaths);
      if(n == 0)
      {
         PrintFormat("Replayer: nenhum .mkstick encontrado em '%s' com prefixo '%s'",
                     InpTickFolder, InpSymbolPrefix);
         return INIT_PARAMETERS_INCORRECT;
      }
      firstPath = allPaths[0];
   }
   else
   {
      if(StringLen(InpTickFilePath) == 0)
      {
         Print("Replayer: InpTickFilePath vazio (e modo multi não ativado)");
         return INIT_PARAMETERS_INCORRECT;
      }
      firstPath = InpTickFilePath;
   }

   // 2. Ler proveniência do primeiro arquivo.
   MksError err;
   if(!ReadFirstFileProvenance(firstPath, g_sourceBroker, g_sourceAccount,
                                g_sourceSymbol, g_sourceDigits, err))
   {
      PrintFormat("Replayer: falha ao ler proveniência de '%s': %s",
                  firstPath, err.ToString());
      return INIT_FAILED;
   }

   // 3. SymbolSelect para o símbolo da captura (borda permitida).
   //    Não-fatal se falhar: o builder não consulta SymbolInfo direto;
   //    apenas WARN para auditoria. ISymbol é usado mais para metadados
   //    no log/header do .mksbk de saída.
   bool symbolSelected = SymbolSelect(g_sourceSymbol, true);

   // 4. Composition root: borda permitida pela ADR-013 §2.
   g_iSymbol  = new CMksMt5Symbol(g_sourceSymbol);
   g_iAccount = new CMksMt5Account();

   // 5. Logger antes de qualquer escrita estruturada.
   FolderCreate("MKS-ULTIMATE");
   FolderCreate("MKS-ULTIMATE\\Bricks");
   FolderCreate("MKS-ULTIMATE\\Logs");

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   string stamp = StringFormat("%04d%02d%02dT%02d%02d%02d",
                                dt.year, dt.mon, dt.day,
                                dt.hour, dt.min, dt.sec);

   g_logger = new CMksLogger();
   g_logPath = StringFormat("MKS-ULTIMATE\\Logs\\Replayer_%s_%s.log",
                             g_sourceSymbol, stamp);
   if(!g_logger.Open(g_logPath, MKS_LOG_INFO, true, InpLogToFile, err))
   {
      PrintFormat("Replayer: logger.Open falhou: %s", err.ToString());
      Cleanup();
      return INIT_FAILED;
   }
   g_logger.WriteHeader(g_sourceBroker, g_sourceAccount, g_sourceSymbol,
                        g_sourceDigits, "Replayer", (long)now * 1000);
   g_logger.Info("Replayer", "starting",
      StringFormat("\"mode\":\"%s\",\"firstPath\":\"%s\",\"symbolSelected\":%s,"
                   "\"S\":%.4f,\"L\":%d,\"K\":%d",
                   (g_isMultiMode ? "multi" : "single"),
                   MksJsonEscape(firstPath),
                   (symbolSelected ? "true" : "false"),
                   InpBrickSize, InpInvalidTickLimit, InpThresholdLimit));

   // 6. Cria source apropriado.
   if(g_isMultiMode)
   {
      g_multiSource = new CMksMultiFileTickSource(allPaths,
                                                   g_sourceBroker,
                                                   g_sourceAccount,
                                                   g_sourceSymbol);
      if(!g_multiSource.Open(err))
      {
         g_logger.Error("Replayer", "multi source open failed",
            StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
         Cleanup();
         return INIT_FAILED;
      }
      g_source = g_multiSource;
      g_logger.Info("Replayer", "multi source opened",
         StringFormat("\"fileCount\":%d", g_multiSource.FileCount()));
   }
   else
   {
      g_singleSource = new CMksFileTickSource(InpTickFilePath,
                                               g_sourceBroker,
                                               g_sourceAccount,
                                               g_sourceSymbol);
      if(!g_singleSource.Open(err))
      {
         g_logger.Error("Replayer", "single source open failed",
            StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
         Cleanup();
         return INIT_FAILED;
      }
      g_source = g_singleSource;
      g_logger.Info("Replayer", "single source opened",
         StringFormat("\"path\":\"%s\",\"tickCount\":%I64d",
                      MksJsonEscape(InpTickFilePath), g_singleSource.TickCount()));
   }

   // 7. Clock de replay — função pura do feed (ADR-024 §5).
   g_clock = new CMksReplayClock(g_source);

   // 8. Sizer + geometria classic (ADR-026 — Producer e Replayer ambos
   //    classic; estratégia opera sobre brick.close real).
   g_sizer = new CMksFixedBrickSizer(InpBrickSize);
   if(!g_sizer.Validate(err))
   {
      g_logger.Error("Replayer", "sizer invalid",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }

   MksRenkoGeometry geom = MksGeometryClassic();
   if(!geom.Validate(err))
   {
      g_logger.Error("Replayer", "geometry invalid",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }

   // 9. Output .mksbk path.
   if(StringLen(InpOutputMksbkPath) > 0)
      g_outputPath = InpOutputMksbkPath;
   else
   {
      string stem = PathStem(firstPath);
      g_outputPath = AutoOutputPath(stem);
   }

   // 10. Writer + sink. Sem CustomSymbol no Replayer — saída canônica é
   //     o .mksbk, comparado byte-a-byte contra live.mksbk via fc/b.
   g_writer = new CMksBrickFileWriter();
   if(!g_writer.Open(g_outputPath, err))
   {
      g_logger.Error("Replayer", "writer.Open failed",
         StringFormat("\"path\":\"%s\",\"err\":\"%s\"",
                      MksJsonEscape(g_outputPath), MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_FAILED;
   }
   if(!g_writer.WriteHeader(g_sourceBroker, g_sourceAccount, g_sourceSymbol,
                             g_sourceDigits, geom, InpBrickSize, err))
   {
      g_logger.Error("Replayer", "writer.WriteHeader failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_FAILED;
   }
   g_logger.Info("Replayer", "mksbk opened",
      StringFormat("\"path\":\"%s\"", MksJsonEscape(g_outputPath)));

   g_sink = new CMksBrickWriterSink();
   g_sink.writer      = g_writer;
   g_sink.printBricks = false; // verbose desligado no Replayer
   g_sink.digits      = g_sourceDigits;

   // Sink final passado ao builder: por padrão é g_sink (writer-only).
   // Se InpAlsoWriteAudit=true, embrulha em MultiSink que também
   // alimenta um CMksAuditLogSink — gera audit.tsv comparável via
   // diff contra o audit do Producer em modo paridade.
   IRenkoSink *builderSink = g_sink;
   if(InpAlsoWriteAudit)
   {
      MqlDateTime ndt;
      TimeToStruct(now, ndt);
      string nstamp = StringFormat("%04d%02d%02dT%02d%02d%02d",
                                    ndt.year, ndt.mon, ndt.day,
                                    ndt.hour, ndt.min, ndt.sec);
      g_auditPath = StringFormat("MKS-ULTIMATE\\Logs\\Replayer_audit_%s_%s.tsv",
                                  g_sourceSymbol, nstamp);
      g_auditSink = new CMksAuditLogSink();
      if(!g_auditSink.Open(g_auditPath))
      {
         g_logger.Error("Replayer", "auditSink.Open failed",
            StringFormat("\"path\":\"%s\"", MksJsonEscape(g_auditPath)));
         Cleanup();
         return INIT_FAILED;
      }
      // Header com mesmos campos do audit do Producer — diff direto.
      g_auditSink.WriteHeader(g_sourceSymbol, g_sourceBroker, g_sourceAccount,
                               g_sourceDigits, InpBrickSize, "classic");
      g_multiSink = new CMksMultiSink();
      g_multiSink.Add(g_sink);
      g_multiSink.Add(g_auditSink);
      builderSink = g_multiSink;
      g_logger.Info("Replayer", "audit mode enabled",
         StringFormat("\"auditPath\":\"%s\"", MksJsonEscape(g_auditPath)));
   }

   // 11. Builder — mesma geometria classic, mesmos L/K do Producer.
   g_builder = new CMksRenkoBuilder(geom, g_sizer, builderSink,
                                    InpInvalidTickLimit, InpThresholdLimit);
   // Replayer não atualiza CS visual; sem OnBrickForming para evitar
   // milhões de chamadas inúteis durante throughput máximo.
   g_builder.SetEmitForming(false);

   // 12. Dispara timer para processar ticks. 1ms = throughput máximo
   //     (MQL5 não permite OnTimer mais frequente).
   int timerMs = (InpTimerMs > 0) ? InpTimerMs : 1;
   EventSetMillisecondTimer(timerMs);

   g_logger.Info("Replayer", "OnInit done, replay dispatched via OnTimer",
      StringFormat("\"timerMs\":%d,\"ticksPerCycle\":%d",
                   timerMs, InpTicksPerCycle));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Processa N ticks por chamada. Retorna true se atingiu EOF natural.|
//+------------------------------------------------------------------+
bool ProcessBatch()
{
   if(g_halted || g_eof) return true;

   int processed = 0;
   MksTick t;
   MksError err;
   while(processed < InpTicksPerCycle)
   {
      if(!g_source.Next(t))
      {
         // EOF OU falha durante advance (multi-file).
         if(g_isMultiMode)
         {
            if(g_multiSource.SeqDiscontinuityDetected())
            {
               g_logger.Error("Replayer", "multi seq discontinuity",
                  StringFormat("\"msg\":\"%s\"",
                               MksJsonEscape(g_multiSource.SeqDiscontinuityMsg())));
               g_halted = true;
               return true;
            }
            if(g_multiSource.AdvanceFailureDetected())
            {
               g_logger.Error("Replayer", "multi advance failure",
                  StringFormat("\"msg\":\"%s\"",
                               MksJsonEscape(g_multiSource.AdvanceErrorMsg())));
               g_halted = true;
               return true;
            }
         }
         g_eof = true;
         return true;
      }
      g_ticksConsumed++;

      if(!g_builder.IngestTick(t, err))
      {
         if(err.code == MKS_ERR_RENKO_INVALID_TICK)
         {
            g_ticksInvalid++;
            if(g_auditSink != NULL)
               g_auditSink.RecordInvalidTick(t.seq, t.bid, t.ask);
         }
         else if(err.code == MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED)
         {
            g_ticksK102++;
            if(g_auditSink != NULL)
               g_auditSink.RecordKExceeded(t.seq, (t.bid + t.ask) / 2.0,
                                            InpThresholdLimit + 1);
         }
         else if(err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP)
         {
            g_ticksK105++;
            if(g_auditSink != NULL)
               g_auditSink.RecordKExceeded(t.seq, (t.bid + t.ask) / 2.0, -105);
            g_logger.Warn("Replayer", "gap structural — builder reanchored",
               StringFormat("\"code\":105,\"err\":\"%s\"",
                            MksJsonEscape(err.ToString())));
         }
         else if(err.code == MKS_ERR_RENKO_TICK_STREAM_CORRUPT)
         {
            if(g_auditSink != NULL)
               g_auditSink.RecordStreamHalted(t.seq, InpInvalidTickLimit);
            g_logger.Error("Replayer", "stream corrupt, builder halted",
               StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
            g_halted = true;
            return true;
         }
         else
         {
            g_logger.Error("Replayer", "ingest error",
               StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
         }
      }
      processed++;
   }
   return false; // mais ticks pendentes — OnTimer volta no próximo tick
}

//+------------------------------------------------------------------+
//| Termina replay: fecha writer, loga summary, encerra EA.           |
//+------------------------------------------------------------------+
void FinishReplay()
{
   EventKillTimer();

   MksError err;
   long fileBricks = (g_writer != NULL) ? g_writer.BrickCount() : 0;
   if(g_writer != NULL)
   {
      // E2.3: grava a ancora da escada (seedMid/seedTickSeq) no header antes do Close.
      if(g_builder != NULL)
         g_writer.SetSeed(g_builder.SeedMid(), g_builder.SeedTickSeq());
      if(!g_writer.Close(err))
         g_logger.Error("Replayer", "writer.Close failed",
            StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
   }
   // Fecha audit sink (escreve rodapé com total). Mesmo padrão do Producer
   // — garante que diff posterior pegue arquivo finalizado.
   if(g_auditSink != NULL) g_auditSink.Close();

   ulong elapsedMs = GetTickCount() - g_startMs;
   double ticksPerSec = (elapsedMs > 0) ? (double)g_ticksConsumed * 1000.0 / elapsedMs : 0.0;

   if(g_logger != NULL)
   {
      g_logger.Info("Replayer", "replay summary",
         StringFormat("\"eof\":%s,\"halted\":%s,\"ticksConsumed\":%I64d,"
                      "\"ticksInvalid\":%I64d,\"ticksK102\":%I64d,\"ticksK105Recovered\":%I64d,"
                      "\"bricksWritten\":%I64d,\"elapsedMs\":%I64u,"
                      "\"ticksPerSec\":%.0f,\"outputPath\":\"%s\","
                      "\"auditPath\":\"%s\","
                      "\"logPath\":\"%s\"",
                      (g_eof ? "true" : "false"),
                      (g_halted ? "true" : "false"),
                      g_ticksConsumed, g_ticksInvalid, g_ticksK102, g_ticksK105,
                      fileBricks, elapsedMs, ticksPerSec,
                      MksJsonEscape(g_outputPath),
                      MksJsonEscape(g_auditPath),
                      MksJsonEscape(g_logPath)));
      g_logger.Close();
   }

   ExpertRemove(); // remove o EA do chart automaticamente
}

//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_eof || g_halted) return;
   bool done = ProcessBatch();
   if(done) FinishReplay();
}

//+------------------------------------------------------------------+
//| OnTick: Replayer NÃO consome ticks live — o feed é o .mkstick.    |
//| Mantém-se vazio deliberadamente; o motor roda em OnTimer.         |
//+------------------------------------------------------------------+
void OnTick() {}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   // Se ainda não chamou FinishReplay (deinit por desanexo do usuário,
   // por exemplo), fecha o writer aqui para não deixar header inconsistente.
   if(!g_eof && !g_halted)
   {
      MksError err;
      if(g_writer != NULL)
      {
         if(g_builder != NULL)  // E2.3: ancora tambem no fecho por deinit precoce
            g_writer.SetSeed(g_builder.SeedMid(), g_builder.SeedTickSeq());
         g_writer.Close(err);
      }
      if(g_logger != NULL)
      {
         g_logger.Info("Replayer", "deinit before EOF",
            StringFormat("\"reason\":%d,\"ticksConsumed\":%I64d",
                         reason, g_ticksConsumed));
         g_logger.Close();
      }
   }
   Cleanup();
}
//+------------------------------------------------------------------+
