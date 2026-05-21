//+------------------------------------------------------------------+
//| @file           : Producer.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Experts / MKS-ULTIMATE
//| @responsibility : EA produtor fundido — embute Builder + Sizer +
//|                   Writer + Custom Symbol num programa único. OnInit
//|                   faz fill histórico opcional, OnTick processa ticks
//|                   live, OnDeinit fecha o arquivo .mksbk. Slice 3b.
//|                   Combate o eixo 2 do V5 (mesmo motor para histórico
//|                   e live). Cada brick é gravado no .mksbk e empurrado
//|                   como barra no Custom Symbol via multi-sink.
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
input bool   InpResetCustomSymbolBars = true; // wipe bars antigas do Custom Symbol no OnInit

string   g_symbol         = "";
int      g_digits         = 0;
string   g_broker         = "";
long     g_account        = 0;
string   g_filePath       = "";
string   g_csName         = "";
datetime g_nextBarTime    = 0;
ulong    g_seq            = 0;
int      g_invalidLogged  = 0;
int      g_invalidSeen    = 0;
int      g_k102Seen       = 0;
bool     g_streamHalted   = false;
int      g_histLoaded     = 0;
int      g_histBricks     = 0;

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
//| Sink: empurra cada brick como uma barra no Custom Symbol.         |
//| Usa slot M1 monotônico (+60s por brick) para evitar colisão de    |
//| timestamp — CustomRatesUpdate sobrescreve bars com mesmo time.    |
//| Tempo da bar é índice ordenador, não tempo real do brick.         |
//+------------------------------------------------------------------+
class CCustomSymbolSink : public IRenkoSink
{
public:
   string   csName;
   datetime nextBarTime;
   int      barsPushed;
   int      updateFailures;

   CCustomSymbolSink()
   {
      csName         = "";
      nextBarTime    = 0;
      barsPushed     = 0;
      updateFailures = 0;
   }

   void OnBrickClose(const MksBrick &brick) override
   {
      if(StringLen(csName) == 0) return;
      MqlRates rates[1];
      rates[0].time        = nextBarTime;
      rates[0].open        = brick.open;
      rates[0].high        = brick.high;
      rates[0].low         = brick.low;
      rates[0].close       = brick.close;
      rates[0].tick_volume = brick.thresholdsCrossed; // não é volume real
      rates[0].spread      = 0;
      rates[0].real_volume = 0;
      int n = CustomRatesUpdate(csName, rates);
      if(n < 0)
      {
         updateFailures++;
         PrintFormat("CS UPDATE FAIL: lastErr=%d", GetLastError());
      }
      else
      {
         barsPushed++;
      }
      nextBarTime = (datetime)((long)nextBarTime + 60);
   }
};

CCustomSymbolSink *g_csSink = NULL;

//+------------------------------------------------------------------+
//| Sink composto: delega OnBrickClose a múltiplos sinks reais.       |
//| Não possui os sinks — apenas os referencia. Cleanup deleta cada   |
//| sink real separadamente.                                          |
//+------------------------------------------------------------------+
class CMultiSink : public IRenkoSink
{
public:
   IRenkoSink *sinks[];
   int         count;

   CMultiSink()
   {
      count = 0;
   }

   void Add(IRenkoSink *sink)
   {
      if(sink == NULL) return;
      ArrayResize(sinks, count + 1);
      sinks[count] = sink;
      count++;
   }

   void OnBrickClose(const MksBrick &brick) override
   {
      for(int i = 0; i < count; i++)
         if(sinks[i] != NULL)
            sinks[i].OnBrickClose(brick);
   }
};

CMultiSink *g_multiSink = NULL;

//+------------------------------------------------------------------+
//| Nome do Custom Symbol: <symbol>.MKS_RKN<size>.                    |
//| Decisão de implementação sem ADR (ADR-014 §6 Fronteiras).          |
//+------------------------------------------------------------------+
string BuildCustomSymbolName(const string &symbol, double sizePts)
{
   string sizeStr;
   if(MathAbs(sizePts - MathRound(sizePts)) < 1e-9)
      sizeStr = StringFormat("%d", (int)MathRound(sizePts));
   else
      sizeStr = DoubleToString(sizePts, 2);
   return StringFormat("%s.MKS_RKN%s", symbol, sizeStr);
}

//+------------------------------------------------------------------+
//| Cria ou recupera o Custom Symbol. Replica propriedades imutáveis  |
//| do símbolo base (Setar SYMBOL_DIGITS/POINT/CHART_MODE/TICK_SIZE   |
//| APAGA o histórico do CS — efeito simétrico com ADR-014). Seleciona |
//| em Market Watch (requisito de fato para CustomRatesUpdate).        |
//+------------------------------------------------------------------+
bool EnsureCustomSymbolReady(const string &cs, const string &src, MksError &err)
{
   bool exists = (SymbolInfoInteger(cs, SYMBOL_CUSTOM) == 1);
   if(!exists)
   {
      if(!CustomSymbolCreate(cs, "MKS-ULTIMATE", src))
      {
         int lastErr = GetLastError();
         if(lastErr != 5304) // 5304 = símbolo já existe (race)
         {
            MKS_SET_ERROR(err, MKS_ERR_DATA_FILE_IO,
                          "CustomSymbolCreate falhou",
                          StringFormat("cs=%s src=%s lastErr=%d", cs, src, lastErr));
            return false;
         }
      }
   }

   CustomSymbolSetInteger(cs, SYMBOL_DIGITS,
                          SymbolInfoInteger(src, SYMBOL_DIGITS));
   CustomSymbolSetInteger(cs, SYMBOL_CHART_MODE, (long)SYMBOL_CHART_MODE_BID);
   CustomSymbolSetDouble (cs, SYMBOL_POINT,
                          SymbolInfoDouble(src, SYMBOL_POINT));
   CustomSymbolSetDouble (cs, SYMBOL_TRADE_TICK_SIZE,
                          SymbolInfoDouble(src, SYMBOL_TRADE_TICK_SIZE));
   CustomSymbolSetDouble (cs, SYMBOL_TRADE_TICK_VALUE,
                          SymbolInfoDouble(src, SYMBOL_TRADE_TICK_VALUE));
   CustomSymbolSetDouble (cs, SYMBOL_TRADE_CONTRACT_SIZE,
                          SymbolInfoDouble(src, SYMBOL_TRADE_CONTRACT_SIZE));
   CustomSymbolSetString (cs, SYMBOL_CURRENCY_BASE,
                          SymbolInfoString(src, SYMBOL_CURRENCY_BASE));
   CustomSymbolSetString (cs, SYMBOL_CURRENCY_PROFIT,
                          SymbolInfoString(src, SYMBOL_CURRENCY_PROFIT));
   CustomSymbolSetString (cs, SYMBOL_CURRENCY_MARGIN,
                          SymbolInfoString(src, SYMBOL_CURRENCY_MARGIN));

   if(!SymbolSelect(cs, true))
   {
      MKS_SET_ERROR(err, MKS_ERR_DATA_FILE_IO,
                    "SymbolSelect falhou — CS não entrou no Market Watch",
                    StringFormat("cs=%s lastErr=%d", cs, GetLastError()));
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Alinha um datetime para o início do minuto (M1 boundary).         |
//+------------------------------------------------------------------+
datetime AlignDownToM1(datetime t)
{
   long s = (long)t;
   return (datetime)((s / 60) * 60);
}

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
   if(g_builder    != NULL) { delete g_builder;    g_builder    = NULL; }
   if(g_multiSink  != NULL) { delete g_multiSink;  g_multiSink  = NULL; }
   if(g_csSink     != NULL) { delete g_csSink;     g_csSink     = NULL; }
   if(g_sink       != NULL) { delete g_sink;       g_sink       = NULL; }
   if(g_writer     != NULL) { delete g_writer;     g_writer     = NULL; }
   if(g_sizer      != NULL) { delete g_sizer;      g_sizer      = NULL; }
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
   PrintFormat("config: S=%.4f preset=median L=%d K=%d histDays=%d printBricks=%s resetCS=%s",
               InpBrickSizePts, InpInvalidTickLimit, InpThresholdLimit,
               InpHistoricalFillDays, (InpPrintBricks ? "true" : "false"),
               (InpResetCustomSymbolBars ? "true" : "false"));

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

   // Custom Symbol: replica propriedades do símbolo base, opcionalmente
   // limpa bars antigas (simétrico com ADR-014: sessão nova = histórico
   // limpo). Setado APÓS WriteHeader do .mksbk para que uma falha aqui
   // não bagunce a invariante do writer.
   g_csName = BuildCustomSymbolName(g_symbol, InpBrickSizePts);
   PrintFormat("custom symbol: %s", g_csName);
   if(!EnsureCustomSymbolReady(g_csName, g_symbol, err))
   {
      PrintFormat("OnInit: EnsureCustomSymbolReady falhou: %s", err.ToString());
      Cleanup();
      return INIT_FAILED;
   }
   if(InpResetCustomSymbolBars)
   {
      if(!CustomRatesDelete(g_csName, 0, LONG_MAX))
         PrintFormat("WARN: CustomRatesDelete falhou: lastErr=%d (segue sem wipe)",
                     GetLastError());
      else
         Print("CS: bars antigas removidas");
   }
   g_nextBarTime = AlignDownToM1(TimeCurrent());

   // Sinks: writer (.mksbk) + Custom Symbol (chart). Agregados via
   // multiSink, que apenas referencia — Cleanup deleta cada um.
   g_sink = new CBrickWriterSink();
   g_sink.writer      = g_writer;
   g_sink.printBricks = InpPrintBricks;
   g_sink.digits      = g_digits;

   g_csSink = new CCustomSymbolSink();
   g_csSink.csName      = g_csName;
   g_csSink.nextBarTime = g_nextBarTime;

   g_multiSink = new CMultiSink();
   g_multiSink.Add(g_sink);
   g_multiSink.Add(g_csSink);

   g_builder = new CMksRenkoBuilder(geom, g_sizer, g_multiSink,
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

   int totalBricks  = (g_sink   != NULL) ? g_sink.bricksWritten    : 0;
   int writeFails   = (g_sink   != NULL) ? g_sink.writeFailures    : 0;
   int csBars       = (g_csSink != NULL) ? g_csSink.barsPushed     : 0;
   int csFails      = (g_csSink != NULL) ? g_csSink.updateFailures : 0;
   long fileBricks  = (g_writer != NULL) ? g_writer.BrickCount()   : 0;

   Print("");
   Print("=== RELATORIO Producer ===");
   PrintFormat("deinit reason: %d", reason);
   PrintFormat("ticks ingeridos (seq): %I64u", g_seq);
   PrintFormat("bricks: total=%d (writer count=%I64d) writeFailures=%d",
               totalBricks, fileBricks, writeFails);
   PrintFormat("custom symbol: %s bars=%d updateFailures=%d",
               g_csName, csBars, csFails);
   PrintFormat("histórico: ticks=%d bricks=%d", g_histLoaded, g_histBricks);
   PrintFormat("erros: 102=%d 103=%d (logados=%d) 104=%s",
               g_k102Seen, g_invalidSeen, g_invalidLogged,
               (g_streamHalted ? "yes" : "no"));
   PrintFormat("arquivo: %s", g_filePath);
   Print("=== fim ===");

   Cleanup();
}
//+------------------------------------------------------------------+