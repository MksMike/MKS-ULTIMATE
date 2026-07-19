//+------------------------------------------------------------------+
//| @file           : ColorReversal.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Experts / MKS-ULTIMATE
//| @responsibility : EA da Fase 9 — primeiro fim-a-fim usando o core
//|                   completo. Composition root: builder + sinks
//|                   (writer + CS + audit + strategy) + risk (3 camadas)
//|                   + sizer + broker live (via CMksMt5Broker gatekeeped
//|                   por CMksRiskGatedBroker). Estratégia: reversão de
//|                   cor pura (close-and-reverse a cada flip, SL fixo,
//|                   sem TP). Magic próprio (527001 default). Auto-detach
//|                   via CMksMt5PositionBook injetado na strategy.
//|                   Geometria FIXA em classic (ADR-026). Sem StressLab
//|                   nesta versão — runner stress é slice separado que
//|                   reusa CMksColorReversalStrategy sobre SimulatedBroker
//|                   + StressLabBroker + replayer de .mkstick.
//| @depends_on     : Strategy/CMksColorReversalStrategy.mqh,
//|                   Core/RenkoBuilder/CMksRenkoBuilder.mqh,
//|                   Core/RenkoBuilder/CMksFixedBrickSizer.mqh,
//|                   Core/Data/CMksBrickFileWriter.mqh,
//|                   Core/Data/CMksBrickWriterSink.mqh,
//|                   Core/Data/TickBatchCursor.mqh,
//|                   Core/Output/CMksCustomSymbolSink.mqh,
//|                   Core/Output/CMksAuditLogSink.mqh,
//|                   Core/Output/CMksMultiSink.mqh,
//|                   Core/Broker/CMksMt5Broker.mqh,
//|                   Core/Risk/CMksRiskManager.mqh,
//|                   Core/Risk/CMksRiskGatedBroker.mqh,
//|                   Core/Position/CMksMt5PositionBook.mqh,
//|                   Core/Account/CMksAccountSnapshot.mqh,
//|                   Core/Trade/CMksFixedLotSizer.mqh,
//|                   Core/Trade/CMksPercentRiskSizer.mqh,
//|                   Core/Clock/CMksMt5Clock.mqh,
//|                   Core/Log/CMksLogger.mqh,
//|                   Core/Symbol/CMksMt5Symbol.mqh,
//|                   Core/Account/CMksMt5Account.mqh,
//|                   Core/Types/*
//| @install_path   : MQL5/Experts/MKS-ULTIMATE/ColorReversal.mq5
//+------------------------------------------------------------------+
#property strict

#include <MKS-ULTIMATE/Strategy/CMksColorReversalStrategy.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksRenkoBuilder.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksFixedBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickFileWriter.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickWriterSink.mqh>
#include <MKS-ULTIMATE/Core/Data/TickBatchCursor.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksCustomSymbolSink.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksAuditLogSink.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksChartPainter.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksMultiSink.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksMt5Broker.mqh>
#include <MKS-ULTIMATE/Core/Risk/CMksRiskManager.mqh>
#include <MKS-ULTIMATE/Core/Risk/CMksRiskGatedBroker.mqh>
#include <MKS-ULTIMATE/Core/Position/CMksMt5PositionBook.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksAccountSnapshot.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksMt5Account.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksFixedLotSizer.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksPercentRiskSizer.mqh>
#include <MKS-ULTIMATE/Core/Clock/CMksMt5Clock.mqh>
#include <MKS-ULTIMATE/Core/Log/CMksLogger.mqh>
#include <MKS-ULTIMATE/Core/Symbol/CMksMt5Symbol.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//--- Inputs --------------------------------------------------------
input group "=== Brick (classic geometry — ADR-026) ==="
input double InpBrickSize           = 3.0;   // Tamanho do brick (price units; XAU em USD)
input int    InpInvalidTickLimit    = 10;    // L (ADR-006)
input int    InpThresholdLimit      = 20;    // K (ADR-011)

input group "=== Estratégia ==="
input long   InpMagicNumber         = 527001; // Identificador único desta estratégia
input double InpSlPoints            = 3000.0; // SL fixo em pontos do símbolo (=10 bricks em XAU/S=3.0). OnInit recusa anexar se < piso mínimo = max(InpMinSlFloorPts, InpMinSlBricks·brickSize) — E0.3/M12.
input string InpComment             = "ColorReversal"; // Comentário das ordens

input group "=== Sizing ==="
enum ENUM_CR_LOT_MODE
{
   CR_LOT_FIXED = 0,    // Lots fixos
   CR_LOT_PERCENT = 1   // % do balance / SL distance
};
input ENUM_CR_LOT_MODE InpLotMode   = CR_LOT_FIXED;
input double InpFixedLots           = 0.01;  // Usado se InpLotMode = FIXED
input double InpRiskPct             = 0.5;   // Usado se InpLotMode = PERCENT (% do balance por trade)

input group "=== Risk Manager — Por Trade ==="
input bool   InpRequireSl           = true;
input bool   InpRequireTp           = false; // Por design (color reversal não usa TP)
input double InpMaxLotsPerTrade     = 1.0;
input int    InpMinSlBricks         = 1;     // Piso de SL em bricks (>=1; mata o M12: StopsLevel=0 não desliga o gate)
input double InpMinSlFloorPts       = 0.0;   // Belt absoluto opcional do piso, em pontos (0 = só o piso de brick)

input group "=== Risk Manager — Por Estratégia ==="
input int    InpMaxOpenPositions    = 1;     // Color reversal: máx 1 posição
input double InpMaxTotalLots        = 1.0;

input group "=== Risk Manager — Por Conta ==="
input double InpMaxDailyLossPct     = 5.0;
input double InpMaxDrawdownPct      = 10.0;
input double InpMinEquityAbs        = 0.0;   // 0 = sem circuit breaker absoluto

input group "=== Custom Symbol ==="
input bool   InpResetCustomSymbolBars = true;
input bool   InpShowWicksInCS         = false;

input group "=== Visualização (ADR-028) ==="
input bool   InpShowTradeMarkers      = true;  // setas de entrada/saída + linha P&L no chart (live: sobre CS; tester: sobre M1)
input color  InpVizArrowBuy           = clrDodgerBlue;  // seta de entrada BUY
input color  InpVizArrowSell          = clrOrangeRed;   // seta de entrada SELL
input color  InpVizArrowBorder        = clrWhite;       // borda (halo) das setas
input color  InpVizLineProfit         = clrLimeGreen;   // linha conectora — trade com lucro
input color  InpVizLineLoss           = clrCrimson;     // linha conectora — trade com prejuízo

input group "=== Histórico ==="
input int    InpHistoricalFillDays    = 3;     // dias de bricks históricos no CS/.mksbk no live (0 = só live). Estratégia NÃO opera no histórico.

input group "=== Logging ==="
input bool   InpPrintBricks         = false;
input bool   InpLogToFile           = true;
input bool   InpAlsoWriteAudit      = true;  // audit.tsv complementar ao .mksbk

//--- State global --------------------------------------------------
string                g_symbol         = "";
int                   g_digits         = 0;
string                g_broker         = "";
long                  g_account        = 0;
string                g_csName         = "";
datetime              g_nextBarTime    = 0;
ulong                 g_seq            = 0;
string                g_filePath       = "";
string                g_logPath        = "";
string                g_auditPath      = "";
bool                  g_streamHalted   = false;
MksTickBatchCursor    g_tickCursor;              // dedup por contagem no boundary (H5)
bool                  g_isTesting      = false;  // MQL_TESTER detection (ADR-022 §UX precedent)

// Checkpoint periódico de observabilidade: a cada 60s de wall-clock,
// patcheia header do .mksbk + flush do audit TSV, para inspeção
// mid-sessão (wc -l, tail) sem destacar o EA. Em tester pula (sessão
// fecha rápido; OnDeinit já faz flush final).
const uint            kCheckpointEveryMs = 60000;
uint                  g_lastCheckpointMs = 0;

ISymbol              *g_iSymbol  = NULL;
IAccount             *g_iAccount = NULL;
IClock               *g_iClock   = NULL;

CMksFixedBrickSizer  *g_brickSizer  = NULL;
CMksBrickFileWriter  *g_writer      = NULL;
CMksBrickWriterSink  *g_brickSink   = NULL;
CMksCustomSymbolSink *g_csSink      = NULL;
CMksAuditLogSink     *g_auditSink   = NULL;
CMksChartPainter     *g_painter     = NULL;  // ADR-028 visualização de trades
long                  g_csChartId   = -1;     // chart do CS auto-aberto (live); -1 = nenhum
CMksMultiSink        *g_multiSink   = NULL;
CMksRenkoBuilder     *g_builder     = NULL;
CMksLogger           *g_logger      = NULL;

CMksMt5PositionBook  *g_book        = NULL;
CMksAccountSnapshot  *g_snapshot    = NULL;
CMksRiskManager      *g_risk        = NULL;
CMksMt5Broker        *g_mt5Broker   = NULL;
CMksRiskGatedBroker  *g_gatedBroker = NULL;
IPositionSizer       *g_lotSizer    = NULL;

CMksColorReversalStrategy *g_strategy = NULL;

//+------------------------------------------------------------------+
//| Helpers de path                                                   |
//+------------------------------------------------------------------+
string FormatTimestamp(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%04d%02d%02dT%02d%02d%02d",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

string BuildBrickFilePath(const string &symbol, datetime t, int attempt)
{
   string stamp = FormatTimestamp(t);
   string suffix = (attempt == 0) ? "" : StringFormat("_%d", attempt + 1);
   return StringFormat("MKS-ULTIMATE\\Bricks\\%s_CR_%s%s.mksbk",
                       symbol, stamp, suffix);
}

string BuildLogPath(const string &symbol, datetime t)
{
   return StringFormat("MKS-ULTIMATE\\Logs\\ColorReversal_%s_%s.log",
                       symbol, FormatTimestamp(t));
}

string BuildAuditPath(const string &symbol, datetime t)
{
   return StringFormat("MKS-ULTIMATE\\Logs\\ColorReversal_audit_%s_%s.tsv",
                       symbol, FormatTimestamp(t));
}

string BuildCustomSymbolName(const string &symbol, double size)
{
   // Naming consistente com Producer pós-ADR-026: <symbol>.MKSCR_<size>.
   // Sufixo CR distingue de CS criados pelo Producer (apenas .MKS_).
   return StringFormat("%s.MKSCR_%d", symbol, (int)MathRound(size));
}

datetime AlignDownToM1(datetime t)
{
   return t - (t % 60);
}

// Localiza o chartId de um chart aberto cujo símbolo == csName. Usado no
// live para desenhar marcadores (ADR-028) sobre as caixinhas renko do CS.
// Retorna -1 se nenhum chart do CS estiver aberto (operador não abriu).
long FindChartIdBySymbol(const string &symbolName)
{
   long cid = ChartFirst();
   while(cid >= 0)
   {
      if(ChartSymbol(cid) == symbolName) return cid;
      cid = ChartNext(cid);
   }
   return -1;
}

string MksJsonEscape(const string &s)
{
   string out = "";
   int n = StringLen(s);
   for(int i = 0; i < n; i++)
   {
      ushort c = StringGetCharacter(s, i);
      if(c == '"' || c == '\\') { out += "\\"; out += ShortToString(c); }
      else if(c == '\n') out += "\\n";
      else if(c == '\r') out += "\\r";
      else if(c == '\t') out += "\\t";
      else out += ShortToString(c);
   }
   return out;
}

// Versão idêntica à do Producer.mq5 (battle-tested em tester + live).
// 5304 = código MT5 real para "símbolo já existe" (race entre verificação
// e criação); 4302 que eu usei antes era de outro contexto e silenciava
// o caso wrong, causando OnInit failure em tester quando o CS persistia
// entre runs. Setters de SYMBOL_DIGITS/POINT/TICK_SIZE/etc são necessários
// — sem eles, MT5 não conhece a ficha técnica do custom symbol e
// SymbolSelect pode falhar downstream.
bool EnsureCustomSymbolReady(const string &cs, ISymbol *src, MksError &err)
{
   if(src == NULL)
   {
      MKS_SET_ERROR(err, MKS_ERR_CORE_INVALID_ARGUMENT,
                    "EnsureCustomSymbolReady: ISymbol nulo", cs);
      return false;
   }
   string srcName = src.Name();
   bool exists  = (SymbolInfoInteger(cs, SYMBOL_CUSTOM) == 1);
   bool created = false;
   if(!exists)
   {
      if(CustomSymbolCreate(cs, "MKS-ULTIMATE", srcName))
      {
         created = true;
      }
      else
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
         // 5304: já existe (race) — trata como existente, não reescreve specs.
      }
   }

   // Specs do símbolo base SÓ na criação genuína. Reaplicá-las a cada OnInit
   // APAGA o histórico do CS — era uma das causas da "morte" do CS (toda
   // re-anexação do EA zerava a série). O V5 setava specs uma única vez.
   if(created)
   {
      CustomSymbolSetInteger(cs, SYMBOL_DIGITS,        src.Digits());
      CustomSymbolSetInteger(cs, SYMBOL_CHART_MODE,    (long)SYMBOL_CHART_MODE_BID);
      CustomSymbolSetDouble (cs, SYMBOL_POINT,                src.Point());
      CustomSymbolSetDouble (cs, SYMBOL_TRADE_TICK_SIZE,      src.TickSize());
      CustomSymbolSetDouble (cs, SYMBOL_TRADE_TICK_VALUE,     src.TickValue());
      CustomSymbolSetDouble (cs, SYMBOL_TRADE_CONTRACT_SIZE,  src.ContractSize());
      CustomSymbolSetString (cs, SYMBOL_CURRENCY_BASE,   src.BaseCurrency());
      CustomSymbolSetString (cs, SYMBOL_CURRENCY_PROFIT, src.ProfitCurrency());
      CustomSymbolSetString (cs, SYMBOL_CURRENCY_MARGIN, src.MarginCurrency());
   }

   // Sessões 24/7 nos 7 dias, SEMPRE (idempotente; NÃO apaga histórico).
   // Sem isto o CS herda do clone as sessões reais do XAUUSDm (pausa diária +
   // fim de semana) e o MT5 recusa CustomRatesUpdate na virada de dia do
   // server (-1, GetLastError()=0) — a causa-raiz da morte do CS à meia-noite.
   // O V5 fazia exatamente isto e sobrevivia. Setar sempre também retrofita
   // sessão em CS já existentes criados por builds antigos sem ela.
   for(int d = 0; d < 7; d++)
   {
      CustomSymbolSetSessionQuote(cs, (ENUM_DAY_OF_WEEK)d, 0, 0, 86400);
      CustomSymbolSetSessionTrade(cs, (ENUM_DAY_OF_WEEK)d, 0, 0, 86400);
   }

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
//| Cleanup — libera todos os ponteiros heap-alocados                 |
//+------------------------------------------------------------------+
void Cleanup()
{
   if(g_strategy        != NULL) { delete g_strategy;        g_strategy        = NULL; }
   if(g_painter         != NULL) { delete g_painter;         g_painter         = NULL; }
   if(g_gatedBroker != NULL) { delete g_gatedBroker; g_gatedBroker = NULL; }
   if(g_mt5Broker   != NULL) { delete g_mt5Broker;   g_mt5Broker   = NULL; }
   if(g_lotSizer    != NULL) { delete g_lotSizer;    g_lotSizer    = NULL; }
   if(g_risk        != NULL) { delete g_risk;        g_risk        = NULL; }
   if(g_snapshot    != NULL) { delete g_snapshot;    g_snapshot    = NULL; }
   if(g_book        != NULL) { delete g_book;        g_book        = NULL; }
   if(g_builder     != NULL) { delete g_builder;     g_builder     = NULL; }
   if(g_multiSink   != NULL) { delete g_multiSink;   g_multiSink   = NULL; }
   if(g_auditSink   != NULL) { delete g_auditSink;   g_auditSink   = NULL; }
   if(g_csSink      != NULL) { delete g_csSink;      g_csSink      = NULL; }
   if(g_brickSink   != NULL) { delete g_brickSink;   g_brickSink   = NULL; }
   if(g_writer      != NULL) { delete g_writer;      g_writer      = NULL; }
   if(g_brickSizer  != NULL) { delete g_brickSizer;  g_brickSizer  = NULL; }
   if(g_iClock      != NULL) { delete g_iClock;      g_iClock      = NULL; }
   if(g_iAccount    != NULL) { delete g_iAccount;    g_iAccount    = NULL; }
   if(g_iSymbol     != NULL) { delete g_iSymbol;     g_iSymbol     = NULL; }
   if(g_logger      != NULL) { delete g_logger;      g_logger      = NULL; }
}

//+------------------------------------------------------------------+
//| OnInit — monta o composition root                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol  = _Symbol;
   g_digits  = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_broker  = AccountInfoString(ACCOUNT_COMPANY);
   g_account = AccountInfoInteger(ACCOUNT_LOGIN);

   // MT5 proíbe CustomSymbolCreate em Strategy Tester (erro 4014 —
   // ERR_FUNCTION_NOT_ALLOWED, limitação documentada). CS é puramente
   // visualização; estratégia recebe bricks via IRenkoSink direto.
   // Em tester, pula criação do CS e remoção do csSink do multiSink.
   g_isTesting = (bool)MQLInfoInteger(MQL_TESTER);

   datetime sessionStart = TimeCurrent();
   g_logPath   = BuildLogPath(g_symbol, sessionStart);
   g_auditPath = BuildAuditPath(g_symbol, sessionStart);

   //--- 1. Logger -------------------------------------------------+
   g_logger = new CMksLogger();
   {
      MksError err;
      if(!g_logger.Open(g_logPath, MKS_LOG_INFO, true, InpLogToFile, err))
      {
         Print("ColorReversal OnInit: logger.Open falhou: ", err.ToString());
         Cleanup();
         return INIT_FAILED;
      }
   }
   g_logger.WriteHeader(g_broker, g_account, g_symbol, g_digits,
                        "ColorReversal", (long)sessionStart * 1000);

   // GUARD: a estratégia consome ticks AO VIVO do símbolo do broker via
   // CopyTicks e constrói os próprios bricks. Um Custom Symbol (ex.:
   // XAUUSDm.MKS_3, criado pelo Producer para visualização) é container
   // ESTÁTICO de bricks históricos — não recebe feed live. Anexar o EA
   // no gráfico de um CS faz CopyTicks retornar 0 para sempre: zero
   // bricks, zero flips, zero ordens (sintoma observado em 2026-05-27 —
   // noite inteira sem ordem). Fora do tester, recusar símbolo custom
   // explicitamente para nunca mais desperdiçar uma sessão em silêncio.
   if(!g_isTesting && (bool)SymbolInfoInteger(g_symbol, SYMBOL_CUSTOM))
   {
      g_logger.Error("ColorReversal",
         "símbolo é Custom Symbol — anexe o EA no gráfico do símbolo REAL do broker",
         StringFormat("\"symbol\":\"%s\",\"hint\":\"use XAUUSDm (sem sufixo .MKS_*), não o CS de visualização\"",
                      MksJsonEscape(g_symbol)));
      Print("ColorReversal: ERRO — símbolo '", g_symbol,
            "' é um Custom Symbol (sem feed live). Anexe o EA no gráfico do símbolo REAL do broker (ex.: XAUUSDm).");
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }

   // GUARD: framework v1 é hedging-only (ADR-029). Conta netting/exchange
   // tem posição líquida por símbolo — rastreamento por positionId, partial
   // close e auto-detach dessincronizariam em silêncio (eixo 2 do V5).
   // Fail-fast aqui (antes de criar Custom Symbol/arquivos), com popup
   // explicando. O CMksMt5Broker.Init também recusa estruturalmente (backstop
   // que todo EA de trade herda). Vale em tester e live.
   {
      ENUM_ACCOUNT_MARGIN_MODE mm =
         (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         g_logger.Error("ColorReversal",
            "conta não-hedging — framework suporta apenas contas HEDGING",
            StringFormat("\"marginMode\":%d,\"hint\":\"use conta/corretora HEDGING\"",
                         (int)mm));
         Alert("MKS-ULTIMATE: conta NETTING/EXCHANGE detectada. ",
               "O framework v6 suporta apenas contas HEDGING — o EA nao vai operar. ",
               "Use uma conta/corretora com HEDGING (na Exness, um tipo de conta com hedging).");
         Print("ColorReversal: ERRO — conta nao-hedging (marginMode=", mm,
               "). MKS-ULTIMATE suporta apenas HEDGING. Troque para conta/corretora hedging.");
         Cleanup();
         return INIT_PARAMETERS_INCORRECT;
      }
   }

   g_logger.Info("ColorReversal", "starting",
      StringFormat("\"magic\":%I64d,\"S\":%.4f,\"slPts\":%.2f,\"lotMode\":\"%s\","
                   "\"fixedLots\":%.4f,\"riskPct\":%.4f,"
                   "\"maxLotsPerTrade\":%.4f,\"maxOpenPos\":%d,\"maxTotalLots\":%.4f,"
                   "\"maxDailyLossPct\":%.4f,\"maxDrawdownPct\":%.4f",
                   InpMagicNumber, InpBrickSize, InpSlPoints,
                   (InpLotMode == CR_LOT_FIXED ? "fixed" : "percent"),
                   InpFixedLots, InpRiskPct,
                   InpMaxLotsPerTrade, InpMaxOpenPositions, InpMaxTotalLots,
                   InpMaxDailyLossPct, InpMaxDrawdownPct));

   //--- 2. ISymbol / IAccount / IClock ----------------------------+
   g_iSymbol  = new CMksMt5Symbol(g_symbol);
   g_iAccount = new CMksMt5Account();
   g_iClock   = new CMksMt5Clock();

   //--- 3. Brick sizer (Fixed somente nesta versão) ---------------+
   g_brickSizer = new CMksFixedBrickSizer(InpBrickSize);
   MksError err;
   if(!g_brickSizer.Validate(err))
   {
      g_logger.Error("ColorReversal", "brick sizer invalid",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- 4. Writer .mksbk -----------------------------------------+
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
      if(err.code != MKS_ERR_DATA_FILE_EXISTS) break;
   }
   if(!opened)
   {
      g_logger.Error("ColorReversal", "writer.Open failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_FAILED;
   }
   MksRenkoGeometry geom = MksGeometryClassic();
   if(!g_writer.WriteHeader(g_broker, g_account, g_symbol, g_digits,
                            geom, InpBrickSize, err))
   {
      g_logger.Error("ColorReversal", "writer.WriteHeader failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_FAILED;
   }
   g_logger.Info("ColorReversal", "mksbk opened",
      StringFormat("\"path\":\"%s\"", MksJsonEscape(g_filePath)));

   //--- 5. Custom Symbol (skip em Strategy Tester) -----------------+
   if(g_isTesting)
   {
      g_logger.Info("ColorReversal", "tester mode — skipping Custom Symbol",
                    "\"reason\":\"CustomSymbolCreate forbidden in Strategy Tester (MT5 err 4014)\"");
      g_csName = "";  // sem CS
   }
   else
   {
      g_csName = BuildCustomSymbolName(g_symbol, InpBrickSize);
      if(!EnsureCustomSymbolReady(g_csName, g_iSymbol, err))
      {
         g_logger.Error("ColorReversal", "EnsureCustomSymbolReady failed",
            StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
         Cleanup();
         return INIT_FAILED;
      }
      if(InpResetCustomSymbolBars)
         CustomRatesDelete(g_csName, 0, LONG_MAX);

      // Auto-open do chart do CS (ADR-022 §6) — UX: o operador não precisa
      // arrastar do Market Watch. Reusa um chart já aberto do CS se houver
      // (evita spam de janelas em re-init); senão abre um novo em M1. Só no
      // live (no tester ChartOpen de CS não se aplica).
      long existing = FindChartIdBySymbol(g_csName);
      if(existing >= 0)
      {
         g_csChartId = existing;
      }
      else
      {
         g_csChartId = (long)ChartOpen(g_csName, PERIOD_M1);
         if(g_csChartId == 0)
         {
            g_logger.Warn("ColorReversal", "ChartOpen do CS falhou (segue sem auto-open)",
               StringFormat("\"cs\":\"%s\",\"lastErr\":%d",
                            MksJsonEscape(g_csName), GetLastError()));
            g_csChartId = -1;
         }
         else
         {
            g_logger.Info("ColorReversal", "cs chart aberto",
               StringFormat("\"cs\":\"%s\",\"chartId\":%I64d",
                            MksJsonEscape(g_csName), g_csChartId));
         }
      }
   }
   // ADR-023 §1: nextBarTime inicia em 0 (epoch) — o primeiro brick decide
   // o slot de partida via timeline híbrida (realTime vence). Garante que
   // os bricks fiquem distribuídos no tempo real e que os marcadores de
   // trade (ADR-028) ancorem na barra correta.
   g_nextBarTime = 0;

   //--- 6. Sinks ---------------------------------------------------+
   g_brickSink = new CMksBrickWriterSink();
   g_brickSink.writer      = g_writer;
   g_brickSink.printBricks = InpPrintBricks;
   g_brickSink.digits      = g_digits;

   g_multiSink = new CMksMultiSink();
   g_multiSink.Add(g_brickSink);

   // CSSink só faz sentido fora do tester (CS proibido lá).
   if(!g_isTesting)
   {
      g_csSink = new CMksCustomSymbolSink();
      g_csSink.csName       = g_csName;
      g_csSink.nextBarTime  = g_nextBarTime;
      g_csSink.brickSizePts = InpBrickSize;
      g_csSink.showWicks    = InpShowWicksInCS;
      g_multiSink.Add(g_csSink);
   }

   if(InpAlsoWriteAudit)
   {
      g_auditSink = new CMksAuditLogSink();
      if(g_auditSink.Open(g_auditPath))
      {
         g_auditSink.WriteHeader(g_symbol, g_broker, g_account, g_digits,
                                 InpBrickSize, "classic");
         g_multiSink.Add(g_auditSink);
         g_logger.Info("ColorReversal", "audit sink enabled",
            StringFormat("\"path\":\"%s\"", MksJsonEscape(g_auditPath)));
      }
      else
      {
         g_logger.Warn("ColorReversal", "audit sink open failed (continues without audit)",
                       StringFormat("\"path\":\"%s\"", MksJsonEscape(g_auditPath)));
      }
   }

   //--- 7. PositionBook (filtra por símbolo + magic) ---------------+
   g_book = new CMksMt5PositionBook(g_symbol, InpMagicNumber);

   //--- 8. AccountSnapshot ----------------------------------------+
   g_snapshot = new CMksAccountSnapshot(g_iAccount, g_iClock);
   g_snapshot.Init();

   //--- 9. Risk Manager (3 camadas) -------------------------------+
   // E1.1 + E0.3/M12: o piso de SL mínimo é ancorado em BRICKS, computado
   // dentro do RiskManager (fonte única, via SetSlFloorSource abaixo). O
   // piso efetivo = max(InpMinSlFloorPts, InpMinSlBricks·brickSizePts) —
   // função pura de config, idêntica em live/tester/replay: backtest e
   // live rejeitam o MESMO SL muito-próximo (anti-eixo-2), sem depender do
   // StopsLevel (que StressLab/tester podem modelar diferente do live).
   // Com InpMinSlBricks>=1 o piso é sempre >0 → o gate fica SEMPRE ativo,
   // matando o NO-OP do M12 (StopsLevel=0 desligava o gate na Exness XAU).
   // StopsLevel entra AQUI só como fail-fast de ANEXAÇÃO (não no número de
   // runtime): se o piso configurado ficar abaixo do stops level do
   // broker, recusa anexar pedindo para subir o piso.
   int    stopsLevelPts = g_iSymbol.StopsLevel();
   double brickSizePts  = (g_iSymbol.Point() > 0.0)
                          ? (g_brickSizer.SizePoints() / g_iSymbol.Point()) : 0.0;
   double configFloor   = MathMax(InpMinSlFloorPts, InpMinSlBricks * brickSizePts);

   if(InpMinSlBricks < 1)
   {
      Alert("MKS ColorReversal: InpMinSlBricks deve ser >= 1 (piso de SL fail-closed).");
      g_logger.Error("ColorReversal", "InpMinSlBricks < 1",
         StringFormat("\"minSlBricks\":%d", InpMinSlBricks));
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }
   if(configFloor < (double)stopsLevelPts)
   {
      Alert(StringFormat(
         "MKS ColorReversal: piso de SL configurado (%.0f pts) abaixo do stops level "
         "do broker (%d pts). Suba InpMinSlBricks ou InpMinSlFloorPts e reanexe.",
         configFloor, stopsLevelPts));
      g_logger.Error("ColorReversal", "piso de SL abaixo do stops level do broker",
         StringFormat("\"configFloor\":%.1f,\"stopsLevel\":%d", configFloor, stopsLevelPts));
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpSlPoints > 0.0 && InpSlPoints < configFloor)
   {
      // Este é o caso exato do M12: operador setou InpSlPoints abaixo do
      // piso enforçado (ex.: 30 < 300). Recusa anexar ANTES de qualquer
      // ordem live — em vez de o gate rejeitar cada Send em runtime.
      Alert(StringFormat(
         "MKS ColorReversal: InpSlPoints=%.0f abaixo do piso mínimo enforçado (%.0f pts "
         "= %d brick(s)). Ajuste InpSlPoints para >= %.0f e reanexe.",
         InpSlPoints, configFloor, InpMinSlBricks, configFloor));
      g_logger.Error("ColorReversal", "InpSlPoints abaixo do piso de SL",
         StringFormat("\"slPoints\":%.1f,\"configFloor\":%.1f", InpSlPoints, configFloor));
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }

   CMksRiskTradeParams rtp;
   rtp.requireSl       = InpRequireSl;
   rtp.requireTp       = InpRequireTp;
   rtp.maxLotsPerTrade = InpMaxLotsPerTrade;
   rtp.minSlPoints     = InpMinSlFloorPts; // belt absoluto; piso de brick via SetSlFloorSource

   CMksRiskStrategyParams rsp;
   rsp.maxOpenPositions = InpMaxOpenPositions;
   rsp.maxTotalLots     = InpMaxTotalLots;

   CMksRiskAccountParams rap;
   rap.maxDailyLossPct = InpMaxDailyLossPct;
   rap.maxDrawdownPct  = InpMaxDrawdownPct;
   rap.minEquityAbs    = InpMinEquityAbs;

   // Construtor 3-camadas: (tradeP, stratP, acctP, book, snapshot, sizer=NULL, logger=NULL)
   g_risk = new CMksRiskManager(rtp, rsp, rap, g_book, g_snapshot, NULL, g_logger);
   // E0.3: injeta a fonte do piso de SL em bricks ANTES de Validate (que
   // checa o wiring fail-closed). Piso = max(belt, InpMinSlBricks·brickSize).
   g_risk.SetSlFloorSource(g_brickSizer, g_iSymbol, InpMinSlBricks);
   if(!g_risk.Validate(err))
   {
      g_logger.Error("ColorReversal", "risk manager invalid",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- 10. Lot Sizer ---------------------------------------------+
   if(InpLotMode == CR_LOT_FIXED)
   {
      CMksFixedLotSizer *fix = new CMksFixedLotSizer(g_iSymbol, InpFixedLots);
      if(!fix.Validate(err))
      {
         g_logger.Error("ColorReversal", "lot sizer invalid",
            StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
         delete fix;
         Cleanup();
         return INIT_PARAMETERS_INCORRECT;
      }
      g_lotSizer = fix;
   }
   else
   {
      CMksPercentRiskSizer *prc = new CMksPercentRiskSizer(g_iSymbol, g_iAccount, InpRiskPct);
      if(!prc.Validate(err))
      {
         g_logger.Error("ColorReversal", "percent risk sizer invalid",
            StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
         delete prc;
         Cleanup();
         return INIT_PARAMETERS_INCORRECT;
      }
      g_lotSizer = prc;
   }

   //--- 11. Broker live + gate ------------------------------------+
   g_mt5Broker = new CMksMt5Broker(g_iSymbol, g_iAccount, (int)InpMagicNumber);
   if(!g_mt5Broker.Init(err))
   {
      g_logger.Error("ColorReversal", "mt5Broker.Init failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_FAILED;
   }
   g_gatedBroker = new CMksRiskGatedBroker(g_mt5Broker, g_risk);

   //--- 11.5 Visualização (ADR-028) -------------------------------+
   // Marcadores de trade como chart objects. No live desenha no chart do
   // CS auto-aberto (caixinhas renko); no tester desenha sobre os candles
   // M1 do chart visual. No-op em backtest não-visual (otimização).
   if(InpShowTradeMarkers)
   {
      bool vizEnabled = (!g_isTesting) || (bool)MQLInfoInteger(MQL_VISUAL_MODE);
      long vizChartId = ChartID();
      if(!g_isTesting)
      {
         if(g_csChartId > 0)
            vizChartId = g_csChartId;  // chart do CS auto-aberto acima
         else
            g_logger.Warn("ColorReversal",
               "chart do CS indisponível — marcadores no chart do EA",
               StringFormat("\"cs\":\"%s\"", MksJsonEscape(g_csName)));
      }
      // Painter só desenha MARCADORES de trade. Renko fica a cargo do CS
      // (live) ou do visualizador de backtest (.mksbk → CS). No tester os
      // marcadores aparecem sobre os candles M1 — honesto, sem fingir renko.
      g_painter = new CMksChartPainter(vizChartId, g_digits, vizEnabled, g_logger);

      MksChartPainterStyle vizStyle;  // widths/dash ficam no default do struct
      vizStyle.arrowBuy    = InpVizArrowBuy;
      vizStyle.arrowSell   = InpVizArrowSell;
      vizStyle.arrowBorder = InpVizArrowBorder;
      vizStyle.lineProfit  = InpVizLineProfit;
      vizStyle.lineLoss    = InpVizLineLoss;
      g_painter.SetStyle(vizStyle);
      // Ancora marcadores no slot real do CS (lastBarTime), não em iTime(CS,0).
      // g_csSink é NULL no tester → painter cai no tempo real (chart M1 real).
      g_painter.SetSink(g_csSink);

      g_painter.Clear(); // start limpo — remove marcadores de sessão anterior (ADR-028 §6)
      g_logger.Info("ColorReversal", "visualização de trades habilitada",
         StringFormat("\"chartId\":%I64d,\"enabled\":%s",
                      vizChartId, (vizEnabled ? "true" : "false")));
   }

   //--- 12. Strategy ----------------------------------------------+
   // g_painter é NULL se InpShowTradeMarkers=false → estratégia roda sem
   // visualização, comportamento idêntico (paridade — ADR-028 §7).
   g_strategy = new CMksColorReversalStrategy(g_gatedBroker, g_lotSizer,
                                               g_iSymbol, InpSlPoints,
                                               InpMagicNumber, g_logger, g_book,
                                               g_painter);
   // Strategy é IRenkoSink → vai no multiSink junto com writer/CS/audit.
   g_multiSink.Add(g_strategy);

   //--- 12.5 Reconciliação de posição órfã (M10, auditoria 2026-07-19) +
   // Sessão anterior pode ter deixado posição aberta (recompile, reboot
   // de VPS, mudança de input). O estado da estratégia nasce vazio; sem
   // adoção a órfã nunca é gerenciada e, com maxOpenPositions=1, o book
   // a conta e todo Send novo leva 405 — EA mudo até o SL bater.
   // Invariante 5 do V5-POSTMORTEM: reconstrução de estado é completa
   // ou não acontece. No tester o book está sempre vazio no OnInit —
   // mesmo caminho de código, no-op (sem bifurcação).
   int orphanCount = g_book.OpenCount();
   if(orphanCount > 1)
   {
      // Duas+ posições no escopo symbol+magic: estado que esta
      // estratégia (1 posição por vez) não sabe reconstruir. Fail-fast
      // barulhento — mesmo padrão da guarda hedging-only (ADR-029).
      Alert(StringFormat(
         "ColorReversal: %d posicoes abertas em %s (magic %d) — a estrategia "
         "gerencia no maximo 1. Feche/ajuste manualmente e reanexe o EA.",
         orphanCount, g_symbol, (int)InpMagicNumber));
      g_logger.Error("ColorReversal", "múltiplas posições órfãs — abortando",
         StringFormat("\"count\":%d", orphanCount));
      Cleanup();
      return INIT_FAILED;
   }
   if(orphanCount == 1)
   {
      ulong               orphanId   = 0;
      ENUM_MKS_ORDER_SIDE orphanSide = MKS_ORDER_BUY;
      double              orphanLots = 0.0;
      if(g_book.PositionAt(0, orphanId, orphanSide, orphanLots))
      {
         g_strategy.AdoptPosition(orphanId, orphanSide, orphanLots);
         Alert(StringFormat(
            "ColorReversal: posicao orfa %I64u (%s %.2f lots) adotada — "
            "sera gerenciada normalmente (flip fecha, SL protege).",
            orphanId, (orphanSide == MKS_ORDER_BUY ? "BUY" : "SELL"),
            orphanLots));
      }
      else
      {
         // Book mudou entre OpenCount e PositionAt (SL bateu no meio do
         // OnInit) — segue sem adoção; auto-detach cobre o resto.
         g_logger.Warn("ColorReversal",
            "órfã sumiu entre OpenCount e PositionAt — seguindo sem adoção", "");
      }
   }

   //--- 13. Builder -----------------------------------------------+
   g_builder = new CMksRenkoBuilder(geom, g_brickSizer, g_multiSink,
                                     InpInvalidTickLimit, InpThresholdLimit);

   //--- 14. Anchor inicial via SymbolInfoTick + EventSetTimer -----+
   MqlTick anchor;
   if(SymbolInfoTick(g_symbol, anchor))
   {
      g_tickCursor.ResetAfter(anchor.time_msc);
      g_logger.Info("ColorReversal", "anchor captured",
         StringFormat("\"anchorMsc\":%I64d,\"bid\":%.5f,\"ask\":%.5f",
                      anchor.time_msc, anchor.bid, anchor.ask));
   }

   g_lastCheckpointMs = GetTickCount(); // primeiro checkpoint 60s após init

   //--- 15. Fill histórico (live only) ----------------------------+
   // Popula CS + .mksbk com N dias de bricks ANTES de operar live, em
   // modo warm-up (estratégia rastreia direção mas não opera no passado).
   // No tester o histórico já vem pelos ticks do período de teste.
   if(!g_isTesting && InpHistoricalFillDays > 0)
      RunHistoricalFill(InpHistoricalFillDays);

   g_logger.Info("ColorReversal", "OnInit done — ready for ticks",
      StringFormat("\"cs\":\"%s\",\"csReset\":%s,\"histDays\":%d",
                   MksJsonEscape(g_csName),
                   (InpResetCustomSymbolBars ? "true" : "false"),
                   InpHistoricalFillDays));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Fill histórico — popula CS/.mksbk com N dias de bricks em warm-up. |
//| A estratégia NÃO opera durante o fill (SetWarmup). Lê de            |
//| CopyTicksRange (fonte diferente do feed live — vale só para o       |
//| trecho histórico visual/registro; paridade canônica é do trecho    |
//| live, ADR-024 R4.5.2). Síncrono — pode levar alguns segundos.       |
//+------------------------------------------------------------------+
void RunHistoricalFill(int days)
{
   long toMsc   = (long)TimeCurrent() * 1000;
   long fromMsc = toMsc - (long)days * 24L * 3600L * 1000L;

   MqlTick histTicks[];
   int n = CopyTicksRange(g_symbol, histTicks, COPY_TICKS_ALL, fromMsc, toMsc);
   if(n <= 0)
   {
      g_logger.Warn("ColorReversal", "historical fill: CopyTicksRange vazio/falhou",
         StringFormat("\"ret\":%d,\"lastErr\":%d", n, GetLastError()));
      return;
   }

   g_builder.SetEmitForming(false);  // não dispara OnBrickForming por tick no fill
   g_strategy.SetWarmup(true);       // rastreia direção mas não opera no passado
   long bricksBefore = (g_writer != NULL) ? g_writer.BrickCount() : 0;

   for(int i = 0; i < n; i++)
   {
      MksTick t = ToMksTick(histTicks[i]);
      IngestOne(t);
      if(g_streamHalted) break;
   }

   long bricksAfter = (g_writer != NULL) ? g_writer.BrickCount() : 0;
   g_strategy.SetWarmup(false);      // live: estratégia volta a operar
   g_builder.SetEmitForming(true);

   g_logger.Info("ColorReversal", "historical fill done",
      StringFormat("\"days\":%d,\"ticks\":%d,\"bricks\":%I64d,\"lastDir\":\"%s\"",
                   days, n, bricksAfter - bricksBefore,
                   (g_strategy.LastBrickDir() == MKS_BRICK_BULL ? "BULL" : "BEAR")));
}

//+------------------------------------------------------------------+
//| Converte MqlTick para MksTick (com seq monotônico interno)        |
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
//| Alimenta builder com um tick. Builder delega para multiSink, que   |
//| inclui a strategy — decisões de trade saem daí.                    |
//+------------------------------------------------------------------+
void IngestOne(const MksTick &tick)
{
   if(g_streamHalted) return;

   MksError err;
   if(g_builder.IngestTick(tick, err)) return;

   if(err.code == MKS_ERR_RENKO_INVALID_TICK)
   {
      if(g_auditSink != NULL)
         g_auditSink.RecordInvalidTick(tick.seq, tick.bid, tick.ask);
   }
   else if(err.code == MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED)
   {
      if(g_auditSink != NULL)
         g_auditSink.RecordKExceeded(tick.seq, (tick.bid + tick.ask) / 2.0,
                                      InpThresholdLimit + 1);
      g_logger.Warn("ColorReversal", "threshold K exceeded",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
   }
   else if(err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP)
   {
      if(g_auditSink != NULL)
         g_auditSink.RecordKExceeded(tick.seq, (tick.bid + tick.ask) / 2.0, -105);
      g_logger.Warn("ColorReversal", "gap structural — builder reanchored",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
   }
   else if(err.code == MKS_ERR_RENKO_TICK_STREAM_CORRUPT)
   {
      g_streamHalted = true;
      if(g_auditSink != NULL)
         g_auditSink.RecordStreamHalted(tick.seq, InpInvalidTickLimit);
      g_logger.Error("ColorReversal", "tick stream corrupt — halted",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));

      // M19 (auditoria 2026-07-19): halt de stream com posição aberta.
      // EA cego não gerencia posição — a única saída seria o SL
      // distante, sem ninguém olhando. Flatten + Alert; se o Close
      // falhar, Alert exige intervenção manual (posição segue aberta,
      // vínculo mantido pelo FlattenForSafety).
      if(g_strategy != NULL && g_strategy.HasOpenPosition())
      {
         ulong haltPid = g_strategy.CurrentPositionId();
         if(g_strategy.FlattenForSafety("tick stream corrupt (104)"))
            Alert(StringFormat(
               "ColorReversal: stream de ticks corrompido — EA PARADO. "
               "Posicao %I64u fechada por seguranca.", haltPid));
         else
            Alert(StringFormat(
               "ColorReversal: stream corrompido — EA PARADO e o Close da "
               "posicao %I64u FALHOU. Feche manualmente AGORA.", haltPid));
      }
      else
         Alert("ColorReversal: stream de ticks corrompido — EA parado "
               "(sem posicao aberta).");
   }
}

//+------------------------------------------------------------------+
//| OnTick — CopyTicks(COPY_TICKS_ALL) para janela completa           |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_streamHalted) return;

   MqlTick ticks[];
   int n = CopyTicks(g_symbol, ticks, COPY_TICKS_ALL, g_tickCursor.FromMsc(), 0);
   if(n <= 0) return;

   // Dedup por contagem na fronteira (MksTickBatchCursor, H5): ticks
   // legítimos do mesmo ms são preservados; só repetições são puladas.
   g_tickCursor.BeginBatch();
   for(int i = 0; i < n; i++)
   {
      const MqlTick mt = ticks[i];
      if(!g_tickCursor.Admit(mt.time_msc)) continue; // fronteira já vista
      if(mt.bid <= 0.0 && mt.ask <= 0.0) continue;   // lixo (contado como visto)
      MksTick t = ToMksTick(mt);
      IngestOne(t);
   }

   // Checkpoint de observabilidade a cada 60s (só fora do tester — no
   // tester a sessão fecha rápido e o OnDeinit faz flush final). Patcheia
   // header do .mksbk + flush do audit TSV para inspeção mid-sessão.
   if(!g_isTesting)
   {
      uint nowMs = GetTickCount();
      if(nowMs - g_lastCheckpointMs >= kCheckpointEveryMs)
      {
         g_lastCheckpointMs = nowMs;
         if(g_writer != NULL)
         {
            MksError ckErr;
            if(!g_writer.Checkpoint(ckErr) && g_logger != NULL)
               g_logger.Warn("ColorReversal", "writer Checkpoint failed",
                  StringFormat("\"err\":\"%s\"", MksJsonEscape(ckErr.ToString())));
         }
         if(g_auditSink != NULL) g_auditSink.Flush();
      }
   }
}

//+------------------------------------------------------------------+
//| Roteamento de OnTradeTransaction para o broker (fallback caso o   |
//| caminho síncrono OrderSend não preencha tudo na ida).              |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(g_mt5Broker != NULL)
      g_mt5Broker.OnTradeTransactionEvent(trans, request, result);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_logger != NULL && g_strategy != NULL)
   {
      CMksColorReversalMetrics m = g_strategy.Metrics();
      g_logger.Info("ColorReversal", "session summary",
         StringFormat("\"deinitReason\":%d,\"ticks\":%I64u,"
                      "\"bricks\":%I64d,\"flips\":%I64d,"
                      "\"sendsAttempted\":%I64d,\"sendsFilled\":%I64d,"
                      "\"sendsRejected\":%I64d,"
                      "\"closesAttempted\":%I64d,\"closesFilled\":%I64d,"
                      "\"autoDetected\":%I64d,\"streamHalted\":%s,"
                      "\"hasOpenPosition\":%s,\"currentPositionId\":%I64u,"
                      "\"mksbkPath\":\"%s\",\"logPath\":\"%s\",\"auditPath\":\"%s\"",
                      reason, g_seq,
                      m.bricksSeen, m.flipsDetected,
                      m.sendsAttempted, m.sendsFilled, m.sendsRejected,
                      m.closesAttempted, m.closesFilled,
                      m.autoDetected,
                      (g_streamHalted ? "true" : "false"),
                      (g_strategy.HasOpenPosition() ? "true" : "false"),
                      g_strategy.CurrentPositionId(),
                      MksJsonEscape(g_filePath),
                      MksJsonEscape(g_logPath),
                      MksJsonEscape(g_auditPath)));
   }

   if(g_writer != NULL)
   {
      MksError err;
      g_writer.Close(err);
   }
   if(g_auditSink != NULL) g_auditSink.Close();

   Cleanup();
}
//+------------------------------------------------------------------+
