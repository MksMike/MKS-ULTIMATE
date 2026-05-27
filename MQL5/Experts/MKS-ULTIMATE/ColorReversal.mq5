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
#include <MKS-ULTIMATE/Core/Output/CMksCustomSymbolSink.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksAuditLogSink.mqh>
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
input double InpSlPoints            = 30.0;  // SL fixo em pontos do símbolo
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
long                  g_lastSeenMsc    = 0;
bool                  g_isTesting      = false;  // MQL_TESTER detection (ADR-022 §UX precedent)

ISymbol              *g_iSymbol  = NULL;
IAccount             *g_iAccount = NULL;
IClock               *g_iClock   = NULL;

CMksFixedBrickSizer  *g_brickSizer  = NULL;
CMksBrickFileWriter  *g_writer      = NULL;
CMksBrickWriterSink  *g_brickSink   = NULL;
CMksCustomSymbolSink *g_csSink      = NULL;
CMksAuditLogSink     *g_auditSink   = NULL;
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
//| Cleanup — libera todos os ponteiros heap-alocados                 |
//+------------------------------------------------------------------+
void Cleanup()
{
   if(g_strategy    != NULL) { delete g_strategy;    g_strategy    = NULL; }
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
   }
   g_nextBarTime = AlignDownToM1(TimeCurrent());

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
   CMksRiskTradeParams rtp;
   rtp.requireSl       = InpRequireSl;
   rtp.requireTp       = InpRequireTp;
   rtp.maxLotsPerTrade = InpMaxLotsPerTrade;

   CMksRiskStrategyParams rsp;
   rsp.maxOpenPositions = InpMaxOpenPositions;
   rsp.maxTotalLots     = InpMaxTotalLots;

   CMksRiskAccountParams rap;
   rap.maxDailyLossPct = InpMaxDailyLossPct;
   rap.maxDrawdownPct  = InpMaxDrawdownPct;
   rap.minEquityAbs    = InpMinEquityAbs;

   // Construtor 3-camadas: (tradeP, stratP, acctP, book, snapshot, sizer=NULL, logger=NULL)
   g_risk = new CMksRiskManager(rtp, rsp, rap, g_book, g_snapshot, NULL, g_logger);
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

   //--- 12. Strategy ----------------------------------------------+
   g_strategy = new CMksColorReversalStrategy(g_gatedBroker, g_lotSizer,
                                               g_iSymbol, InpSlPoints,
                                               InpMagicNumber, g_logger, g_book);
   // Strategy é IRenkoSink → vai no multiSink junto com writer/CS/audit.
   g_multiSink.Add(g_strategy);

   //--- 13. Builder -----------------------------------------------+
   g_builder = new CMksRenkoBuilder(geom, g_brickSizer, g_multiSink,
                                     InpInvalidTickLimit, InpThresholdLimit);

   //--- 14. Anchor inicial via SymbolInfoTick + EventSetTimer -----+
   MqlTick anchor;
   if(SymbolInfoTick(g_symbol, anchor))
   {
      g_lastSeenMsc = anchor.time_msc;
      g_logger.Info("ColorReversal", "anchor captured",
         StringFormat("\"anchorMsc\":%I64d,\"bid\":%.5f,\"ask\":%.5f",
                      anchor.time_msc, anchor.bid, anchor.ask));
   }

   g_logger.Info("ColorReversal", "OnInit done — ready for ticks",
      StringFormat("\"cs\":\"%s\",\"csReset\":%s",
                   MksJsonEscape(g_csName),
                   (InpResetCustomSymbolBars ? "true" : "false")));

   return INIT_SUCCEEDED;
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
   }
}

//+------------------------------------------------------------------+
//| OnTick — CopyTicks(COPY_TICKS_ALL) para janela completa           |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_streamHalted) return;

   MqlTick ticks[];
   int n = CopyTicks(g_symbol, ticks, COPY_TICKS_ALL, g_lastSeenMsc, 0);
   if(n <= 0) return;

   for(int i = 0; i < n; i++)
   {
      const MqlTick mt = ticks[i];
      if(mt.time_msc <= g_lastSeenMsc) continue;  // dedup
      if(mt.bid <= 0.0 && mt.ask <= 0.0) continue; // lixo
      MksTick t = ToMksTick(mt);
      IngestOne(t);
      g_lastSeenMsc = mt.time_msc;
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
