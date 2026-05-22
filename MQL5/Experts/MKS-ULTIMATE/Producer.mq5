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
//|                   Core/Data/CMksBrickWriterSink.mqh,
//|                   Core/Output/CMksCustomSymbolSink.mqh,
//|                   Core/Output/CMksMultiSink.mqh,
//|                   Core/Log/CMksLogger.mqh,
//|                   Core/Symbol/CMksMt5Symbol.mqh,
//|                   Core/Account/CMksMt5Account.mqh,
//|                   Core/Types/RenkoGeometry.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/Error.mqh,
//|                   Core/Interfaces/ISymbol.mqh,
//|                   Core/Interfaces/IAccount.mqh
//| @install_path   : MQL5/Experts/MKS-ULTIMATE/Producer.mq5
//+------------------------------------------------------------------+
#property strict

#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksRenkoBuilder.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksFixedBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickFileWriter.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickWriterSink.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksCustomSymbolSink.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksMultiSink.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksProgressPanel.mqh>
#include <MKS-ULTIMATE/Core/Log/CMksLogger.mqh>
#include <MKS-ULTIMATE/Core/Symbol/CMksMt5Symbol.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksMt5Account.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IAccount.mqh>

// ADR-022: inputs em grupos. Tipo de geometria selecionável.
enum ENUM_MKS_GEOMETRY_TYPE
{
   MKS_GEOM_MEDIAN  = 0,  // Median Renko (pro/po 0.50/0.50)
   MKS_GEOM_CLASSIC = 1,  // Classic Renko (pro/po 0.00/0.00)
   MKS_GEOM_CUSTOM  = 2   // Custom (usa InpPro/InpPo)
};

input group "=== Brick / Geometria ==="
input ENUM_MKS_GEOMETRY_TYPE InpGeometryType = MKS_GEOM_MEDIAN; // Tipo (Median/Classic/Custom)
input double InpBrickSizePts          = 3.0;   // Brick Size (em pontos do símbolo)
input double InpPro                   = 0.50;  // PRO — só usado se Type = Custom
input double InpPo                    = 0.50;  // PO  — só usado se Type = Custom

input group "=== Histórico / Live ==="
input int    InpHistoricalFillDays    = 30;    // Histórico (dias). 0 = só live.
input int    InpInvalidTickLimit      = 10;    // L: ticks inválidos consecutivos antes de halt (ADR-006)
input int    InpThresholdLimit        = 20;    // K: máx thresholds em um tick (ADR-011)

input group "=== Custom Symbol ==="
input bool   InpShowWicksInCS         = false; // Mostrar wicks de excursão no CS (ADR-022 §3)
input bool   InpResetCustomSymbolBars = true;  // Wipe bars antigas no OnInit

input group "=== Logging ==="
input bool   InpPrintBricks           = false; // Verbose: imprime cada brick no journal
input int    InpInvalidLogEvery       = 100;   // Rate-limit do log 103 (1 a cada N)
input bool   InpLogToFile             = true;  // Grava .log em MKS-ULTIMATE\Logs\ (ADR-007)

string   g_symbol         = "";
int      g_digits         = 0;
string   g_broker         = "";
long     g_account        = 0;
string   g_filePath       = "";
string   g_logPath        = "";
string   g_csName         = "";
datetime g_nextBarTime    = 0;
ulong    g_seq            = 0;
int      g_invalidLogged  = 0;
int      g_invalidSeen    = 0;
int      g_k102Seen       = 0;
bool     g_streamHalted   = false;
int      g_histLoaded     = 0;
int      g_histBricks     = 0;

CMksFixedBrickSizer  *g_sizer    = NULL;
CMksBrickFileWriter  *g_writer   = NULL;
CMksRenkoBuilder     *g_builder  = NULL;
CMksLogger           *g_logger   = NULL;
ISymbol              *g_iSymbol  = NULL;
IAccount             *g_iAccount = NULL;

// Sinks extraídos para Core/Output/ e Core/Data/ (ADR-020 §Consequências).
CMksBrickWriterSink  *g_sink      = NULL;
CMksCustomSymbolSink *g_csSink    = NULL;
CMksMultiSink        *g_multiSink = NULL;

// Painel UX (ADR-022). Painel só existe em chart real (não em backtest).
CMksProgressPanel    g_panel;
bool                 g_isTesting = false;

// Estado do fill histórico em chunks (refactor OnInit -> OnTimer):
// CopyTicksRange retorna tudo de uma vez, mas o loop de IngestOne é
// dividido em fatias para permitir update do painel a cada chunk.
MqlTick              g_histTicks[];
int                  g_histPos          = 0;
int                  g_histTotalTicks   = 0;
int                  g_bricksAtFillStart = 0;
bool                 g_fillRunning      = false;
bool                 g_fillRequested    = false; // OnInit pediu fill?

// Para Ticks/s no modo live.
ulong                g_lastSeqLive = 0;
uint                 g_lastTimerMs = 0;
double               g_ticksPerSec = 0.0;

//+------------------------------------------------------------------+
//| Nome do Custom Symbol — ADR-022 regra 5.                           |
//| Formato:                                                            |
//|   Median/Classic:  <symbol>.MKS_<typeCode>_<sizeStr>                |
//|   Custom:          <symbol>.MKS_X_<sizeStr>_<proInt>_<poInt>        |
//| typeCode: M / C / X. sizeStr inteiro quando size é inteiro, senão  |
//| 2 casas decimais. proInt/poInt = round(pro*100), round(po*100).    |
//+------------------------------------------------------------------+
string BuildCustomSymbolName(const string &symbol,
                             ENUM_MKS_GEOMETRY_TYPE type,
                             double sizePts,
                             double pro,
                             double po)
{
   string sizeStr;
   if(MathAbs(sizePts - MathRound(sizePts)) < 1e-9)
      sizeStr = StringFormat("%d", (int)MathRound(sizePts));
   else
      sizeStr = DoubleToString(sizePts, 2);

   string typeCode;
   switch(type)
   {
      case MKS_GEOM_MEDIAN:  typeCode = "M"; break;
      case MKS_GEOM_CLASSIC: typeCode = "C"; break;
      case MKS_GEOM_CUSTOM:  typeCode = "X"; break;
      default:               typeCode = "?"; break;
   }

   if(type == MKS_GEOM_CUSTOM)
   {
      int proInt = (int)MathRound(pro * 100.0);
      int poInt  = (int)MathRound(po  * 100.0);
      return StringFormat("%s.MKS_X_%s_%d_%d", symbol, sizeStr, proInt, poInt);
   }
   return StringFormat("%s.MKS_%s_%s", symbol, typeCode, sizeStr);
}

//+------------------------------------------------------------------+
//| Constrói a MksRenkoGeometry conforme InpGeometryType (ADR-022 §1). |
//+------------------------------------------------------------------+
MksRenkoGeometry BuildGeometry(ENUM_MKS_GEOMETRY_TYPE type, double pro, double po)
{
   switch(type)
   {
      case MKS_GEOM_MEDIAN:  return MksGeometryMedian();
      case MKS_GEOM_CLASSIC: return MksGeometryClassic();
      case MKS_GEOM_CUSTOM:
      {
         MksRenkoGeometry g;
         g.pro = pro;
         g.po  = po;
         g.revSizeRatio = 1.0;
         return g;
      }
   }
   return MksGeometryMedian(); // fallback inerte; OnInit aborta antes
}

//+------------------------------------------------------------------+
//| Cria ou recupera o Custom Symbol. Replica propriedades imutáveis  |
//| do símbolo base (Setar SYMBOL_DIGITS/POINT/CHART_MODE/TICK_SIZE   |
//| APAGA o histórico do CS — efeito simétrico com ADR-014). Seleciona |
//| em Market Watch (requisito de fato para CustomRatesUpdate).        |
//+------------------------------------------------------------------+
bool EnsureCustomSymbolReady(const string &cs, ISymbol *src, MksError &err)
{
   if(src == NULL)
   {
      MKS_SET_ERROR(err, MKS_ERR_CORE_INVALID_ARGUMENT,
                    "EnsureCustomSymbolReady: ISymbol nulo", cs);
      return false;
   }
   string srcName = src.Name();
   bool exists = (SymbolInfoInteger(cs, SYMBOL_CUSTOM) == 1);
   if(!exists)
   {
      if(!CustomSymbolCreate(cs, "MKS-ULTIMATE", srcName))
      {
         int lastErr = GetLastError();
         if(lastErr != 5304) // 5304 = símbolo já existe (race)
         {
            MKS_SET_ERROR(err, MKS_ERR_DATA_FILE_IO,
                          "CustomSymbolCreate falhou",
                          StringFormat("cs=%s src=%s lastErr=%d",
                                       cs, srcName, lastErr));
            return false;
         }
      }
   }

   CustomSymbolSetInteger(cs, SYMBOL_DIGITS,        src.Digits());
   CustomSymbolSetInteger(cs, SYMBOL_CHART_MODE,    (long)SYMBOL_CHART_MODE_BID);
   CustomSymbolSetDouble (cs, SYMBOL_POINT,                src.Point());
   CustomSymbolSetDouble (cs, SYMBOL_TRADE_TICK_SIZE,      src.TickSize());
   CustomSymbolSetDouble (cs, SYMBOL_TRADE_TICK_VALUE,     src.TickValue());
   CustomSymbolSetDouble (cs, SYMBOL_TRADE_CONTRACT_SIZE,  src.ContractSize());
   CustomSymbolSetString (cs, SYMBOL_CURRENCY_BASE,   src.BaseCurrency());
   CustomSymbolSetString (cs, SYMBOL_CURRENCY_PROFIT, src.ProfitCurrency());
   CustomSymbolSetString (cs, SYMBOL_CURRENCY_MARGIN, src.MarginCurrency());

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
         g_logger.Warn("Producer", "invalid tick (rate-limited)",
            StringFormat("\"code\":103,\"seen\":%d,\"every\":%d,\"err\":\"%s\"",
                         g_invalidSeen, InpInvalidLogEvery,
                         MksJsonEscape(err.ToString())));
      }
   }
   else if(err.code == MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED)
   {
      g_k102Seen++;
      g_logger.Warn("Producer", "threshold limit K exceeded",
         StringFormat("\"code\":102,\"err\":\"%s\"",
                      MksJsonEscape(err.ToString())));
   }
   else if(err.code == MKS_ERR_RENKO_TICK_STREAM_CORRUPT)
   {
      g_streamHalted = true;
      g_logger.Error("Producer", "tick stream corrupt, builder halted",
         StringFormat("\"code\":104,\"err\":\"%s\"",
                      MksJsonEscape(err.ToString())));
   }
   else
   {
      g_logger.Error("Producer", "ingest error",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
   }
}

//+------------------------------------------------------------------+
//| Histórico em chunks. CopyTicksRange é síncrono (1-3s para 1.7M    |
//| ticks), mas o LOOP de IngestOne é dividido em fatias via OnTimer  |
//| para permitir update do painel UX. Suprime OnBrickForming durante |
//| fill (ADR-021): milhões de CustomRatesUpdate travariam o terminal.|
//+------------------------------------------------------------------+
const int kHistChunkSize = 10000; // ticks por chunk no OnTimer

bool StartHistoricalFill(int days)
{
   if(days <= 0)
   {
      g_logger.Info("Producer", "historical fill: skipped (days=0)", "");
      return false;
   }
   long toMsc   = (long)TimeCurrent() * 1000;
   long fromMsc = toMsc - (long)days * 24L * 3600L * 1000L;

   int n = CopyTicksRange(g_symbol, g_histTicks, COPY_TICKS_ALL, fromMsc, toMsc);
   if(n <= 0)
   {
      g_logger.Warn("Producer", "historical fill: CopyTicksRange failed",
         StringFormat("\"ret\":%d,\"lastErr\":%d", n, GetLastError()));
      return false;
   }
   g_histLoaded         = n;
   g_histTotalTicks     = n;
   g_histPos            = 0;
   g_bricksAtFillStart  = g_sink.bricksWritten;
   g_fillRunning        = true;
   g_builder.SetEmitForming(false); // evita 1.7M CustomRatesUpdate durante fill

   g_logger.Info("Producer", "historical fill: ticks loaded",
      StringFormat("\"ticks\":%d,\"days\":%d", n, days));
   return true;
}

// Processa próximo chunk. Retorna true se ainda há ticks a processar.
bool ProcessHistoricalChunk()
{
   if(!g_fillRunning) return false;
   int end = MathMin(g_histPos + kHistChunkSize, g_histTotalTicks);
   for(int i = g_histPos; i < end; i++)
   {
      MksTick t = ToMksTick(g_histTicks[i]);
      IngestOne(t);
      if(g_streamHalted) break;
   }
   g_histPos = end;
   return (g_histPos < g_histTotalTicks) && !g_streamHalted;
}

// Termina o fill: libera builder.SetEmitForming, loga totais.
void FinalizeHistoricalFill()
{
   if(!g_fillRunning) return;
   g_fillRunning = false;
   g_builder.SetEmitForming(true);
   g_histBricks = g_sink.bricksWritten - g_bricksAtFillStart;
   ArrayFree(g_histTicks);
   g_logger.Info("Producer", "historical fill: bricks emitted",
      StringFormat("\"bricks\":%d", g_histBricks));
}

// Helper: nome legível do tipo de geometria (pra painel/log).
string GeometryTypeName(ENUM_MKS_GEOMETRY_TYPE t)
{
   switch(t)
   {
      case MKS_GEOM_MEDIAN:  return "Median";
      case MKS_GEOM_CLASSIC: return "Classic";
      case MKS_GEOM_CUSTOM:  return "Custom";
   }
   return "?";
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
   if(g_logger     != NULL) { delete g_logger;     g_logger     = NULL; }
   if(g_iSymbol    != NULL) { delete g_iSymbol;    g_iSymbol    = NULL; }
   if(g_iAccount   != NULL) { delete g_iAccount;   g_iAccount   = NULL; }
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = _Symbol;

   // Backtest guard (ADR-022): painel UX só aparece em chart real.
   // No tester, MQLInfoInteger(MQL5_TESTING) == 1 — consulta na borda
   // do composition root é permitida (ADR-015 §3) para ajuste de output.
   g_isTesting = (bool)MQLInfoInteger(MQL_TESTER);

   // Painel UX: criar IMEDIATAMENTE para feedback de "EA está vivo".
   // Setup pode demorar 1-3s (CustomSymbolCreate, wipe), fill 20-40s.
   // Sem o painel agora, usuário pensa que travou.
   if(!g_isTesting)
   {
      g_panel.InitMode(g_symbol, "<calculando>",
                       "Inicializando MKS-ULTIMATE...");
   }

   // Composition root: instancia as interfaces para o instrumento e a
   // conta corrente. ADR-016: lógica futura consulta via interface; só
   // a borda do composition root toca CMksMt5Symbol/Account direto.
   g_iSymbol  = new CMksMt5Symbol(g_symbol);
   g_iAccount = new CMksMt5Account();

   g_digits  = g_iSymbol.Digits();
   g_broker  = g_iAccount.Company();
   g_account = g_iAccount.Login();

   datetime sessionStart = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(sessionStart, dt);
   string stamp = StringFormat("%04d%02d%02dT%02d%02d%02d",
                               dt.year, dt.mon, dt.day,
                               dt.hour, dt.min, dt.sec);

   // Pastas. FileOpen não cria recursivamente — criar nível por nível.
   FolderCreate("MKS-ULTIMATE");
   FolderCreate("MKS-ULTIMATE\\Bricks");
   FolderCreate("MKS-ULTIMATE\\Logs");

   if(!g_isTesting) g_panel.UpdateSubtitle("Inicializando logger...");

   // Logger antes de tudo — todas mensagens posteriores vão para JSON-line.
   g_logger = new CMksLogger();
   g_logPath = StringFormat("MKS-ULTIMATE\\Logs\\%s_%s.log", g_symbol, stamp);
   MksError err;
   if(!g_logger.Open(g_logPath, MKS_LOG_INFO, true, InpLogToFile, err))
   {
      PrintFormat("OnInit: logger.Open falhou: %s", err.ToString());
      Cleanup();
      return INIT_FAILED;
   }
   g_logger.WriteHeader(g_broker, g_account, g_symbol, g_digits,
                        "Producer", (long)sessionStart * 1000);
   g_logger.Info("Producer", "starting",
      StringFormat("\"S\":%.4f,\"preset\":\"median\",\"L\":%d,\"K\":%d,"
                   "\"histDays\":%d,\"printBricks\":%s,\"resetCS\":%s",
                   InpBrickSizePts, InpInvalidTickLimit, InpThresholdLimit,
                   InpHistoricalFillDays,
                   (InpPrintBricks ? "true" : "false"),
                   (InpResetCustomSymbolBars ? "true" : "false")));

   // Sizer (heap para que cleanup parcial seja uniforme).
   g_sizer = new CMksFixedBrickSizer(InpBrickSizePts);
   if(!g_sizer.Validate(err))
   {
      g_logger.Error("Producer", "sizer invalid",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }

   // ADR-022: geometry dinâmica via InpGeometryType.
   MksRenkoGeometry geom = BuildGeometry(InpGeometryType, InpPro, InpPo);
   if(!geom.Validate(err))
   {
      g_logger.Error("Producer", "geometry invalid",
         StringFormat("\"type\":%d,\"err\":\"%s\"",
                      (int)InpGeometryType, MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }
   g_logger.Info("Producer", "geometry",
      StringFormat("\"type\":%d,\"pro\":%.4f,\"po\":%.4f",
                   (int)InpGeometryType, geom.pro, geom.po));

   if(!g_isTesting) g_panel.UpdateSubtitle("Abrindo arquivo .mksbk...");

   // Writer com retry de sufixo numérico em caso de colisão (ADR-014 §4).
   // Reutiliza sessionStart já capturado para o log (mesmo timestamp em
   // ambos os arquivos: .log e .mksbk).
   g_writer = new CMksBrickFileWriter();
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
      g_logger.Info("Producer", "mksbk filename collision, retrying",
         StringFormat("\"path\":\"%s\",\"attempt\":%d",
                      MksJsonEscape(g_filePath), attempt + 1));
   }
   if(!opened)
   {
      g_logger.Error("Producer", "writer.Open failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_FAILED;
   }
   g_logger.Info("Producer", "mksbk opened",
      StringFormat("\"path\":\"%s\"", MksJsonEscape(g_filePath)));
   if(!g_writer.WriteHeader(g_broker, g_account, g_symbol, g_digits,
                            geom, InpBrickSizePts, err))
   {
      g_logger.Error("Producer", "writer.WriteHeader failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_FAILED;
   }

   // Custom Symbol: replica propriedades do símbolo base, opcionalmente
   // limpa bars antigas (simétrico com ADR-014: sessão nova = histórico
   // limpo). Setado APÓS WriteHeader do .mksbk para que uma falha aqui
   // não bagunce a invariante do writer.
   // ADR-022: naming carrega tipo + tamanho + pro/po (se Custom).
   g_csName = BuildCustomSymbolName(g_symbol, InpGeometryType,
                                    InpBrickSizePts, InpPro, InpPo);
   if(StringLen(g_csName) > 32)
   {
      g_logger.Error("Producer", "custom symbol name exceeds 32 chars",
         StringFormat("\"name\":\"%s\",\"len\":%d",
                      MksJsonEscape(g_csName), StringLen(g_csName)));
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }
   g_logger.Info("Producer", "custom symbol",
      StringFormat("\"name\":\"%s\"", MksJsonEscape(g_csName)));

   // Atualiza painel: agora temos o csName real para mostrar.
   if(!g_isTesting)
   {
      ObjectSetString(ChartID(), MKS_PANEL_PREFIX + "FLOW", OBJPROP_TEXT,
                      g_symbol + " -> " + g_csName);
      g_panel.UpdateSubtitle("Criando Custom Symbol...");
   }

   if(!EnsureCustomSymbolReady(g_csName, g_iSymbol, err))
   {
      g_logger.Error("Producer", "EnsureCustomSymbolReady failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      if(!g_isTesting) g_panel.ShowError("Falha ao criar Custom Symbol");
      Cleanup();
      return INIT_FAILED;
   }
   if(InpResetCustomSymbolBars)
   {
      if(!g_isTesting) g_panel.UpdateSubtitle("Limpando histórico anterior...");
      if(!CustomRatesDelete(g_csName, 0, LONG_MAX))
         g_logger.Warn("Producer", "CustomRatesDelete failed (continues without wipe)",
            StringFormat("\"lastErr\":%d", GetLastError()));
      else
         g_logger.Info("Producer", "cs bars wiped", "");
   }
   g_nextBarTime = AlignDownToM1(TimeCurrent());

   // Sinks: writer (.mksbk) + Custom Symbol (chart). Agregados via
   // multiSink, que apenas referencia — Cleanup deleta cada um.
   g_sink = new CMksBrickWriterSink();
   g_sink.writer      = g_writer;
   g_sink.printBricks = InpPrintBricks;
   g_sink.digits      = g_digits;

   g_csSink = new CMksCustomSymbolSink();
   g_csSink.csName       = g_csName;
   g_csSink.nextBarTime  = g_nextBarTime;
   g_csSink.brickSizePts = InpBrickSizePts;  // ADR-022 regra 8
   g_csSink.showWicks    = InpShowWicksInCS; // ADR-022 regra 3

   g_multiSink = new CMksMultiSink();
   g_multiSink.Add(g_sink);
   g_multiSink.Add(g_csSink);

   g_builder = new CMksRenkoBuilder(geom, g_sizer, g_multiSink,
                                    InpInvalidTickLimit, InpThresholdLimit);

   // Fill histórico em chunks via OnTimer (ADR-022 §UX): OnInit precisa
   // retornar rápido para o terminal renderizar o painel. CopyTicksRange
   // é síncrono (alguns segundos), mas o LOOP de IngestOne é dividido.
   if(!g_isTesting)
      g_panel.UpdateSubtitle(StringFormat("Carregando %d dias de histórico...",
                                          InpHistoricalFillDays));
   g_fillRequested = StartHistoricalFill(InpHistoricalFillDays);

   // Dispara o ciclo de OnTimer. 50ms é granular o bastante para o painel
   // parecer animado, e processa ~10k ticks por tick de timer (>= 200k tps
   // em throughput, suficiente para 1.7M ticks em < 10s no fluxo real).
   EventSetMillisecondTimer(50);

   g_logger.Info("Producer", "OnInit done; fill+ChartOpen via OnTimer",
      StringFormat("\"fillRequested\":%s", (g_fillRequested ? "true" : "false")));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Finaliza o ciclo de init: abre chart do CS, transição do painel   |
//| para modo live, troca timer para 1Hz. Chamado quando fill termina |
//| (ou imediatamente se !g_fillRequested).                            |
//+------------------------------------------------------------------+
void FinishInitAndGoLive()
{
   FinalizeHistoricalFill();

   // ADR-022 §6: abre chart do CS em M1.
   long chartId = ChartOpen(g_csName, PERIOD_M1);
   if(chartId == 0)
   {
      g_logger.Warn("Producer", "ChartOpen failed (continues without auto-open)",
         StringFormat("\"cs\":\"%s\",\"lastErr\":%d",
                      MksJsonEscape(g_csName), GetLastError()));
   }
   else
   {
      g_logger.Info("Producer", "cs chart opened",
         StringFormat("\"cs\":\"%s\",\"chartId\":%I64d",
                      MksJsonEscape(g_csName), chartId));
   }

   // Transição painel para modo live.
   if(!g_isTesting)
   {
      g_panel.LiveMode(g_symbol, g_csName,
                       GeometryTypeName(InpGeometryType),
                       InpBrickSizePts, TimeCurrent());
   }

   g_logger.Info("Producer", "ready, processing live ticks", "");

   // Reduz frequência do timer: live só precisa de update 1Hz para
   // ticks/sec, último brick, sync.
   EventKillTimer();
   EventSetTimer(1);
   g_lastSeqLive = g_seq;
   g_lastTimerMs = GetTickCount();
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(g_streamHalted || g_builder == NULL) return;
   // Durante fill histórico, ignorar ticks live (eles entram via OnTick
   // depois que FinishInitAndGoLive transiciona para modo live).
   if(g_fillRunning) return;

   MqlTick mt;
   if(!SymbolInfoTick(g_symbol, mt)) return;

   MksTick t = ToMksTick(mt);
   IngestOne(t);
}

//+------------------------------------------------------------------+
//| OnTimer — duas funções por fase:                                  |
//|   Fase init (g_fillRunning): processa próximo chunk de ticks      |
//|     históricos; quando termina, chama FinishInitAndGoLive.        |
//|   Fase live: atualiza painel com ticks/sec, último brick, sync.   |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_fillRunning)
   {
      bool more = ProcessHistoricalChunk();
      // Atualiza painel.
      if(!g_isTesting)
      {
         double pct = 0.0;
         if(g_histTotalTicks > 0)
            pct = 100.0 * g_histPos / g_histTotalTicks;
         g_panel.UpdateProgress(pct, g_histPos, g_histTotalTicks,
                                 g_sink != NULL ? g_sink.bricksWritten : 0);
      }
      if(!more)
         FinishInitAndGoLive();
      return;
   }

   // Modo live: update painel 1Hz.
   if(!g_isTesting && g_panel.Mode() == MKS_PANEL_MODE_LIVE)
   {
      uint nowMs = GetTickCount();
      double elapsedSec = (nowMs - g_lastTimerMs) / 1000.0;
      if(elapsedSec > 0.05)
      {
         ulong dseq = g_seq - g_lastSeqLive;
         g_ticksPerSec = dseq / elapsedSec;
         g_lastSeqLive = g_seq;
         g_lastTimerMs = nowMs;
      }
      long bricksTotal = g_sink != NULL ? g_sink.bricksWritten : 0;
      long writerCount = g_writer != NULL ? g_writer.BrickCount() : 0;
      string lastInfo = "—";
      // Pequena info do último brick (lê do builder snapshot).
      // GetFormingBrick() é leve: snapshot de campos.
      if(g_builder != NULL)
      {
         MksFormingBrick fb = g_builder.GetFormingBrick();
         if(fb.hasData)
         {
            lastInfo = StringFormat("%s @ %s",
                                     fb.direction == MKS_BRICK_BULL ? "BULL" : "BEAR",
                                     DoubleToString(fb.open, g_digits));
         }
      }
      g_panel.UpdateLive(bricksTotal, writerCount, lastInfo, g_ticksPerSec);
   }
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(!g_isTesting) g_panel.Clear();

   if(g_writer != NULL)
   {
      MksError err;
      if(!g_writer.Close(err) && g_logger != NULL)
         g_logger.Error("Producer", "writer.Close failed",
            StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
   }

   int totalBricks  = (g_sink   != NULL) ? g_sink.bricksWritten    : 0;
   int writeFails   = (g_sink   != NULL) ? g_sink.writeFailures    : 0;
   int csBars       = (g_csSink != NULL) ? g_csSink.barsPushed     : 0;
   int csFails      = (g_csSink != NULL) ? g_csSink.updateFailures : 0;
   long fileBricks  = (g_writer != NULL) ? g_writer.BrickCount()   : 0;

   if(g_logger != NULL)
   {
      g_logger.Info("Producer", "session summary",
         StringFormat(
            "\"deinitReason\":%d,\"ticksIngested\":%I64u,"
            "\"bricksTotal\":%d,\"writerCount\":%I64d,\"writeFailures\":%d,"
            "\"csName\":\"%s\",\"csBars\":%d,\"csUpdateFailures\":%d,"
            "\"histTicks\":%d,\"histBricks\":%d,"
            "\"err102\":%d,\"err103\":%d,\"err103Logged\":%d,\"streamHalted\":%s,"
            "\"mksbkPath\":\"%s\",\"logPath\":\"%s\"",
            reason, g_seq,
            totalBricks, fileBricks, writeFails,
            MksJsonEscape(g_csName), csBars, csFails,
            g_histLoaded, g_histBricks,
            g_k102Seen, g_invalidSeen, g_invalidLogged,
            (g_streamHalted ? "true" : "false"),
            MksJsonEscape(g_filePath), MksJsonEscape(g_logPath)));
      g_logger.Close();
   }

   Cleanup();
}
//+------------------------------------------------------------------+