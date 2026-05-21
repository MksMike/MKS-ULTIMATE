//+------------------------------------------------------------------+
//| @file           : Producer.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Experts / MKS-ULTIMATE
//| @responsibility : EA produtor fundido — embute Builder + Sizer +
//|                   Writer num programa único. OnInit faz fill
//|                   histórico opcional, OnTick processa ticks live,
//|                   OnDeinit fecha o arquivo .mksbk. Slice 3b. Combate
//|                   o eixo 2 do V5 (mesmo motor para histórico e live).
//| @depends_on     : Core/RenkoBuilder/CMksRenkoBuilder.mqh,
//|                   Core/RenkoBuilder/CMksFixedBrickSizer.mqh,
//|                   Core/Data/CMksBrickFileWriter.mqh,
//|                   Core/Types/RenkoGeometry.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/Error.mqh,
//|                   Core/Interfaces/IRenkoSink.mqh
//| @install_path   : MQL5/Experts/MKS-ULTIMATE/Producer.mq5
//+------------------------------------------------------------------+
#property strict

#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksRenkoBuilder.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksFixedBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickFileWriter.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>

input double InpBrickSizePts        = 3.0;   // tamanho do brick em pontos
input int    InpHistoricalFillDays  = 0;     // 0 = sem fill histórico; >0 = CopyTicksRange(now-N*86400, now)
input int    InpInvalidTickLimit    = 10;    // L (ADR-006 §5)
input int    InpThresholdLimit      = 20;    // K (ADR-011 §4)
input bool   InpPrintBricks         = false; // verbose: imprime cada brick no journal
input int    InpInvalidLogEvery     = 100;   // rate-limit do log 103: imprime 1 a cada N

string  g_symbol         = "";
int     g_digits         = 0;
string  g_broker         = "";
long    g_account        = 0;
string  g_filePath       = "";
ulong   g_seq            = 0;
int     g_invalidLogged  = 0;
int     g_invalidSeen    = 0;
int     g_k102Seen       = 0;
bool    g_streamHalted   = false;
int     g_histLoaded     = 0;
int     g_histBricks     = 0;

CMksFixedBrickSizer  *g_sizer   = NULL;
CMksBrickFileWriter  *g_writer  = NULL;
CMksRenkoBuilder     *g_builder = NULL;

//+------------------------------------------------------------------+
//| Sink: encaminha cada brick fechado para o writer e contabiliza.   |
//+------------------------------------------------------------------+
class CBrickWriterSink : public IRenkoSink
{
public:
   CMksBrickFileWriter *writer;
   int  bricksWritten;
   int  writeFailures;
   bool printBricks;
   int  digits;

   CBrickWriterSink()
   {
      writer = NULL;
      bricksWritten = 0;
      writeFailures = 0;
      printBricks = false;
      digits = 2;
   }

   void OnBrickClose(const MksBrick &brick) override
   {
      if(writer == NULL) return;
      MksError err;
      if(!writer.WriteBrick(brick, err))
      {
         writeFailures++;
         PrintFormat("WRITE FAIL: %s", err.ToString());
         return;
      }
      bricksWritten++;
      if(printBricks)
      {
         PrintFormat("BRICK %s open=%s close=%s M=%d trigger=%s time=%s",
                     brick.IsBull() ? "BULL" : "BEAR",
                     DoubleToString(brick.open, digits),
                     DoubleToString(brick.close, digits),
                     brick.thresholdsCrossed,
                     DoubleToString(brick.triggerPrice, digits),
                     TimeToString((datetime)(brick.closeTimeMsc / 1000),
                                  TIME_DATE|TIME_SECONDS));
      }
   }
};

CBrickWriterSink *g_sink = NULL;

//+------------------------------------------------------------------+
//| Gera caminho do .mksbk (ADR-014 §4.2 e §4 cláusula 4).             |
//| attempt = 0 → nome base; attempt > 0 → sufixo "_<attempt+1>"       |
//| (primeiro retry é "_2", segundo "_3", etc).                       |
//+------------------------------------------------------------------+
string BuildBrickFilePath(const string &symbol, datetime sessionStart, int attempt)
{
   MqlDateTime dt;
   TimeToStruct(sessionStart, dt);
   string stamp = StringFormat("%04d%02d%02dT%02d%02d%02d",
                               dt.year, dt.mon, dt.day,
                               dt.hour, dt.min, dt.sec);
   string suffix = (attempt > 0) ? StringFormat("_%d", attempt + 1) : "";
   return StringFormat("MKS-ULTIMATE\\Bricks\\%s_%s%s.mksbk",
                       symbol, stamp, suffix);
}

//+------------------------------------------------------------------+
//| Converte MqlTick em MksTick com seq monotônico e flags preservados |
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
   t.flags   = mt.flags; // ADR-012 §4
   return t;
}

//+------------------------------------------------------------------+
//| Alimenta o builder com um tick e despacha tratamento de erro.     |
//+------------------------------------------------------------------+
void IngestOne(const MksTick &tick)
{
   if(g_streamHalted) return;
   MksError err;
   if(g_builder.IngestTick(tick, err)) return;

   if(err.code == MKS_ERR_RENKO_INVALID_TICK)
   {
      g_invalidSeen++;
      if(InpInvalidLogEvery > 0 && (g_invalidSeen % InpInvalidLogEvery == 0))
      {
         g_invalidLogged++;
         PrintFormat("103 invalid tick (%d-th, log 1/%d): %s",
                     g_invalidSeen, InpInvalidLogEvery, err.ToString());
      }
   }
   else if(err.code == MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED)
   {
      g_k102Seen++;
      PrintFormat("102 K-exceeded: %s", err.ToString());
   }
   else if(err.code == MKS_ERR_RENKO_TICK_STREAM_CORRUPT)
   {
      g_streamHalted = true;
      PrintFormat("104 STREAM CORRUPT — builder interrompido: %s", err.ToString());
   }
   else
   {
      PrintFormat("ERR: %s", err.ToString());
   }
}

//+------------------------------------------------------------------+
//| Fill histórico (ADR-013 §2 — broker/account capturados antes).     |
//+------------------------------------------------------------------+
void RunHistoricalFill(int days)
{
   if(days <= 0) return;
   long toMsc   = (long)TimeCurrent() * 1000;
   long fromMsc = toMsc - (long)days * 24L * 3600L * 1000L;

   MqlTick ticks[];
   int n = CopyTicksRange(g_symbol, ticks, COPY_TICKS_ALL, fromMsc, toMsc);
   if(n <= 0)
   {
      PrintFormat("historical fill: CopyTicksRange retornou %d (LastError=%d)",
                  n, GetLastError());
      return;
   }
   g_histLoaded = n;
   PrintFormat("historical fill: %d ticks (%d dias)", n, days);

   int bricksBefore = g_sink.bricksWritten;
   for(int i = 0; i < n; i++)
   {
      MksTick t = ToMksTick(ticks[i]);
      IngestOne(t);
      if(g_streamHalted) break;
   }
   g_histBricks = g_sink.bricksWritten - bricksBefore;
   PrintFormat("historical fill: %d bricks emitidos", g_histBricks);
}

//+------------------------------------------------------------------+
//| Limpeza segura para uso em meio de OnInit (parcial) ou OnDeinit.   |
//+------------------------------------------------------------------+
void Cleanup()
{
   if(g_builder != NULL) { delete g_builder; g_builder = NULL; }
   if(g_sink    != NULL) { delete g_sink;    g_sink    = NULL; }
   if(g_writer  != NULL) { delete g_writer;  g_writer  = NULL; }
   if(g_sizer   != NULL) { delete g_sizer;   g_sizer   = NULL; }
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol  = _Symbol;
   g_digits  = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   g_broker  = AccountInfoString(ACCOUNT_COMPANY);
   g_account = AccountInfoInteger(ACCOUNT_LOGIN);

   Print("");
   Print("=== MKS-ULTIMATE Producer (Slice 3b) ===");
   PrintFormat("provenance: broker=\"%s\" account=%I64d symbol=%s digits=%d",
               g_broker, g_account, g_symbol, g_digits);
   PrintFormat("config: S=%.4f preset=median L=%d K=%d histDays=%d printBricks=%s",
               InpBrickSizePts, InpInvalidTickLimit, InpThresholdLimit,
               InpHistoricalFillDays, (InpPrintBricks ? "true" : "false"));

   // Pasta destino. FileOpen não cria recursivamente — criar nível por nível.
   FolderCreate("MKS-ULTIMATE");
   FolderCreate("MKS-ULTIMATE\\Bricks");

   // Sizer (heap para que cleanup parcial seja uniforme).
   g_sizer = new CMksFixedBrickSizer(InpBrickSizePts);
   MksError err;
   if(!g_sizer.Validate(err))
   {
      PrintFormat("OnInit: sizer inválido: %s", err.ToString());
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }

   MksRenkoGeometry geom = MksGeometryMedian();
   if(!geom.Validate(err))
   {
      PrintFormat("OnInit: geometria inválida: %s", err.ToString());
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }

   // Writer com retry de sufixo numérico em caso de colisão (ADR-014 §4).
   // Sessão capturada uma vez para que todos os retries usem o mesmo
   // timestamp — sufixo é o único campo que muda entre tentativas.
   g_writer = new CMksBrickFileWriter();
   datetime sessionStart = TimeCurrent();
   const int kMaxAttempts = 100;
   bool opened = false;
   for(int attempt = 0; attempt < kMaxAttempts; attempt++)
   {
      g_filePath = BuildBrickFilePath(g_symbol, sessionStart, attempt);
      if(g_writer.Open(g_filePath, err))
      {
         opened = true;
         break;
      }
      if(err.code != MKS_ERR_DATA_FILE_EXISTS) break; // erro real, não retry
      PrintFormat("OnInit: arquivo existe, tentando próximo sufixo: %s", g_filePath);
   }
   if(!opened)
   {
      PrintFormat("OnInit: writer.Open falhou: %s", err.ToString());
      Cleanup();
      return INIT_FAILED;
   }
   PrintFormat("output: %s", g_filePath);
   if(!g_writer.WriteHeader(g_broker, g_account, g_symbol, g_digits,
                            geom, InpBrickSizePts, err))
   {
      PrintFormat("OnInit: WriteHeader falhou: %s", err.ToString());
      Cleanup();
      return INIT_FAILED;
   }

   // Sink (referencia writer) e builder (referencia sizer + sink).
   g_sink = new CBrickWriterSink();
   g_sink.writer      = g_writer;
   g_sink.printBricks = InpPrintBricks;
   g_sink.digits      = g_digits;

   g_builder = new CMksRenkoBuilder(geom, g_sizer, g_sink,
                                    InpInvalidTickLimit, InpThresholdLimit);

   // Fill histórico opcional (mesmo motor; combate ao eixo 2 do V5).
   RunHistoricalFill(InpHistoricalFillDays);

   Print("OnInit: pronto. Processando ticks live...");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(g_streamHalted || g_builder == NULL) return;

   MqlTick mt;
   if(!SymbolInfoTick(g_symbol, mt)) return;

   MksTick t = ToMksTick(mt);
   IngestOne(t);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_writer != NULL)
   {
      MksError err;
      if(!g_writer.Close(err))
         PrintFormat("OnDeinit: Close falhou: %s", err.ToString());
   }

   int totalBricks  = (g_sink != NULL) ? g_sink.bricksWritten : 0;
   int writeFails   = (g_sink != NULL) ? g_sink.writeFailures : 0;
   long fileBricks  = (g_writer != NULL) ? g_writer.BrickCount() : 0;

   Print("");
   Print("=== RELATORIO Producer ===");
   PrintFormat("deinit reason: %d", reason);
   PrintFormat("ticks ingeridos (seq): %I64u", g_seq);
   PrintFormat("bricks: total=%d (writer count=%I64d) writeFailures=%d",
               totalBricks, fileBricks, writeFails);
   PrintFormat("histórico: ticks=%d bricks=%d", g_histLoaded, g_histBricks);
   PrintFormat("erros: 102=%d 103=%d (logados=%d) 104=%s",
               g_k102Seen, g_invalidSeen, g_invalidLogged,
               (g_streamHalted ? "yes" : "no"));
   PrintFormat("arquivo: %s", g_filePath);
   Print("=== fim ===");

   Cleanup();
}
//+------------------------------------------------------------------+