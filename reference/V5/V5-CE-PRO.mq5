//+------------------------------------------------------------------+
//| MKS-EA-CE-PRO.mq5                                                |
//| MKS Framework - V5.0 [Expert Advisor]                            |
//| Descricao: 4 Estrategias + Regime Detection + Pyramid + Risco    |
//| Instalacao: MQL5/Experts/MKS-V5.0/                               |
//| Build: V5.0 (2026-04-13)                                         |
//+------------------------------------------------------------------+
//
// ARQUITETURA:
//   CE1 Solo  (Magic+0): micro scalp, 100% independente
//   CE2 Solo  (Magic+1): scalp, regime TREND
//   CE1+CE2   (Magic+2): scalp maior, regime TREND, hierarquia
//   BOX       (Magic+3): lateral, regime LATERAL
//
// REGIME DETECTOR (switch ON/OFF):
//   CE2 inclinada → TREND  (CE2 solo + combo ativos)
//   CE2 flat      → LATERAL (BOX ativo)
//   CE1 solo: SEMPRE ativo (independente)
//
// PYRAMID: pullback-then-resume (CE2 e combo)
// RISCO: max exposicao, max drawdown diario, anti-hedge
// Usa SOMENTE close (sem wicks)
//+------------------------------------------------------------------+

#property copyright   "MKS Framework"
#property version     "1.00"
#property description "EA CE-PRO V1.0 — Fase 1: Fundacao"

#include <MKS-V5.0/Core/MKS-Renko-Types.mqh>
#include <MKS-V5.0/Core/Logger.mqh>
#include <Trade/Trade.mqh>

//=====================================================================
// SECAO 1: INPUTS
//=====================================================================

input group "═══════════ CONFIGURACAO BASICA ═══════════"
input string InpCustomSymbol  = "";        // Custom Symbol (vazio = auto)
input int    InpMagic         = 70001;     // Magic Base (CE1=+0, CE2=+1, Combo=+2, BOX=+3)
input bool   InpDebugMode     = false;     // Debug detalhado (logs por modulo)

input group "═══════════ STRESS LABORATORY ═══════════"
input bool   InpUseStressLab  = false;     // ── ATIVAR StressLab
enum ENUM_STRESS_PRESET
{
   PRESET_CUSTOM       = 0,               // CUSTOM (usar valores abaixo)
   PRESET_ECN_BEST     = 1,               // ECN Best   (spread 15,  lat 20-50ms)
   PRESET_ECN_AVG      = 2,               // ECN Avg    (spread 30,  lat 50-150ms)
   PRESET_RETAIL_GOOD  = 3,               // Retail Bom (spread 50,  lat 100-200ms)
   PRESET_RETAIL_AVG   = 4,               // Retail Med (spread 100, lat 200-400ms)
   PRESET_WORST_CASE   = 5,               // Worst Case (spread 500, lat 300-700ms)
   PRESET_NIGHTMARE    = 6                 // Nightmare  (spread 1000, lat 500-1500ms)
};
input ENUM_STRESS_PRESET InpPreset = PRESET_ECN_AVG;
input int    InpSpreadPoints    = 30;      //    Spread (pontos)
input int    InpSlippageMin     = 0;       //    Slippage min (pontos)
input int    InpSlippageMax     = 10;      //    Slippage max (pontos)
input double InpCommissionEntry = 3.50;    //    Comissao entrada ($)
input double InpCommissionExit  = 3.50;    //    Comissao saida ($)
input int    InpLatencyMin      = 50;      //    Latencia min (ms)
input int    InpLatencyMax      = 150;     //    Latencia max (ms)
input int    InpRejectionRate   = 1;       //    Taxa rejeicao (%)
input int    InpRequoteRate     = 0;       //    Taxa requote (%)

input group "═══════════ FILTRO: SESSOES ═══════════"
input bool   InpSesTokyo      = true;      // Tokyo   (00:00-09:00 UTC)
input bool   InpSesLondon     = true;      // London  (07:00-16:00 UTC)
input bool   InpSesNewYork    = true;      // New York(12:00-21:00 UTC)
input bool   InpSesSydney     = true;      // Sydney  (21:00-06:00 UTC)

input group "═══════════ REGIME DETECTOR ═══════════"
input bool   InpUseRegime     = false;     // ── ATIVAR switch trend/lateral
                                           //    ON: CE2 incl=trend, CE2 flat=lateral
                                           //    OFF: todos operam independentes

input group "═══════════ CE1 — MICRO SCALP ═══════════"
input bool   InpUseCE1        = true;      // ── ATIVAR CE1 solo (100% independente)
input double InpCE1Brick      = 3.0;       //    BrickSize ($) para calculo CE
input int    InpCE1Period     = 2;         //    Janela CE (bricks)
input double InpCE1Mult       = 1.4;       //    Multiplicador CE
input bool   InpCE1Ratchet    = true;      //    Ratchet ativo
input int    InpCE1FlatBricks = 3;         //    Bricks sem movimento = flat
input double InpCE1Lot        = 0.01;      //    Lote CE1
input int    InpCE1EntryDelay = 0;         //    Entrada: 0=mesmo brick, N=N bricks apos CE1 inclinada
//--- Saidas CE1 ---
input bool   InpCE1ExitFlip   = true;      //    Saida: CE1 flip fecha
input bool   InpCE1ExitBricks = true;      //    Saida: N bricks contrarios
input int    InpCE1ExitN      = 2;         //    N bricks para saida
//--- Re-entrada CE1 ---
input bool   InpCE1ReEntry    = true;      //    Re-entrada mesma tendencia
input int    InpCE1ReMax      = 3;         //    Max re-entradas por tendencia
//--- Pyramid CE1 (confirmacao de momentum) ---
input int    InpCE1PyrMax     = 0;         //    Pyramid: 0=OFF, 1=+1 pos, 2=+2 pos
input int    InpCE1PyrBricks  = 2;         //    Bricks consecutivos para add (lote fixo 0.01)

input group "═══════════ CE2 — SCALP ═══════════"
input bool   InpUseCE2        = true;      // ── ATIVAR CE2 solo
input double InpCE2Brick      = 3.0;       //    BrickSize ($) para calculo CE
input int    InpCE2Period     = 9;         //    Janela CE (bricks)
input double InpCE2Mult       = 3.0;       //    Multiplicador CE
input bool   InpCE2Ratchet    = true;      //    Ratchet ativo
input int    InpCE2FlatBricks = 5;         //    Bricks sem movimento = flat
input double InpCE2Lot        = 0.01;      //    Lote CE2
input int    InpCE2EntryDelay = 0;         //    Entrada: 0=mesmo brick, N=espera N bricks apos flip
//--- Saidas CE2 ---
input bool   InpCE2ExitFlip   = true;      //    Saida: CE2 flip fecha
input bool   InpCE2ExitBricks = true;      //    Saida: N bricks contrarios
input int    InpCE2ExitN      = 2;         //    N bricks para saida
input bool   InpCE2UseTrail   = true;      //    Saida: Trailing 3F
input int    InpCE2TrailInit  = 3;         //    Trailing F1: distancia inicial (bricks)
input int    InpCE2TrailTight = 1;         //    Trailing F3: distancia tight (bricks)
//--- Re-entrada CE2 ---
input bool   InpCE2ReEntry    = true;      //    Re-entrada mesma tendencia
input int    InpCE2ReMax      = 3;         //    Max re-entradas por tendencia

input group "═══════════ CE1+CE2 COMBO — SCALP MAIOR ═══════════"
input bool   InpUseCombo      = false;     // ── ATIVAR combo
input double InpComboLot      = 0.01;      //    Lote combo
input int    InpComboEntryDelay= 0;        //    Entrada: 0=mesmo brick, N=espera N bricks apos ambas confirmarem
input bool   InpComboHierarchy= false;     //    Hierarquia: CE1/CE2 solo dormem quando combo ativa
//--- Saidas combo ---
input bool   InpComboUseTrail = true;      //    Saida: Trailing 3F
input int    InpComboTrailInit= 3;         //    Trailing F1: distancia inicial (bricks)
input int    InpComboTrailTight=1;         //    Trailing F3: distancia tight (bricks)
input bool   InpComboExitFlip = true;      //    Saida: CE1 flip fecha
input bool   InpComboExitTimeout=false;    //    Saida: Timeout N bricks sem progresso
input int    InpComboTimeoutN = 10;        //    N bricks sem novo high/low
//--- Re-entrada combo ---
input bool   InpComboReEntry  = true;      //    Re-entrada mesma tendencia
input int    InpComboReMax    = 2;         //    Max re-entradas por tendencia

input group "═══════════ BOX — ESTRATEGIA LATERAL CE2 ═══════════"
input bool   InpUseBox        = false;     // ── ATIVAR BOX
input int    InpBoxEntry      = 1;         //    Entrada: 0=mesmo brick, 1=proximo a favor
input int    InpBoxExitBricks = 1;         //    Saida padrao: N bricks contrarios
input double InpBoxLot        = 0.01;      //    Lote BOX
//--- Gatilhos (distancia em halfSteps) ---
input bool   InpBoxTouchNear  = true;      //    ── PROXIMO (acima da linha)
input int    InpBoxNearSteps  = 1;         //       HalfSteps acima (1=meio brick)
input bool   InpBoxTouchExact = true;      //    ── TOCANDO (na linha)
input bool   InpBoxTouchCross = true;      //    ── SOBRE (cruzou a linha)
input int    InpBoxCrossSteps = 0;         //       HalfSteps abaixo (0=na linha)
//--- Filtros BOX ---
input bool   InpBoxUseMinSize = false;     //    ── FILTRO: tamanho minimo
input int    InpBoxMinSize    = 4;         //       HalfSteps entre CE2 bull/bear
input bool   InpBoxUseMinDist = false;     //    ── FILTRO: distancia minima
input int    InpBoxMinAway    = 4;         //       HalfSteps away antes do pullback
input bool   InpBoxUseDynExit = false;     //    ── FILTRO: saida dinamica (CE2 oposta)
input bool   InpBoxUseSpread  = false;     //    ── FILTRO: spread maximo
input double InpBoxMaxSpreadPct=15.0;      //       Max spread (% do brick)

input group "═══════════ PYRAMID ═══════════"
input bool   InpUsePyramid    = false;     // ── ATIVAR Pyramid (pullback-then-resume)
input int    InpPyrPullback   = 2;         //    Bricks de pullback para detectar
input int    InpPyrType       = 2;         //    Tipo: 1=add no pullback, 2=add proximo a favor
input int    InpPyrMax        = 4;         //    Max posicoes (incluindo inicial)
input double InpPyrDecay      = 0.5;       //    Fator reducao lote (0.5=metade)
input bool   InpPyrCE2        = true;      //    Aplica a CE2 solo
input bool   InpPyrCombo      = true;      //    Aplica a CE1+CE2 combo

input group "═══════════ GESTAO DE RISCO ═══════════"
input bool   InpUseMaxExposure = false;    // ── Max exposicao global (lotes)
input double InpMaxExposure    = 1.0;      //    Max lotes total (CE1+CE2+combo+BOX)
input bool   InpUseMaxDD       = false;    // ── Max drawdown diario
input double InpMaxDDPct       = 2.0;      //    Max perda diaria (% equity)
input bool   InpUseAntiHedge   = false;    // ── Anti-hedge (ignora CE1)
                                           //    BOX SELL bloqueado se CE2/combo tem BUY

input group "═══════════ VISUAL ═══════════"
input bool   InpDrawCE        = true;      // Desenhar linhas CE
input color  InpCE1ColorBull  = clrDodgerBlue;    // CE1 bull
input color  InpCE1ColorBear  = clrCrimson;       // CE1 bear
input int    InpCE1LineWidth  = 2;                 // CE1 largura
input ENUM_LINE_STYLE InpCE1LineStyle = STYLE_SOLID; // CE1 estilo
input color  InpCE2ColorBull  = clrLime;           // CE2 bull
input color  InpCE2ColorBear  = clrOrangeRed;      // CE2 bear
input int    InpCE2LineWidth  = 1;                 // CE2 largura
input ENUM_LINE_STYLE InpCE2LineStyle = STYLE_DOT;  // CE2 estilo

//=====================================================================
// SECAO 2: CONSTANTES
//=====================================================================

#define CE_HIST_MAX    20                  // Historico CE para flat detection
#define MAGIC_CE1      0                   // Offset magic CE1 solo
#define MAGIC_CE2      1                   // Offset magic CE2 solo
#define MAGIC_COMBO    2                   // Offset magic combo
#define MAGIC_BOX      3                   // Offset magic BOX

//=====================================================================
// SECAO 3: GLOBAIS
//=====================================================================

//--- Simbolo e propriedades
string g_csName="", g_baseSymbol="", g_activeSymbol="";
double g_brickSize=0.0;
bool   g_isTester=false;
datetime g_lastBarTime=0;

//--- Propriedades do simbolo
double g_pointValue=0, g_tickSize=0, g_tickValue=0, g_pointSize=0;
double g_contractSize=0; int g_digits=0;

//--- Trade objects (1 por estrategia)
CTrade g_tradeCE1;                                     // CE1 solo (magic+0)
CTrade g_tradeCE2;                                     // CE2 solo (magic+1)
CTrade g_tradeCombo;                                   // Combo (magic+2)
CTrade g_tradeBox;                                     // BOX (magic+3)

//--- CE1 estado
double g_ce1Bull=0, g_ce1Bear=0;
double g_ce1Dir=0, g_ce1PrevDir=0;
bool   g_ce1Flat=true, g_ce1Ready=false;
double g_ce1FlatDiff=0;
double g_ce1BullHist[], g_ce1BearHist[];
int    g_ce1HistCount=0;

//--- CE2 estado
double g_ce2Bull=0, g_ce2Bear=0;
double g_ce2Dir=0, g_ce2PrevDir=0;
bool   g_ce2Flat=true, g_ce2Ready=false;
double g_ce2FlatDiff=0;
double g_ce2BullHist[], g_ce2BearHist[];
int    g_ce2HistCount=0;

//--- Regime
bool   g_regimeTrend=true;                             // true=trend, false=lateral
bool   g_regimeChanged=false;                          // Flag transicao de regime

//--- CE1 Solo estado
int    g_ce1OppCount=0;                                // Bricks contra CE1
int    g_ce1ReCount=0;                                 // Re-entradas na tendencia atual
int    g_ce1Trades=0, g_ce1Buys=0, g_ce1Sells=0;
int    g_ce1PyrAdds=0;                                 // Pyramid adds CE1
int    g_ce1FlipWait=0;                                // Countdown entry delay (bricks)
int    g_ce1ConfirmCount=0;                             // Bricks confirmando CE1 inclinada
double g_ce1ConfirmDir=0;                               // Direcao quando confirmacao comecou
double g_ce1FlipDir=0;                                 // Direcao no momento do flip

//--- CE2 Solo estado
int    g_ce2OppCount=0;                                // Bricks contra CE2
int    g_ce2ReCount=0;                                 // Re-entradas na tendencia atual
int    g_ce2Trades=0, g_ce2Buys=0, g_ce2Sells=0;
double g_ce2TsAvg=0; int g_ce2TsDir=0, g_ce2TsPhase=0; double g_ce2TsBest=0;
int    g_ce2FlipWait=0;                                // Countdown entry delay
double g_ce2FlipDir=0;                                 // Direcao no momento do flip

//--- Combo estado
int    g_comboOppCount=0;
int    g_comboReCount=0;
int    g_comboTrades=0, g_comboBuys=0, g_comboSells=0;
double g_comboTsAvg=0; int g_comboTsDir=0, g_comboTsPhase=0; double g_comboTsBest=0;
int    g_comboStagnant=0;                              // Bricks sem progresso (timeout)
double g_comboBestPrice=0;                             // Melhor preco desde entrada
int    g_comboFlipWait=0;                              // Countdown entry delay
double g_comboFlipDir=0;                               // Direcao no momento da confirmacao

//--- BOX estado
bool   g_boxTrigger=false;
int    g_boxSide=0;
int    g_boxOppCount=0;
int    g_boxTrades=0, g_boxBuys=0, g_boxSells=0;
int    g_boxTriggers=0;
double g_boxEntryPrice=0;
int    g_boxTouchType=0;
int    g_boxTrigsNear=0, g_boxTrigsExact=0, g_boxTrigsCross=0;
int    g_boxTouchCount=0;
double g_boxLastTouchLine=0;
double g_boxMaxAway=0;
int    g_boxSizeFiltered=0, g_boxDistFiltered=0, g_boxSpreadFiltered=0;
int    g_boxDynExits=0;

//--- Pyramid estado
int    g_pyrAdds=0;
int    g_pyrCE2PullCount=0;                            // Bricks contra CE2 (pullback)
bool   g_pyrCE2Ready=false;                            // Pullback detectado, espera resume
int    g_pyrComboPullCount=0;                          // Bricks contra combo (pullback)
bool   g_pyrComboReady=false;                          // Pullback detectado, espera resume

//--- Visual
double g_viz1PrevBull=0, g_viz1PrevBear=0;
double g_viz2PrevBull=0, g_viz2PrevBear=0;
datetime g_vizPrevTime=0; int g_vizCount=0;

//--- StressLab
int    g_effSpread=0, g_effLatencyMin=0, g_effLatencyMax=0, g_effRejection=0;
double g_costSpread=0, g_costSlippage=0, g_costCommission=0, g_costSwap=0;
int    g_statTrades=0, g_statRejections=0, g_statRequotes=0;
ulong  g_lastSignalTick=0;
long   g_latencySum=0, g_latencyMin=LONG_MAX, g_latencyMax=0; int g_latencySamples=0;
double g_spreadSum=0, g_spreadMin=DBL_MAX, g_spreadMax=0; int g_spreadSamples=0;

//--- Risco
double g_dailyStartEquity=0;                           // Equity no inicio do dia
datetime g_dailyDate=0;                                // Data atual para reset diario
bool   g_dailyLocked=false;                            // Dia bloqueado por drawdown

//--- Stats gerais
int    g_bricksTotal=0, g_bricksBull=0, g_bricksBear=0;
int    g_flatBlocked=0, g_regimeBlocked=0, g_sessionBlocked=0;
int    g_hedgeBlocked=0, g_exposureBlocked=0;
datetime g_startTime=0;

//=====================================================================
// SECAO 4: ONINIT / ONDEINIT
//=====================================================================

int OnInit()
{
   CLogger::Init(LOG_LEVEL_INFO, true, "MKS_EA_CE_PRO.log");
   g_startTime = TimeCurrent();
   Print("╔══════════════════════════════════════════╗");
   Print("║     MKS EA CE-PRO V1.0 — Fase 1         ║");
   Print("║   4 Estrategias + Regime + Risco         ║");
   Print("╚══════════════════════════════════════════╝");

   //--- Parse do Custom Symbol
   g_csName = (InpCustomSymbol == "") ? Symbol() : InpCustomSymbol;
   ENUM_MKS_SIZE_MODE sm; ENUM_MKS_PRESET pr;
   if(!MKS_ParseSymbolName(g_csName, g_baseSymbol, g_brickSize, sm, pr))
   { Print("ERRO: Parse falhou: ", g_csName); return INIT_FAILED; }

   g_isTester = (bool)MQLInfoInteger(MQL_TESTER);
   g_activeSymbol = g_isTester ? g_csName : g_baseSymbol;

   //--- Propriedades do simbolo
   g_tickSize     = SymbolInfoDouble(g_csName, SYMBOL_TRADE_TICK_SIZE);
   g_tickValue    = SymbolInfoDouble(g_csName, SYMBOL_TRADE_TICK_VALUE);
   g_pointSize    = SymbolInfoDouble(g_csName, SYMBOL_POINT);
   g_contractSize = SymbolInfoDouble(g_csName, SYMBOL_TRADE_CONTRACT_SIZE);
   g_digits       = (int)SymbolInfoInteger(g_csName, SYMBOL_DIGITS);
   g_pointValue   = (g_pointSize>0 && g_tickSize>0) ? (g_tickValue*g_pointSize/g_tickSize) : 0;
   if(g_tickSize==0) { Print("ERRO: TickSize=0"); return INIT_FAILED; }

   //--- Configura 4 CTrade objects (1 por estrategia)
   InitTrade(g_tradeCE1,   InpMagic + MAGIC_CE1);
   InitTrade(g_tradeCE2,   InpMagic + MAGIC_CE2);
   InitTrade(g_tradeCombo, InpMagic + MAGIC_COMBO);
   InitTrade(g_tradeBox,   InpMagic + MAGIC_BOX);

   //--- Arrays CE historico
   ArrayResize(g_ce1BullHist, CE_HIST_MAX); ArrayResize(g_ce1BearHist, CE_HIST_MAX);
   ArrayInitialize(g_ce1BullHist, 0);       ArrayInitialize(g_ce1BearHist, 0);
   ArrayResize(g_ce2BullHist, CE_HIST_MAX); ArrayResize(g_ce2BearHist, CE_HIST_MAX);
   ArrayInitialize(g_ce2BullHist, 0);       ArrayInitialize(g_ce2BearHist, 0);

   //--- Validacoes
   if(InpUseBox && !InpUseCE2)
   { Print("ERRO: BOX requer CE2 ativo"); return INIT_PARAMETERS_INCORRECT; }
   if(InpUseCombo && (!InpUseCE1 || !InpUseCE2))
   { Print("ERRO: Combo requer CE1 e CE2 ativos"); return INIT_PARAMETERS_INCORRECT; }

   //--- StressLab
   if(InpUseStressLab) ApplyStressPreset();

   //--- Risco: equity inicial do dia
   g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dailyDate = TimeCurrent() - (TimeCurrent() % 86400);

   PrintConfig();
   EventSetMillisecondTimer(250);
   CLogger::Info("PRO", "INIT OK — pronto para operar");
   return INIT_SUCCEEDED;
}

void InitTrade(CTrade &trade, int magic)
{
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(50);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   trade.SetTypeFillingBySymbol(g_activeSymbol);
}

void OnDeinit(const int reason) { EventKillTimer(); PrintFinalReport(); }

//=====================================================================
// SECAO 5: FILTRO SESSAO
//=====================================================================

bool CheckSession()
{
   if(!InpSesTokyo && !InpSesLondon && !InpSesNewYork && !InpSesSydney) return true;
   MqlDateTime dt; TimeGMT(dt); int h = dt.hour;
   if(InpSesTokyo   && h >= 0  && h < 9)   return true;
   if(InpSesLondon  && h >= 7  && h < 16)  return true;
   if(InpSesNewYork && h >= 12 && h < 21)  return true;
   if(InpSesSydney  && (h >= 21 || h < 6)) return true;
   return false;
}

//=====================================================================
// SECAO 6: STRESSLAB
//=====================================================================

void ApplyStressPreset()
{
   switch(InpPreset)
   {
      case PRESET_ECN_BEST:    g_effSpread=15;   g_effLatencyMin=20;  g_effLatencyMax=50;   g_effRejection=0;  break;
      case PRESET_ECN_AVG:     g_effSpread=30;   g_effLatencyMin=50;  g_effLatencyMax=150;  g_effRejection=1;  break;
      case PRESET_RETAIL_GOOD: g_effSpread=50;   g_effLatencyMin=100; g_effLatencyMax=200;  g_effRejection=2;  break;
      case PRESET_RETAIL_AVG:  g_effSpread=100;  g_effLatencyMin=200; g_effLatencyMax=400;  g_effRejection=5;  break;
      case PRESET_WORST_CASE:  g_effSpread=500;  g_effLatencyMin=300; g_effLatencyMax=700;  g_effRejection=10; break;
      case PRESET_NIGHTMARE:   g_effSpread=1000; g_effLatencyMin=500; g_effLatencyMax=1500; g_effRejection=20; break;
      default:
         g_effSpread=InpSpreadPoints;   g_effLatencyMin=InpLatencyMin;
         g_effLatencyMax=InpLatencyMax; g_effRejection=InpRejectionRate; break;
   }
}

bool SimulateExecution(string tag, double lot, double &totalCost)
{
   totalCost=0;
   if(g_effRejection>0 && (MathRand()%100)<g_effRejection)
   { g_statRejections++; CLogger::Warn("STRESS",StringFormat("[REJ] %s",tag)); return false; }
   if(InpRequoteRate>0 && (MathRand()%100)<InpRequoteRate) g_statRequotes++;
   double sCost=g_effSpread*g_pointValue*lot; g_costSpread+=sCost; totalCost+=sCost;
   int slip=InpSlippageMin+(InpSlippageMax>InpSlippageMin?MathRand()%(InpSlippageMax-InpSlippageMin+1):0);
   double slCost=slip*g_pointValue*lot; g_costSlippage+=slCost; totalCost+=slCost;
   g_costCommission+=InpCommissionEntry; totalCost+=InpCommissionEntry;
   g_statTrades++;
   if(InpDebugMode) CLogger::Debug("STRESS",StringFormat("[COST] %s $%.2f",tag,totalCost));
   return true;
}

void CaptureSpread()
{
   double a=SymbolInfoDouble(g_baseSymbol,SYMBOL_ASK);
   double b=SymbolInfoDouble(g_baseSymbol,SYMBOL_BID);
   if(a<=0||b<=0||g_pointSize<=0) return;
   double pts=(a-b)/g_pointSize; g_spreadSum+=pts; g_spreadSamples++;
   if(pts<g_spreadMin) g_spreadMin=pts;
   if(pts>g_spreadMax) g_spreadMax=pts;
}

//=====================================================================
// SECAO 7: GESTAO DE RISCO
//=====================================================================

bool CheckDailyDrawdown()
{
   if(!InpUseMaxDD) return true;
   datetime today = TimeCurrent() - (TimeCurrent() % 86400);
   if(today != g_dailyDate)                                            // Novo dia → reseta
   {
      g_dailyDate = today;
      g_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_dailyLocked = false;
      CLogger::Info("RISK", StringFormat("Novo dia — equity base: $%.2f", g_dailyStartEquity));
   }
   if(g_dailyLocked) return false;                                     // Ja bloqueado
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct = (g_dailyStartEquity > 0) ? ((g_dailyStartEquity - equity) / g_dailyStartEquity * 100.0) : 0;
   if(ddPct >= InpMaxDDPct)
   {
      g_dailyLocked = true;
      CLogger::Warn("RISK", StringFormat("MAX DD DIARIO atingido: %.2f%% >= %.2f%% — BLOQUEADO", ddPct, InpMaxDDPct));
      return false;
   }
   return true;
}

bool CheckMaxExposure(double newLot)
{
   if(!InpUseMaxExposure) return true;
   double total = GetTotalExposure() + newLot;
   if(total > InpMaxExposure)
   {
      g_exposureBlocked++;
      if(InpDebugMode)
         CLogger::Debug("RISK", StringFormat("Exposicao %.2f + %.2f > max %.2f", GetTotalExposure(), newLot, InpMaxExposure));
      return false;
   }
   return true;
}

double GetTotalExposure()
{
   double total = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_activeSymbol) continue;
      int mag = (int)PositionGetInteger(POSITION_MAGIC);
      if(mag >= InpMagic && mag <= InpMagic + MAGIC_BOX)
         total += PositionGetDouble(POSITION_VOLUME);
   }
   return total;
}

bool CheckAntiHedge(int boxSide)
{
   if(!InpUseAntiHedge) return true;
   // Ignora CE1 (independente) — so verifica CE2 e combo
   int ce2Buys  = CountPosByMagic(POSITION_TYPE_BUY,  InpMagic+MAGIC_CE2);
   int ce2Sells = CountPosByMagic(POSITION_TYPE_SELL, InpMagic+MAGIC_CE2);
   int coBuys   = CountPosByMagic(POSITION_TYPE_BUY,  InpMagic+MAGIC_COMBO);
   int coSells  = CountPosByMagic(POSITION_TYPE_SELL, InpMagic+MAGIC_COMBO);
   if(boxSide == 1  && (ce2Sells>0 || coSells>0))                     // BOX BUY vs CE2/combo SELL
   { g_hedgeBlocked++; return false; }
   if(boxSide == -1 && (ce2Buys>0  || coBuys>0))                      // BOX SELL vs CE2/combo BUY
   { g_hedgeBlocked++; return false; }
   return true;
}

//=====================================================================
// SECAO 8: DISPATCHER
//=====================================================================

void OnTimer() { ProcessMain(); }
void OnTick()  { ProcessMain(); }

void ProcessMain()
{
   //--- Novo brick? (bar[1] = ultimo brick completo)
   datetime barTime = iTime(g_csName, PERIOD_M1, 1);
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;

   double o1 = iOpen(g_csName, PERIOD_M1, 1);
   double c1 = iClose(g_csName, PERIOD_M1, 1);
   if(o1==0 || c1==0) return;

   bool bull = (c1 > o1);
   g_bricksTotal++;
   if(bull) g_bricksBull++; else g_bricksBear++;
   CaptureSpread();

   if(InpDebugMode)
      CLogger::Debug("MAIN", StringFormat("Brick #%d %s | O:%.2f C:%.2f",
         g_bricksTotal, bull?"BULL":"BEAR", o1, c1));

   //--- Calcula CE1 + CE2
   UpdateCE1();
   if(!g_ce1Ready) return;
   UpdateCE2();

   //--- Regime detection
   g_regimeChanged = false;
   if(InpUseRegime && g_ce2Ready)
   {
      bool wasTrend = g_regimeTrend;
      g_regimeTrend = !g_ce2Flat;                                     // CE2 inclinada = trend
      if(wasTrend != g_regimeTrend)
      {
         g_regimeChanged = true;
         CLogger::Info("REGIME", StringFormat("→ %s", g_regimeTrend ? "TREND" : "LATERAL"));
      }
   }

   //--- Risco diario
   if(!CheckDailyDrawdown()) return;                                   // Dia bloqueado

   //--- Visual
   if(InpDrawCE) DrawCELines(barTime);

   //--- Hierarquia: combo ativo → CE1/CE2 solo dormem?
   bool comboDormancy = InpUseCombo && InpComboHierarchy && g_ce2Ready && !g_ce2Flat
                        && g_ce1Dir == g_ce2Dir && !g_ce1Flat;

   //=== CE1 SOLO — SEMPRE RODA (independente) ===
   if(InpUseCE1 && !comboDormancy)
      ProcessCE1Solo(c1, bull, barTime);

   //=== CE2 SOLO — REGIME TREND (ou sempre se switch OFF) ===
   bool ce2CanRun = InpUseCE2 && g_ce2Ready && (!InpUseRegime || g_regimeTrend) && !comboDormancy;
   if(ce2CanRun)
      ProcessCE2Solo(c1, bull, barTime);

   //=== COMBO — REGIME TREND (ou sempre se switch OFF) ===
   bool comboCanRun = InpUseCombo && g_ce1Ready && g_ce2Ready && (!InpUseRegime || g_regimeTrend);
   if(comboCanRun)
      ProcessCombo(c1, bull, barTime);

   //=== BOX — REGIME LATERAL (ou sempre se switch OFF) ===
   bool boxCanRun = InpUseBox && g_ce2Ready && (!InpUseRegime || !g_regimeTrend);
   if(boxCanRun)
      ProcessBox(c1, bull, barTime);

   //=== PYRAMID ===
   if(InpUsePyramid)
      ProcessPyramid(c1, bull, barTime);

   //--- Comment
   UpdateComment();
}

//=====================================================================
// SECAO 9: CALCULO CE1
//=====================================================================

void UpdateCE1()
{
   double closes[];
   if(CopyClose(g_csName, PERIOD_M1, 1, InpCE1Period, closes) != InpCE1Period) return;
   double hi=closes[0], lo=closes[0];
   for(int i=1; i<InpCE1Period; i++) { if(closes[i]>hi) hi=closes[i]; if(closes[i]<lo) lo=closes[i]; }
   double off=InpCE1Brick*InpCE1Mult, bR=hi-off, sR=lo+off;
   if(InpCE1Ratchet)
   { if(!g_ce1Ready||g_ce1Dir==-1) g_ce1Bull=bR; else g_ce1Bull=MathMax(g_ce1Bull,bR);
     if(!g_ce1Ready||g_ce1Dir== 1) g_ce1Bear=sR; else g_ce1Bear=MathMin(g_ce1Bear,sR); }
   else { g_ce1Bull=bR; g_ce1Bear=sR; }
   g_ce1PrevDir=g_ce1Dir; double cc=closes[InpCE1Period-1];
   if(g_ce1Dir==0) g_ce1Dir=(cc>=g_ce1Bull)?1.0:-1.0;
   else { if(g_ce1Dir==1&&cc<g_ce1Bull) g_ce1Dir=-1; if(g_ce1Dir==-1&&cc>g_ce1Bear) g_ce1Dir=1; }
   for(int i=CE_HIST_MAX-1;i>0;i--) { g_ce1BullHist[i]=g_ce1BullHist[i-1]; g_ce1BearHist[i]=g_ce1BearHist[i-1]; }
   g_ce1BullHist[0]=g_ce1Bull; g_ce1BearHist[0]=g_ce1Bear;
   if(g_ce1HistCount<CE_HIST_MAX) g_ce1HistCount++;
   g_ce1Flat=true; g_ce1FlatDiff=0;
   if(g_ce1HistCount>InpCE1FlatBricks)
   { double t=InpCE1Brick*0.5;
     g_ce1FlatDiff=(g_ce1Dir==1)?MathAbs(g_ce1BullHist[0]-g_ce1BullHist[InpCE1FlatBricks])
                                :MathAbs(g_ce1BearHist[0]-g_ce1BearHist[InpCE1FlatBricks]);
     g_ce1Flat=(g_ce1FlatDiff<t); }
   g_ce1Ready=true;
   if(InpDebugMode) CLogger::Debug("CE1", StringFormat("%s %s d=%.2f",
      g_ce1Dir==1?"BULL":"BEAR", g_ce1Flat?"FLAT":"INCL", g_ce1FlatDiff));
}

//=====================================================================
// SECAO 10: CALCULO CE2
//=====================================================================

void UpdateCE2()
{
   double closes[];
   if(CopyClose(g_csName, PERIOD_M1, 1, InpCE2Period, closes) != InpCE2Period) return;
   double hi=closes[0], lo=closes[0];
   for(int i=1; i<InpCE2Period; i++) { if(closes[i]>hi) hi=closes[i]; if(closes[i]<lo) lo=closes[i]; }
   double off=InpCE2Brick*InpCE2Mult, bR=hi-off, sR=lo+off;
   if(InpCE2Ratchet)
   { if(!g_ce2Ready||g_ce2Dir==-1) g_ce2Bull=bR; else g_ce2Bull=MathMax(g_ce2Bull,bR);
     if(!g_ce2Ready||g_ce2Dir== 1) g_ce2Bear=sR; else g_ce2Bear=MathMin(g_ce2Bear,sR); }
   else { g_ce2Bull=bR; g_ce2Bear=sR; }
   g_ce2PrevDir=g_ce2Dir; double cc=closes[InpCE2Period-1];
   if(g_ce2Dir==0) g_ce2Dir=(cc>=g_ce2Bull)?1.0:-1.0;
   else { if(g_ce2Dir==1&&cc<g_ce2Bull) g_ce2Dir=-1; if(g_ce2Dir==-1&&cc>g_ce2Bear) g_ce2Dir=1; }
   for(int i=CE_HIST_MAX-1;i>0;i--) { g_ce2BullHist[i]=g_ce2BullHist[i-1]; g_ce2BearHist[i]=g_ce2BearHist[i-1]; }
   g_ce2BullHist[0]=g_ce2Bull; g_ce2BearHist[0]=g_ce2Bear;
   if(g_ce2HistCount<CE_HIST_MAX) g_ce2HistCount++;
   g_ce2Flat=true; g_ce2FlatDiff=0;
   if(g_ce2HistCount>InpCE2FlatBricks)
   { double t=InpCE2Brick*0.5;
     g_ce2FlatDiff=(g_ce2Dir==1)?MathAbs(g_ce2BullHist[0]-g_ce2BullHist[InpCE2FlatBricks])
                                :MathAbs(g_ce2BearHist[0]-g_ce2BearHist[InpCE2FlatBricks]);
     g_ce2Flat=(g_ce2FlatDiff<t); }
   g_ce2Ready=true;
   if(InpDebugMode) CLogger::Debug("CE2", StringFormat("%s %s d=%.2f",
      g_ce2Dir==1?"BULL":"BEAR", g_ce2Flat?"FLAT":"INCL", g_ce2FlatDiff));
}

//=====================================================================
// SECAO 11: CE1 SOLO — MICRO SCALP
//=====================================================================
//
// LOGICA:
//   CE1 inclinada + nao flat → entra na direcao
//   100% independente: nao depende de CE2, regime, ou hierarquia
//   Saidas: CE1 flip | N bricks contra
//   Re-entrada: apos saida por N bricks, se CE1 mesma dir + inclinada
//   Max re-entradas por tendencia (input)
//   Sem trailing (trades muito curtos)
//
//=====================================================================

void ProcessCE1Solo(double lastClose, bool lastBull, datetime barTime)
{
   int magic = InpMagic + MAGIC_CE1;                                   // Magic CE1 solo
   int buyCount  = CountPosByMagic(POSITION_TYPE_BUY,  magic);
   int sellCount = CountPosByMagic(POSITION_TYPE_SELL, magic);
   int totalPos  = buyCount + sellCount;

   bool isBull = (g_ce1Dir == 1);                                      // Direcao CE1
   bool isBear = (g_ce1Dir == -1);
   bool flipB  = (isBull && g_ce1PrevDir != 1);                       // CE1 flipou para bull
   bool flipS  = (isBear && g_ce1PrevDir != -1);                      // CE1 flipou para bear

   //--- CE1 flipou → reset contadores
   if(flipB || flipS)
   {
      g_ce1ReCount = 0;                                                // Nova tendencia, zera re-entradas
      if(InpDebugMode)
         CLogger::Debug("CE1_SOLO", StringFormat("FLIP → %s | Delay=%d | Re-count reset",
            flipB?"BULL":"BEAR", InpCE1EntryDelay));
   }

   //=== SAIDAS ===
   bool exitThisBrick = false;                                         // Guard: nao entra no mesmo brick da saida

   //--- Saida 1: CE1 flip fecha posicao
   if(InpCE1ExitFlip && totalPos > 0)
   {
      if(flipS && buyCount > 0)                                        // CE1 → BEAR, fecha BUY
      {
         CloseByMagic(POSITION_TYPE_BUY, magic);
         if(InpUseStressLab) g_costCommission += InpCommissionExit * buyCount;
         buyCount = 0; totalPos = 0; g_ce1OppCount = 0;
         g_ce1ConfirmCount = 0; exitThisBrick = true;                  // Reset + guard
         CLogger::Info("CE1_SOLO", "SAIDA FLIP → BEAR | Fechou BUY");
      }
      if(flipB && sellCount > 0)                                       // CE1 → BULL, fecha SELL
      {
         CloseByMagic(POSITION_TYPE_SELL, magic);
         if(InpUseStressLab) g_costCommission += InpCommissionExit * sellCount;
         sellCount = 0; totalPos = 0; g_ce1OppCount = 0;
         g_ce1ConfirmCount = 0; exitThisBrick = true;                  // Reset + guard
         CLogger::Info("CE1_SOLO", "SAIDA FLIP → BULL | Fechou SELL");
      }
   }

   //--- Saida 2: N bricks contrarios + re-entrada
   if(InpCE1ExitBricks && totalPos > 0)
   {
      bool isOpp = (buyCount>0 && !lastBull) || (sellCount>0 && lastBull);
      if(isOpp) g_ce1OppCount++; else g_ce1OppCount = 0;

      if(g_ce1OppCount >= InpCE1ExitN)
      {
         ENUM_POSITION_TYPE closeType = buyCount>0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         CloseByMagic(closeType, magic);
         if(InpUseStressLab) g_costCommission += InpCommissionExit * totalPos;
         g_ce1OppCount = 0;
         g_ce1ConfirmCount = 0; exitThisBrick = true;                  // Reset + guard
         CLogger::Info("CE1_SOLO", StringFormat("SAIDA %d bricks contra", InpCE1ExitN));

         //--- Re-entrada mesma tendencia
         if(InpCE1ReEntry && !g_ce1Flat && CheckSession())
         {
            if(g_ce1ReCount >= InpCE1ReMax)                            // Limite de re-entradas atingido
            {
               CLogger::Info("CE1_SOLO", StringFormat("RE bloqueada — max %d/%d", g_ce1ReCount, InpCE1ReMax));
            }
            else if(!CheckMaxExposure(InpCE1Lot))                      // Exposicao global
            {
               CLogger::Info("CE1_SOLO", "RE bloqueada — max exposicao");
            }
            else
            {
               double cost = 0;
               bool canExec = !InpUseStressLab || SimulateExecution("CE1_RE", InpCE1Lot, cost);
               if(canExec && isBull)
               {
                  if(g_tradeCE1.Buy(InpCE1Lot, g_activeSymbol, 0, 0, 0, "CE1_RE_BUY"))
                  { g_ce1Trades++; g_ce1Buys++; g_ce1ReCount++; g_ce1OppCount = 0;
                    CLogger::Info("CE1_SOLO", StringFormat("RE BUY #%d/%d | $%.2f",
                       g_ce1ReCount, InpCE1ReMax, cost)); }
               }
               else if(canExec && isBear)
               {
                  if(g_tradeCE1.Sell(InpCE1Lot, g_activeSymbol, 0, 0, 0, "CE1_RE_SELL"))
                  { g_ce1Trades++; g_ce1Sells++; g_ce1ReCount++; g_ce1OppCount = 0;
                    CLogger::Info("CE1_SOLO", StringFormat("RE SELL #%d/%d | $%.2f",
                       g_ce1ReCount, InpCE1ReMax, cost)); }
               }
            }
         }
         // Atualiza contadores apos re-entrada
         buyCount  = CountPosByMagic(POSITION_TYPE_BUY,  magic);
         sellCount = CountPosByMagic(POSITION_TYPE_SELL, magic);
         totalPos  = buyCount + sellCount;
      }
   }
   else if(totalPos == 0) g_ce1OppCount = 0;                          // Sem posicao → zera opp

   //=== PYRAMID CE1: confirmacao de momentum ===
   if(InpCE1PyrMax > 0 && totalPos > 0 && totalPos <= InpCE1PyrMax)
   {
      //--- Verifica N bricks consecutivos na direcao da posicao
      bool pyrOK = true;
      bool pyrIsBuy = (buyCount > 0);
      for(int k = 1; k <= InpCE1PyrBricks; k++)
      {
         double pO = iOpen(g_csName, PERIOD_M1, k);
         double pC = iClose(g_csName, PERIOD_M1, k);
         if(pO==0 || pC==0) { pyrOK=false; break; }
         bool kBull = (pC > pO);
         if(kBull != pyrIsBuy) { pyrOK=false; break; }                // Brick na direcao errada
      }

      if(pyrOK && !g_ce1Flat && CheckSession() && CheckMaxExposure(InpCE1Lot))
      {
         double cost = 0;
         bool canExec = !InpUseStressLab || SimulateExecution("CE1_PYR", InpCE1Lot, cost);
         if(canExec && pyrIsBuy)
         {
            if(g_tradeCE1.Buy(InpCE1Lot, g_activeSymbol, 0, 0, 0, "CE1_PYR_BUY"))
            { g_ce1PyrAdds++; g_ce1OppCount = 0;
              CLogger::Info("CE1_SOLO", StringFormat("PYR BUY #%d/%d | %d bricks consec | $%.2f",
                 totalPos+1, InpCE1PyrMax+1, InpCE1PyrBricks, cost)); }
         }
         else if(canExec && !pyrIsBuy)
         {
            if(g_tradeCE1.Sell(InpCE1Lot, g_activeSymbol, 0, 0, 0, "CE1_PYR_SELL"))
            { g_ce1PyrAdds++; g_ce1OppCount = 0;
              CLogger::Info("CE1_SOLO", StringFormat("PYR SELL #%d/%d | %d bricks consec | $%.2f",
                 totalPos+1, InpCE1PyrMax+1, InpCE1PyrBricks, cost)); }
         }
      }
   }

   //=== ENTRADA CE1 SOLO ===
   if(totalPos > 0) return;                                            // Ja tem posicao → nao entra
   if(exitThisBrick) return;                                           // Saiu neste brick → nao re-entra

   //--- 1. Flat = nao entra + reseta confirmacao
   if(g_ce1Flat)
   {
      g_ce1ConfirmCount = 0;                                           // Reset: CE1 parou de mover
      g_flatBlocked++;
      return;
   }

   //--- 2. Direcao mudou = reseta confirmacao
   if(g_ce1Dir != g_ce1ConfirmDir)
   {
      g_ce1ConfirmCount = 0;                                           // Nova direcao, recomeca contagem
      g_ce1ConfirmDir = g_ce1Dir;                                      // Salva direcao atual
   }

   //--- 3. CE1 inclinada → conta bricks de confirmacao
   g_ce1ConfirmCount++;

   if(InpDebugMode)
      CLogger::Debug("CE1_SOLO", StringFormat("Confirm: %s incl | count=%d/%d",
         isBull?"BULL":"BEAR", g_ce1ConfirmCount, InpCE1EntryDelay));

   //--- 4. Ainda nao confirmou N bricks
   if(g_ce1ConfirmCount <= InpCE1EntryDelay) return;

   //--- 5. Brick atual deve ser na MESMA direcao que CE1
   if(isBull && !lastBull) return;                                     // CE1 bull mas brick bear → espera
   if(isBear && lastBull) return;                                      // CE1 bear mas brick bull → espera

   //--- Filtros finais
   if(!CheckSession()) { g_sessionBlocked++; return; }
   if(!CheckMaxExposure(InpCE1Lot)) return;

   //--- ENTRA
   if(isBull && buyCount == 0 && sellCount == 0)
   {
      double cost = 0;
      bool canExec = !InpUseStressLab || SimulateExecution("CE1_BUY", InpCE1Lot, cost);
      if(canExec && g_tradeCE1.Buy(InpCE1Lot, g_activeSymbol, 0, 0, 0, "CE1_BUY"))
      {
         g_ce1Trades++; g_ce1Buys++; g_ce1OppCount = 0;
         g_ce1ConfirmCount = 0;                                        // Reset apos entrada
         CLogger::Info("CE1_SOLO", StringFormat("BUY | lot=%.2f | $%.2f", InpCE1Lot, cost));
      }
   }
   else if(isBear && sellCount == 0 && buyCount == 0)
   {
      double cost = 0;
      bool canExec = !InpUseStressLab || SimulateExecution("CE1_SELL", InpCE1Lot, cost);
      if(canExec && g_tradeCE1.Sell(InpCE1Lot, g_activeSymbol, 0, 0, 0, "CE1_SELL"))
      {
         g_ce1Trades++; g_ce1Sells++; g_ce1OppCount = 0;
         g_ce1ConfirmCount = 0;                                        // Reset apos entrada
         CLogger::Info("CE1_SOLO", StringFormat("SELL | lot=%.2f | $%.2f", InpCE1Lot, cost));
      }
   }
}

//=====================================================================
// SECAO 12: CE2 SOLO — SCALP
//=====================================================================
//
// LOGICA:
//   CE2 inclinada + nao flat → entra na direcao
//   Regime: TREND (se switch ON), senao roda sempre
//   Saidas: CE2 flip | N bricks contra | Trailing 3F
//   Re-entrada: apos saida por N bricks, se CE2 mesma dir + inclinada
//   Max re-entradas por tendencia (input)
//
// TRAILING 3F:
//   F1 (inicial): trail a F1 bricks do melhor preco
//   F2 (break-even): quando lucro >= F1, trail no preco de entrada
//   F3 (tight): quando lucro >= F1+F3, trail a F3 bricks do melhor
//
//=====================================================================

void ProcessCE2Solo(double lastClose, bool lastBull, datetime barTime)
{
   int magic = InpMagic + MAGIC_CE2;                                   // Magic CE2 solo
   int buyCount  = CountPosByMagic(POSITION_TYPE_BUY,  magic);
   int sellCount = CountPosByMagic(POSITION_TYPE_SELL, magic);
   int totalPos  = buyCount + sellCount;

   bool isBull = (g_ce2Dir == 1);                                      // Direcao CE2
   bool isBear = (g_ce2Dir == -1);
   bool flipB  = (isBull && g_ce2PrevDir != 1);                       // CE2 flipou para bull
   bool flipS  = (isBear && g_ce2PrevDir != -1);                      // CE2 flipou para bear

   //--- CE2 flipou → reset contadores + inicia countdown
   if(flipB || flipS)
   {
      g_ce2ReCount = 0;
      g_ce2FlipWait = InpCE2EntryDelay + 1;                            // +1 para entrar APOS N bricks
      g_ce2FlipDir = g_ce2Dir;
      if(InpDebugMode)
         CLogger::Debug("CE2_SOLO", StringFormat("FLIP → %s | Delay=%d | Re-count reset",
            flipB?"BULL":"BEAR", InpCE2EntryDelay));
   }

   //--- Se CE2 mudou de direcao durante countdown → cancela
   if(g_ce2FlipWait > 0 && g_ce2Dir != g_ce2FlipDir)
   {
      g_ce2FlipWait = 0;
      if(InpDebugMode)
         CLogger::Debug("CE2_SOLO", "Entry delay CANCELADO — direcao mudou");
   }

   //=== SAIDAS ===

   //--- Saida 1: CE2 flip fecha posicao
   if(InpCE2ExitFlip && totalPos > 0)
   {
      if(flipS && buyCount > 0)                                        // CE2 → BEAR, fecha BUY
      {
         CloseByMagic(POSITION_TYPE_BUY, magic);
         if(InpUseStressLab) g_costCommission += InpCommissionExit * buyCount;
         buyCount = 0; totalPos = 0; g_ce2OppCount = 0;
         ResetTrailingCE2();
         CLogger::Info("CE2_SOLO", "SAIDA CE2 FLIP → BEAR | Fechou BUY");
      }
      if(flipB && sellCount > 0)                                       // CE2 → BULL, fecha SELL
      {
         CloseByMagic(POSITION_TYPE_SELL, magic);
         if(InpUseStressLab) g_costCommission += InpCommissionExit * sellCount;
         sellCount = 0; totalPos = 0; g_ce2OppCount = 0;
         ResetTrailingCE2();
         CLogger::Info("CE2_SOLO", "SAIDA CE2 FLIP → BULL | Fechou SELL");
      }
   }

   //--- Saida 2: Trailing 3F
   if(InpCE2UseTrail && totalPos > 0)
   {
      bool tsClosed = ProcessTrailingCE2(buyCount, sellCount, lastClose, magic);
      if(tsClosed)
      {
         buyCount  = CountPosByMagic(POSITION_TYPE_BUY,  magic);
         sellCount = CountPosByMagic(POSITION_TYPE_SELL, magic);
         totalPos  = buyCount + sellCount;
      }
   }

   //--- Saida 3: N bricks contrarios + re-entrada
   if(InpCE2ExitBricks && totalPos > 0)
   {
      bool isOpp = (buyCount>0 && !lastBull) || (sellCount>0 && lastBull);
      if(isOpp) g_ce2OppCount++; else g_ce2OppCount = 0;

      if(g_ce2OppCount >= InpCE2ExitN)
      {
         ENUM_POSITION_TYPE closeType = buyCount>0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         CloseByMagic(closeType, magic);
         if(InpUseStressLab) g_costCommission += InpCommissionExit * totalPos;
         g_ce2OppCount = 0;
         ResetTrailingCE2();
         CLogger::Info("CE2_SOLO", StringFormat("SAIDA %d bricks contra", InpCE2ExitN));

         //--- Re-entrada mesma tendencia
         if(InpCE2ReEntry && !g_ce2Flat && CheckSession())
         {
            if(g_ce2ReCount >= InpCE2ReMax)
            {
               CLogger::Info("CE2_SOLO", StringFormat("RE bloqueada — max %d/%d", g_ce2ReCount, InpCE2ReMax));
            }
            else if(!CheckMaxExposure(InpCE2Lot))
            {
               CLogger::Info("CE2_SOLO", "RE bloqueada — max exposicao");
            }
            else
            {
               double cost = 0;
               bool canExec = !InpUseStressLab || SimulateExecution("CE2_RE", InpCE2Lot, cost);
               if(canExec && isBull)
               {
                  if(g_tradeCE2.Buy(InpCE2Lot, g_activeSymbol, 0, 0, 0, "CE2_RE_BUY"))
                  { g_ce2Trades++; g_ce2Buys++; g_ce2ReCount++; g_ce2OppCount = 0;
                    InitTrailingCE2(true, SymbolInfoDouble(g_activeSymbol, SYMBOL_ASK));
                    CLogger::Info("CE2_SOLO", StringFormat("RE BUY #%d/%d | $%.2f",
                       g_ce2ReCount, InpCE2ReMax, cost)); }
               }
               else if(canExec && isBear)
               {
                  if(g_tradeCE2.Sell(InpCE2Lot, g_activeSymbol, 0, 0, 0, "CE2_RE_SELL"))
                  { g_ce2Trades++; g_ce2Sells++; g_ce2ReCount++; g_ce2OppCount = 0;
                    InitTrailingCE2(false, SymbolInfoDouble(g_activeSymbol, SYMBOL_BID));
                    CLogger::Info("CE2_SOLO", StringFormat("RE SELL #%d/%d | $%.2f",
                       g_ce2ReCount, InpCE2ReMax, cost)); }
               }
            }
         }
         buyCount  = CountPosByMagic(POSITION_TYPE_BUY,  magic);
         sellCount = CountPosByMagic(POSITION_TYPE_SELL, magic);
         totalPos  = buyCount + sellCount;
      }
   }
   else if(totalPos == 0) g_ce2OppCount = 0;

   //=== ENTRADA (somente via flip + countdown) ===
   if(totalPos > 0) return;
   if(g_ce2FlipWait <= 0) return;                                      // Sem flip pendente

   g_ce2FlipWait--;
   if(g_ce2FlipWait > 0)
   {
      if(InpDebugMode)
         CLogger::Debug("CE2_SOLO", StringFormat("Entry delay: %d bricks restantes", g_ce2FlipWait));
      return;
   }
   if(g_ce2Dir != g_ce2FlipDir)
   { if(InpDebugMode) CLogger::Debug("CE2_SOLO", "Entry CANCELADA — direcao mudou"); return; }

   //--- Flip detectado → IGNORA flat
   if(InpDebugMode)
      CLogger::Debug("CE2_SOLO", StringFormat("Entry via flip — %s (flat=%s ignorado)",
         isBull?"BULL":"BEAR", g_ce2Flat?"SIM":"NAO"));

   if(!CheckSession()) { g_sessionBlocked++; return; }
   if(!CheckMaxExposure(InpCE2Lot)) return;

   double cost = 0;
   bool canExec = !InpUseStressLab || SimulateExecution(isBull?"CE2_BUY":"CE2_SELL", InpCE2Lot, cost);
   if(!canExec) return;

   if(isBull && buyCount == 0 && sellCount == 0)
   {
      if(g_tradeCE2.Buy(InpCE2Lot, g_activeSymbol, 0, 0, 0, "CE2_BUY"))
      {
         g_ce2Trades++; g_ce2Buys++; g_ce2OppCount = 0;
         InitTrailingCE2(true, SymbolInfoDouble(g_activeSymbol, SYMBOL_ASK));
         CLogger::Info("CE2_SOLO", StringFormat("BUY | lot=%.2f | $%.2f", InpCE2Lot, cost));
      }
   }
   else if(isBear && sellCount == 0 && buyCount == 0)
   {
      if(g_tradeCE2.Sell(InpCE2Lot, g_activeSymbol, 0, 0, 0, "CE2_SELL"))
      {
         g_ce2Trades++; g_ce2Sells++; g_ce2OppCount = 0;
         InitTrailingCE2(false, SymbolInfoDouble(g_activeSymbol, SYMBOL_BID));
         CLogger::Info("CE2_SOLO", StringFormat("SELL | lot=%.2f | $%.2f", InpCE2Lot, cost));
      }
   }
}

//--- Trailing 3F helpers para CE2 ---

void InitTrailingCE2(bool isBuy, double entryPrice)
{
   if(!InpCE2UseTrail) return;
   g_ce2TsAvg   = entryPrice;                                         // Preco de entrada
   g_ce2TsDir   = isBuy ? 1 : -1;                                     // Direcao
   g_ce2TsPhase = 1;                                                   // Fase 1: inicial
   g_ce2TsBest  = entryPrice;                                          // Melhor preco = entrada
   if(InpDebugMode)
      CLogger::Debug("CE2_TS", StringFormat("INIT %s @ %.2f", isBuy?"BUY":"SELL", entryPrice));
}

void ResetTrailingCE2()
{
   g_ce2TsAvg = 0; g_ce2TsDir = 0; g_ce2TsPhase = 0; g_ce2TsBest = 0;
}

bool ProcessTrailingCE2(int buyCount, int sellCount, double lastClose, int magic)
{
   if(g_ce2TsPhase == 0) return false;                                 // Trailing inativo

   //--- Atualiza melhor preco
   if(g_ce2TsDir == 1  && lastClose > g_ce2TsBest) g_ce2TsBest = lastClose;
   if(g_ce2TsDir == -1 && lastClose < g_ce2TsBest) g_ce2TsBest = lastClose;

   double profitBricks = MathAbs(g_ce2TsBest - g_ce2TsAvg) / g_brickSize;
   double retraceBricks = MathAbs(g_ce2TsBest - lastClose) / g_brickSize;

   //--- Transicao de fase
   if(g_ce2TsPhase == 1 && profitBricks >= InpCE2TrailInit)            // F1 → F2 (break-even)
   {
      g_ce2TsPhase = 2;
      CLogger::Info("CE2_TS", StringFormat("F1→F2 BE | profit=%.1f bricks", profitBricks));
   }
   if(g_ce2TsPhase == 2 && profitBricks >= InpCE2TrailInit + InpCE2TrailTight) // F2 → F3 (tight)
   {
      g_ce2TsPhase = 3;
      CLogger::Info("CE2_TS", StringFormat("F2→F3 TIGHT | profit=%.1f bricks", profitBricks));
   }

   //--- Checa saida por trailing
   bool shouldClose = false;
   if(g_ce2TsPhase == 1 && retraceBricks >= InpCE2TrailInit)           // F1: retracou F1 bricks
      shouldClose = true;
   else if(g_ce2TsPhase == 2)                                          // F2: preco voltou ao entry (BE)
   {
      if(g_ce2TsDir == 1  && lastClose <= g_ce2TsAvg) shouldClose = true;
      if(g_ce2TsDir == -1 && lastClose >= g_ce2TsAvg) shouldClose = true;
   }
   else if(g_ce2TsPhase == 3 && retraceBricks >= InpCE2TrailTight)     // F3: retracou F3 bricks
      shouldClose = true;

   if(shouldClose)
   {
      ENUM_POSITION_TYPE closeType = (g_ce2TsDir==1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      CloseByMagic(closeType, magic);
      if(InpUseStressLab) g_costCommission += InpCommissionExit;
      CLogger::Info("CE2_TS", StringFormat("SAIDA F%d | best=%.2f cl=%.2f retrace=%.1f bricks",
         g_ce2TsPhase, g_ce2TsBest, lastClose, retraceBricks));
      ResetTrailingCE2(); g_ce2OppCount = 0;
      return true;
   }

   if(InpDebugMode)
      CLogger::Debug("CE2_TS", StringFormat("F%d | best=%.2f cl=%.2f profit=%.1f ret=%.1f",
         g_ce2TsPhase, g_ce2TsBest, lastClose, profitBricks, retraceBricks));
   return false;
}

//=====================================================================
// SECAO 13: CE1+CE2 COMBO — SCALP MAIOR
//=====================================================================
//
// LOGICA:
//   CE1 + CE2 mesma direcao + ambas inclinadas → entra
//   Regime: TREND (se switch ON)
//   Saidas: Trailing 3F | CE1 flip | Timeout N bricks sem progresso
//   Re-entrada: apos saida, se ambas CEs confirmam
//   Hierarquia: ON/OFF (CE1/CE2 solo dormem quando combo ativa)
//
//=====================================================================

void ProcessCombo(double lastClose, bool lastBull, datetime barTime)
{
   int magic = InpMagic + MAGIC_COMBO;
   int buyCount  = CountPosByMagic(POSITION_TYPE_BUY,  magic);
   int sellCount = CountPosByMagic(POSITION_TYPE_SELL, magic);
   int totalPos  = buyCount + sellCount;

   bool bothBull = (g_ce1Dir == 1  && g_ce2Dir == 1);                  // Ambos bull
   bool bothBear = (g_ce1Dir == -1 && g_ce2Dir == -1);                 // Ambos bear
   bool bothIncl = (!g_ce1Flat && !g_ce2Flat);                         // Ambos inclinados
   bool comboOK  = (bothBull || bothBear) && bothIncl;                 // Condicao completa

   //--- CE1 flipou → reset re-count (usamos CE1 flip como referencia de mudanca)
   bool ce1FlipB = (g_ce1Dir == 1  && g_ce1PrevDir != 1);
   bool ce1FlipS = (g_ce1Dir == -1 && g_ce1PrevDir != -1);
   if(ce1FlipB || ce1FlipS)
   {
      g_comboReCount = 0;
      //--- Combo recebeu confirmacao → inicia countdown
      if(comboOK)
      {
         g_comboFlipWait = InpComboEntryDelay + 1;                     // +1: delay=0 entra no mesmo brick
         g_comboFlipDir = g_ce1Dir;
         if(InpDebugMode)
            CLogger::Debug("COMBO", StringFormat("CE1 FLIP + combo OK → Delay=%d", InpComboEntryDelay));
      }
   }

   //--- CE2 flipou → tambem pode iniciar countdown do combo
   bool ce2FlipB = (g_ce2Dir == 1  && g_ce2PrevDir != 1);
   bool ce2FlipS = (g_ce2Dir == -1 && g_ce2PrevDir != -1);
   if((ce2FlipB || ce2FlipS) && comboOK && g_comboFlipWait == 0)
   {
      g_comboFlipWait = InpComboEntryDelay + 1;
      g_comboFlipDir = g_ce2Dir;
      if(InpDebugMode)
         CLogger::Debug("COMBO", StringFormat("CE2 FLIP + combo OK → Delay=%d", InpComboEntryDelay));
   }

   //--- Se combo desfez durante countdown → cancela
   if(g_comboFlipWait > 0 && g_ce1Dir != g_comboFlipDir)
   {
      g_comboFlipWait = 0;
      if(InpDebugMode)
         CLogger::Debug("COMBO", "Entry delay CANCELADO — direcao mudou");
   }

   //=== SAIDAS ===

   //--- Saida 1: CE1 flip fecha combo
   if(InpComboExitFlip && totalPos > 0)
   {
      if(ce1FlipS && buyCount > 0)
      {
         CloseByMagic(POSITION_TYPE_BUY, magic);
         if(InpUseStressLab) g_costCommission += InpCommissionExit * buyCount;
         buyCount = 0; totalPos = 0; g_comboStagnant = 0;
         ResetTrailingCombo();
         CLogger::Info("COMBO", "SAIDA CE1 FLIP → BEAR | Fechou BUY");
      }
      if(ce1FlipB && sellCount > 0)
      {
         CloseByMagic(POSITION_TYPE_SELL, magic);
         if(InpUseStressLab) g_costCommission += InpCommissionExit * sellCount;
         sellCount = 0; totalPos = 0; g_comboStagnant = 0;
         ResetTrailingCombo();
         CLogger::Info("COMBO", "SAIDA CE1 FLIP → BULL | Fechou SELL");
      }
   }

   //--- Saida 2: Trailing 3F
   if(InpComboUseTrail && totalPos > 0)
   {
      bool tsClosed = ProcessTrailingCombo(buyCount, sellCount, lastClose, magic);
      if(tsClosed)
      {
         buyCount  = CountPosByMagic(POSITION_TYPE_BUY,  magic);
         sellCount = CountPosByMagic(POSITION_TYPE_SELL, magic);
         totalPos  = buyCount + sellCount;
         g_comboStagnant = 0;
      }
   }

   //--- Saida 3: Timeout — N bricks sem progresso
   if(InpComboExitTimeout && totalPos > 0)
   {
      //--- Atualiza melhor preco e stagnation
      bool newProgress = false;
      if(buyCount > 0  && lastClose > g_comboBestPrice) { g_comboBestPrice = lastClose; newProgress = true; }
      if(sellCount > 0 && lastClose < g_comboBestPrice) { g_comboBestPrice = lastClose; newProgress = true; }
      if(newProgress) g_comboStagnant = 0; else g_comboStagnant++;

      if(g_comboStagnant >= InpComboTimeoutN)
      {
         ENUM_POSITION_TYPE closeType = buyCount>0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         CloseByMagic(closeType, magic);
         if(InpUseStressLab) g_costCommission += InpCommissionExit * totalPos;
         g_comboStagnant = 0;
         ResetTrailingCombo();
         CLogger::Info("COMBO", StringFormat("SAIDA TIMEOUT | %d bricks sem progresso", InpComboTimeoutN));

         //--- Re-entrada apos timeout
         if(InpComboReEntry && comboOK && CheckSession() && g_comboReCount < InpComboReMax)
         {
            if(CheckMaxExposure(InpComboLot))
            {
               double cost = 0;
               bool canExec = !InpUseStressLab || SimulateExecution("COMBO_RE", InpComboLot, cost);
               if(canExec && bothBull)
               {
                  if(g_tradeCombo.Buy(InpComboLot, g_activeSymbol, 0, 0, 0, "CO_RE_BUY"))
                  { g_comboTrades++; g_comboBuys++; g_comboReCount++;
                    g_comboBestPrice = SymbolInfoDouble(g_activeSymbol, SYMBOL_ASK);
                    InitTrailingCombo(true, g_comboBestPrice);
                    CLogger::Info("COMBO", StringFormat("RE BUY #%d/%d | $%.2f", g_comboReCount, InpComboReMax, cost)); }
               }
               else if(canExec && bothBear)
               {
                  if(g_tradeCombo.Sell(InpComboLot, g_activeSymbol, 0, 0, 0, "CO_RE_SELL"))
                  { g_comboTrades++; g_comboSells++; g_comboReCount++;
                    g_comboBestPrice = SymbolInfoDouble(g_activeSymbol, SYMBOL_BID);
                    InitTrailingCombo(false, g_comboBestPrice);
                    CLogger::Info("COMBO", StringFormat("RE SELL #%d/%d | $%.2f", g_comboReCount, InpComboReMax, cost)); }
               }
            }
         }
         buyCount  = CountPosByMagic(POSITION_TYPE_BUY,  magic);
         sellCount = CountPosByMagic(POSITION_TYPE_SELL, magic);
         totalPos  = buyCount + sellCount;
      }
   }

   //=== ENTRADA (somente via flip + countdown) ===
   if(totalPos > 0) return;
   if(g_comboFlipWait <= 0) return;                                    // Sem flip pendente

   g_comboFlipWait--;
   if(g_comboFlipWait > 0)
   {
      if(InpDebugMode)
         CLogger::Debug("COMBO", StringFormat("Entry delay: %d bricks restantes", g_comboFlipWait));
      return;
   }
   if(g_ce1Dir != g_comboFlipDir)
   { if(InpDebugMode) CLogger::Debug("COMBO", "Entry CANCELADA — direcao mudou"); return; }

   //--- Revalida ambos CEs mesma direcao (ignora flat se delay>0)
   bothBull = (g_ce1Dir == 1  && g_ce2Dir == 1);
   bothBear = (g_ce1Dir == -1 && g_ce2Dir == -1);
   if(!bothBull && !bothBear)
   { if(InpDebugMode) CLogger::Debug("COMBO", "Entry CANCELADA — CEs divergiram"); return; }

   //--- Flip detectado → IGNORA flat
   if(InpDebugMode)
      CLogger::Debug("COMBO", StringFormat("Entry via flip — %s (flat ignorado)",
         bothBull?"BULL":"BEAR"));

   if(!CheckSession()) { g_sessionBlocked++; return; }
   if(!CheckMaxExposure(InpComboLot)) return;

   double cost = 0;
   bool canExec = !InpUseStressLab || SimulateExecution(bothBull?"CO_BUY":"CO_SELL", InpComboLot, cost);
   if(!canExec) return;

   if(bothBull && buyCount == 0 && sellCount == 0)
   {
      if(g_tradeCombo.Buy(InpComboLot, g_activeSymbol, 0, 0, 0, "CO_BUY"))
      {
         g_comboTrades++; g_comboBuys++; g_comboStagnant = 0;
         g_comboBestPrice = SymbolInfoDouble(g_activeSymbol, SYMBOL_ASK);
         InitTrailingCombo(true, g_comboBestPrice);
         CLogger::Info("COMBO", StringFormat("BUY | lot=%.2f | $%.2f", InpComboLot, cost));
      }
   }
   else if(bothBear && sellCount == 0 && buyCount == 0)
   {
      if(g_tradeCombo.Sell(InpComboLot, g_activeSymbol, 0, 0, 0, "CO_SELL"))
      {
         g_comboTrades++; g_comboSells++; g_comboStagnant = 0;
         g_comboBestPrice = SymbolInfoDouble(g_activeSymbol, SYMBOL_BID);
         InitTrailingCombo(false, g_comboBestPrice);
         CLogger::Info("COMBO", StringFormat("SELL | lot=%.2f | $%.2f", InpComboLot, cost));
      }
   }
}

//--- Trailing 3F helpers para Combo ---

void InitTrailingCombo(bool isBuy, double entryPrice)
{
   if(!InpComboUseTrail) return;
   g_comboTsAvg   = entryPrice;
   g_comboTsDir   = isBuy ? 1 : -1;
   g_comboTsPhase = 1;
   g_comboTsBest  = entryPrice;
   if(InpDebugMode)
      CLogger::Debug("COMBO_TS", StringFormat("INIT %s @ %.2f", isBuy?"BUY":"SELL", entryPrice));
}

void ResetTrailingCombo()
{
   g_comboTsAvg = 0; g_comboTsDir = 0; g_comboTsPhase = 0; g_comboTsBest = 0;
}

bool ProcessTrailingCombo(int buyCount, int sellCount, double lastClose, int magic)
{
   if(g_comboTsPhase == 0) return false;

   if(g_comboTsDir == 1  && lastClose > g_comboTsBest) g_comboTsBest = lastClose;
   if(g_comboTsDir == -1 && lastClose < g_comboTsBest) g_comboTsBest = lastClose;

   double profitBricks  = MathAbs(g_comboTsBest - g_comboTsAvg) / g_brickSize;
   double retraceBricks = MathAbs(g_comboTsBest - lastClose) / g_brickSize;

   if(g_comboTsPhase == 1 && profitBricks >= InpComboTrailInit)
   { g_comboTsPhase = 2;
     CLogger::Info("COMBO_TS", StringFormat("F1→F2 BE | profit=%.1f bricks", profitBricks)); }
   if(g_comboTsPhase == 2 && profitBricks >= InpComboTrailInit + InpComboTrailTight)
   { g_comboTsPhase = 3;
     CLogger::Info("COMBO_TS", StringFormat("F2→F3 TIGHT | profit=%.1f bricks", profitBricks)); }

   bool shouldClose = false;
   if(g_comboTsPhase == 1 && retraceBricks >= InpComboTrailInit)
      shouldClose = true;
   else if(g_comboTsPhase == 2)
   { if(g_comboTsDir == 1 && lastClose <= g_comboTsAvg) shouldClose = true;
     if(g_comboTsDir == -1 && lastClose >= g_comboTsAvg) shouldClose = true; }
   else if(g_comboTsPhase == 3 && retraceBricks >= InpComboTrailTight)
      shouldClose = true;

   if(shouldClose)
   {
      ENUM_POSITION_TYPE closeType = (g_comboTsDir==1) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
      CloseByMagic(closeType, magic);
      if(InpUseStressLab) g_costCommission += InpCommissionExit;
      CLogger::Info("COMBO_TS", StringFormat("SAIDA F%d | best=%.2f cl=%.2f ret=%.1f",
         g_comboTsPhase, g_comboTsBest, lastClose, retraceBricks));
      ResetTrailingCombo();
      return true;
   }

   if(InpDebugMode)
      CLogger::Debug("COMBO_TS", StringFormat("F%d | best=%.2f cl=%.2f p=%.1f r=%.1f",
         g_comboTsPhase, g_comboTsBest, lastClose, profitBricks, retraceBricks));
   return false;
}

//=====================================================================
// SECAO 14: BOX — LATERAL CE2
//=====================================================================
//
// LOGICA (portada do CE-TEST, validada em backtest):
//   CE2 flat → linha CE2 = suporte (bull) ou resistencia (bear)
//   Preco faz pullback perto da linha → trigger
//   3 gatilhos: PROXIMO / TOCANDO / SOBRE (halfSteps do grid Renko)
//   3 filtros: tamanho / distancia / spread
//   Anti-hedge: ignora CE1, so verifica CE2/combo
//   Regime: LATERAL (se switch ON)
//
//=====================================================================

void ProcessBox(double lastClose, bool lastBull, datetime barTime)
{
   int magic = InpMagic + MAGIC_BOX;
   int boxBuys  = CountPosByMagic(POSITION_TYPE_BUY,  magic);
   int boxSells = CountPosByMagic(POSITION_TYPE_SELL, magic);
   int boxTotal = boxBuys + boxSells;

   //=== SAIDAS BOX ===
   if(boxTotal > 0)
   {
      //--- Saida dinamica: alvo = linha CE2 oposta
      if(InpBoxUseDynExit)
      {
         bool hitTarget = false;
         if(boxBuys > 0  && lastClose >= g_ce2Bear) hitTarget = true;  // BUY atingiu teto
         if(boxSells > 0 && lastClose <= g_ce2Bull) hitTarget = true;  // SELL atingiu piso

         if(hitTarget)
         {
            ENUM_POSITION_TYPE ct = boxBuys>0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
            CloseByMagic(ct, magic);
            if(InpUseStressLab) g_costCommission += InpCommissionExit;
            g_boxOppCount = 0; g_boxDynExits++;
            CLogger::Info("BOX", StringFormat("SAIDA DINAMICA | CE2 oposta | Cl=%.2f", lastClose));
            return;
         }
      }

      //--- Saida padrao: N bricks contrarios
      bool isOpp = (boxBuys>0 && !lastBull) || (boxSells>0 && lastBull);
      if(isOpp) g_boxOppCount++; else g_boxOppCount = 0;

      if(g_boxOppCount >= InpBoxExitBricks)
      {
         ENUM_POSITION_TYPE ct = boxBuys>0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         CloseByMagic(ct, magic);
         if(InpUseStressLab) g_costCommission += InpCommissionExit;
         g_boxOppCount = 0;
         CLogger::Info("BOX", StringFormat("SAIDA %d bricks contra", InpBoxExitBricks));
      }
      return;
   }

   //--- CE2 deve ter direcao
   if(g_ce2Dir == 0) return;

   //--- CE2 flipou → reseta tudo
   if(g_ce2Dir != g_ce2PrevDir && g_ce2PrevDir != 0)
   {
      g_boxTrigger = false; g_boxSide = 0;
      g_boxTouchCount = 0; g_boxMaxAway = 0; g_boxLastTouchLine = 0;
      if(InpDebugMode) CLogger::Debug("BOX", "CE2 flipou — reset completo");
   }

   //--- FILTRO: Tamanho do box
   if(InpBoxUseMinSize)
   {
      double boxSize = MathAbs(g_ce2Bear - g_ce2Bull);
      double minSize = InpBoxMinSize * (g_brickSize * 0.5);
      if(boxSize < minSize)
      {
         if(InpDebugMode)
            CLogger::Debug("BOX", StringFormat("FILTRO tamanho: %.2f (%.1f hs) < %.2f (%d hs)",
               boxSize, boxSize/(g_brickSize*0.5), minSize, InpBoxMinSize));
         g_boxSizeFiltered++;
         return;
      }
   }

   //--- Monitora distancia maxima
   double activeLine = (g_ce2Dir == 1.0) ? g_ce2Bull : g_ce2Bear;
   double distFromLine = MathAbs(lastClose - activeLine);
   if(distFromLine > g_boxMaxAway) g_boxMaxAway = distFromLine;

   //--- Detecta mudanca de linha → reseta toques
   if(activeLine != g_boxLastTouchLine && g_boxLastTouchLine != 0)
   {
      g_boxTouchCount = 0; g_boxMaxAway = distFromLine;
      if(InpDebugMode) CLogger::Debug("BOX", "Linha CE2 mudou — reset toques");
   }
   g_boxLastTouchLine = activeLine;

   //--- Deteccao de toque (grid Renko)
   double halfStep   = g_brickSize * 0.5;
   double nearLevel  = InpBoxNearSteps * halfStep;
   double crossLevel = InpBoxCrossSteps * halfStep;
   double tol        = g_brickSize * 0.03;

   if(g_ce2Dir == 1.0)                                                 // CE2 BULL → suporte
   {
      double support = g_ce2Bull;
      double dist = lastClose - support;

      if(InpDebugMode)
         CLogger::Debug("BOX", StringFormat("BULL sup=%.2f cl=%.2f d=%.2f hs=%.2f T#%d",
            support, lastClose, dist, halfStep, g_boxTouchCount));

      int touchType = 0;
      if(InpBoxTouchCross && dist <= -crossLevel + tol)                // SOBRE
         touchType = 3;
      else if(InpBoxTouchExact && MathAbs(dist) <= tol)                // TOCANDO
         touchType = 2;
      else if(InpBoxTouchNear && dist > tol && dist <= nearLevel + tol) // PROXIMO
         touchType = 1;

      if(touchType > 0 && !g_boxTrigger)
      {
         //--- Filtro distancia (UMA VEZ no trigger)
         if(InpBoxUseMinDist)
         {
            double minAway = InpBoxMinAway * halfStep;
            if(g_boxMaxAway < minAway)
            {
               g_boxDistFiltered++;
               if(InpDebugMode)
                  CLogger::Debug("BOX", StringFormat("FILTRO dist: %.2f < %.2f", g_boxMaxAway, minAway));
               g_boxMaxAway = 0; return;
            }
         }
         g_boxTrigger = true; g_boxSide = 1; g_boxTouchType = touchType;
         g_boxTriggers++; g_boxTouchCount++;
         if(touchType==1) g_boxTrigsNear++; if(touchType==2) g_boxTrigsExact++; if(touchType==3) g_boxTrigsCross++;
         string tStr = touchType==1?"PROXIMO":touchType==2?"TOCANDO":"SOBRE";
         CLogger::Info("BOX", StringFormat("TRIGGER BUY [%s] | Cl=%.2f Sup=%.2f d=%.2f (%.1f hs) | Away=%.2f | T#%d",
            tStr, lastClose, support, dist, dist/halfStep, g_boxMaxAway, g_boxTouchCount));
         g_boxMaxAway = 0;
      }
      else if(g_boxTrigger && g_boxSide == 1 && lastBull && dist > nearLevel * 2)
      { g_boxTrigger = false; if(InpDebugMode) CLogger::Debug("BOX", "Trigger reset — afastou"); }
   }
   else if(g_ce2Dir == -1.0)                                           // CE2 BEAR → resistencia
   {
      double resistance = g_ce2Bear;
      double dist = resistance - lastClose;

      if(InpDebugMode)
         CLogger::Debug("BOX", StringFormat("BEAR res=%.2f cl=%.2f d=%.2f hs=%.2f T#%d",
            resistance, lastClose, dist, halfStep, g_boxTouchCount));

      int touchType = 0;
      if(InpBoxTouchCross && dist <= -crossLevel + tol)
         touchType = 3;
      else if(InpBoxTouchExact && MathAbs(dist) <= tol)
         touchType = 2;
      else if(InpBoxTouchNear && dist > tol && dist <= nearLevel + tol)
         touchType = 1;

      if(touchType > 0 && !g_boxTrigger)
      {
         if(InpBoxUseMinDist)
         {
            double minAway = InpBoxMinAway * halfStep;
            if(g_boxMaxAway < minAway)
            {
               g_boxDistFiltered++;
               if(InpDebugMode)
                  CLogger::Debug("BOX", StringFormat("FILTRO dist: %.2f < %.2f", g_boxMaxAway, minAway));
               g_boxMaxAway = 0; return;
            }
         }
         g_boxTrigger = true; g_boxSide = -1; g_boxTouchType = touchType;
         g_boxTriggers++; g_boxTouchCount++;
         if(touchType==1) g_boxTrigsNear++; if(touchType==2) g_boxTrigsExact++; if(touchType==3) g_boxTrigsCross++;
         string tStr = touchType==1?"PROXIMO":touchType==2?"TOCANDO":"SOBRE";
         CLogger::Info("BOX", StringFormat("TRIGGER SELL [%s] | Cl=%.2f Res=%.2f d=%.2f (%.1f hs) | Away=%.2f | T#%d",
            tStr, lastClose, resistance, dist, dist/halfStep, g_boxMaxAway, g_boxTouchCount));
         g_boxMaxAway = 0;
      }
      else if(g_boxTrigger && g_boxSide == -1 && !lastBull && dist > nearLevel * 2)
      { g_boxTrigger = false; if(InpDebugMode) CLogger::Debug("BOX", "Trigger reset — afastou"); }
   }

   //=== FILTROS PRE-ENTRADA ===
   if(!g_boxTrigger) return;

   //--- Anti-hedge (ignora CE1, so CE2/combo)
   if(!CheckAntiHedge(g_boxSide)) { if(InpDebugMode) CLogger::Debug("BOX","Anti-hedge bloqueou"); return; }

   //--- Spread
   if(InpBoxUseSpread)
   {
      double ask = SymbolInfoDouble(g_activeSymbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(g_activeSymbol, SYMBOL_BID);
      double spNow = (ask>0 && bid>0) ? (ask-bid) : 0;
      double spPct = (g_brickSize>0) ? (spNow/g_brickSize)*100.0 : 0;
      if(spPct > InpBoxMaxSpreadPct)
      { g_boxSpreadFiltered++; if(InpDebugMode) CLogger::Debug("BOX",StringFormat("FILTRO spread %.1f%%",spPct)); return; }
   }

   //--- Sessao + exposicao
   if(!CheckSession()) return;
   if(!CheckMaxExposure(InpBoxLot)) return;

   //--- Confirmacao de entrada
   bool canEnterNow = (InpBoxEntry == 0);
   if(!canEnterNow)
   { if(g_boxSide==1 && lastBull) canEnterNow=true; if(g_boxSide==-1 && !lastBull) canEnterNow=true; }
   if(!canEnterNow) return;

   //--- StressLab
   double cost = 0;
   if(InpUseStressLab && !SimulateExecution(g_boxSide==1?"BOX_BUY":"BOX_SELL", InpBoxLot, cost)) return;

   //--- ENTRADA
   if(g_boxSide == 1)
   {
      if(g_tradeBox.Buy(InpBoxLot, g_activeSymbol, 0, 0, 0, "BOX_BUY"))
      {
         g_boxTrades++; g_boxBuys++;
         g_boxTrigger = false; g_boxOppCount = 0;
         g_boxEntryPrice = SymbolInfoDouble(g_activeSymbol, SYMBOL_ASK);
         CLogger::Info("BOX", StringFormat("BUY | lot=%.2f | T#%d | BoxSz=%.1f | $%.2f",
            InpBoxLot, g_boxTouchCount, MathAbs(g_ce2Bear-g_ce2Bull)/g_brickSize, cost));
      }
   }
   else if(g_boxSide == -1)
   {
      if(g_tradeBox.Sell(InpBoxLot, g_activeSymbol, 0, 0, 0, "BOX_SELL"))
      {
         g_boxTrades++; g_boxSells++;
         g_boxTrigger = false; g_boxOppCount = 0;
         g_boxEntryPrice = SymbolInfoDouble(g_activeSymbol, SYMBOL_BID);
         CLogger::Info("BOX", StringFormat("SELL | lot=%.2f | T#%d | BoxSz=%.1f | $%.2f",
            InpBoxLot, g_boxTouchCount, MathAbs(g_ce2Bear-g_ce2Bull)/g_brickSize, cost));
      }
   }
}

//=====================================================================
// SECAO 15: PYRAMID — PULLBACK THEN RESUME
//=====================================================================
//
// LOGICA:
//   Detecta pullback dentro de tendencia e adiciona posicao
//   Tipo 1: add no pullback (agressivo — pega o dip)
//   Tipo 2: add no proximo brick a favor (confirmacao — espera resume)
//
//   Exemplo BUY (Tipo 2, PullbackN=2):
//     BUY ativo → 2 bricks BEAR (pullback) → g_pyrReady = true
//     → proximo brick BULL (resume) → ADD BUY (lote × decay^nivel)
//
//   Aplica a CE2 solo e/ou CE1+CE2 combo (inputs)
//   NAO aplica a CE1 (CE1 tem pyramid momentum proprio)
//   NAO aplica a BOX
//   Requer CE inclinada para add
//
//=====================================================================

void ProcessPyramid(double lastClose, bool lastBull, datetime barTime)
{
   //=== PYRAMID CE2 ===
   if(InpPyrCE2)
   {
      int magic = InpMagic + MAGIC_CE2;
      int ce2Buys  = CountPosByMagic(POSITION_TYPE_BUY,  magic);
      int ce2Sells = CountPosByMagic(POSITION_TYPE_SELL, magic);
      int ce2Total = ce2Buys + ce2Sells;

      if(ce2Total > 0 && ce2Total < InpPyrMax && !g_ce2Flat)          // Tem posicao, abaixo do max, CE2 inclinada
      {
         bool isBuy = (ce2Buys > 0);
         bool oppBrick = (isBuy && !lastBull) || (!isBuy && lastBull); // Brick contra
         bool favBrick = (isBuy && lastBull)  || (!isBuy && !lastBull); // Brick a favor

         //--- Conta pullback
         if(oppBrick) g_pyrCE2PullCount++;
         else if(favBrick && g_pyrCE2PullCount > 0)
         {
            //--- Pullback suficiente → marca ready (Tipo 2) ou add direto (Tipo 1)
            if(g_pyrCE2PullCount >= InpPyrPullback) g_pyrCE2Ready = true;
            g_pyrCE2PullCount = 0;                                     // Brick a favor reseta pullback
         }

         //--- Tipo 1: add no pullback (quando atinge N bricks contra)
         if(InpPyrType == 1 && g_pyrCE2PullCount >= InpPyrPullback)
         {
            double lot = InpCE2Lot * MathPow(InpPyrDecay, ce2Total);
            if(lot < SymbolInfoDouble(g_activeSymbol, SYMBOL_VOLUME_MIN))
               lot = SymbolInfoDouble(g_activeSymbol, SYMBOL_VOLUME_MIN);

            if(CheckSession() && CheckMaxExposure(lot))
            {
               double cost = 0;
               bool canExec = !InpUseStressLab || SimulateExecution("PYR_CE2", lot, cost);
               if(canExec && isBuy && g_tradeCE2.Buy(lot, g_activeSymbol, 0, 0, 0, "PYR_CE2_BUY"))
               { g_pyrAdds++;
                 CLogger::Info("PYR", StringFormat("CE2 BUY #%d/%d | pullback=%d | lot=%.2f | $%.2f",
                    ce2Total+1, InpPyrMax, g_pyrCE2PullCount, lot, cost)); }
               else if(canExec && !isBuy && g_tradeCE2.Sell(lot, g_activeSymbol, 0, 0, 0, "PYR_CE2_SELL"))
               { g_pyrAdds++;
                 CLogger::Info("PYR", StringFormat("CE2 SELL #%d/%d | pullback=%d | lot=%.2f | $%.2f",
                    ce2Total+1, InpPyrMax, g_pyrCE2PullCount, lot, cost)); }
            }
            g_pyrCE2PullCount = 0; g_pyrCE2Ready = false;
         }

         //--- Tipo 2: add no proximo brick a favor (apos pullback)
         if(InpPyrType == 2 && g_pyrCE2Ready && favBrick)
         {
            double lot = InpCE2Lot * MathPow(InpPyrDecay, ce2Total);
            if(lot < SymbolInfoDouble(g_activeSymbol, SYMBOL_VOLUME_MIN))
               lot = SymbolInfoDouble(g_activeSymbol, SYMBOL_VOLUME_MIN);

            if(CheckSession() && CheckMaxExposure(lot))
            {
               double cost = 0;
               bool canExec = !InpUseStressLab || SimulateExecution("PYR_CE2", lot, cost);
               if(canExec && isBuy && g_tradeCE2.Buy(lot, g_activeSymbol, 0, 0, 0, "PYR_CE2_BUY"))
               { g_pyrAdds++;
                 CLogger::Info("PYR", StringFormat("CE2 BUY #%d/%d | resume | lot=%.2f | $%.2f",
                    ce2Total+1, InpPyrMax, lot, cost)); }
               else if(canExec && !isBuy && g_tradeCE2.Sell(lot, g_activeSymbol, 0, 0, 0, "PYR_CE2_SELL"))
               { g_pyrAdds++;
                 CLogger::Info("PYR", StringFormat("CE2 SELL #%d/%d | resume | lot=%.2f | $%.2f",
                    ce2Total+1, InpPyrMax, lot, cost)); }
            }
            g_pyrCE2Ready = false;
         }
      }
      else { g_pyrCE2PullCount = 0; g_pyrCE2Ready = false; }          // Sem posicao ou max atingido → reset
   }

   //=== PYRAMID COMBO ===
   if(InpPyrCombo)
   {
      int magic = InpMagic + MAGIC_COMBO;
      int coBuys  = CountPosByMagic(POSITION_TYPE_BUY,  magic);
      int coSells = CountPosByMagic(POSITION_TYPE_SELL, magic);
      int coTotal = coBuys + coSells;

      bool comboIncl = (!g_ce1Flat && !g_ce2Flat && g_ce1Dir == g_ce2Dir); // Ambos inclinados mesma dir

      if(coTotal > 0 && coTotal < InpPyrMax && comboIncl)
      {
         bool isBuy = (coBuys > 0);
         bool oppBrick = (isBuy && !lastBull) || (!isBuy && lastBull);
         bool favBrick = (isBuy && lastBull)  || (!isBuy && !lastBull);

         if(oppBrick) g_pyrComboPullCount++;
         else if(favBrick && g_pyrComboPullCount > 0)
         {
            if(g_pyrComboPullCount >= InpPyrPullback) g_pyrComboReady = true;
            g_pyrComboPullCount = 0;
         }

         //--- Tipo 1: add no pullback
         if(InpPyrType == 1 && g_pyrComboPullCount >= InpPyrPullback)
         {
            double lot = InpComboLot * MathPow(InpPyrDecay, coTotal);
            if(lot < SymbolInfoDouble(g_activeSymbol, SYMBOL_VOLUME_MIN))
               lot = SymbolInfoDouble(g_activeSymbol, SYMBOL_VOLUME_MIN);

            if(CheckSession() && CheckMaxExposure(lot))
            {
               double cost = 0;
               bool canExec = !InpUseStressLab || SimulateExecution("PYR_CO", lot, cost);
               if(canExec && isBuy && g_tradeCombo.Buy(lot, g_activeSymbol, 0, 0, 0, "PYR_CO_BUY"))
               { g_pyrAdds++;
                 CLogger::Info("PYR", StringFormat("COMBO BUY #%d/%d | pullback=%d | lot=%.2f | $%.2f",
                    coTotal+1, InpPyrMax, g_pyrComboPullCount, lot, cost)); }
               else if(canExec && !isBuy && g_tradeCombo.Sell(lot, g_activeSymbol, 0, 0, 0, "PYR_CO_SELL"))
               { g_pyrAdds++;
                 CLogger::Info("PYR", StringFormat("COMBO SELL #%d/%d | pullback=%d | lot=%.2f | $%.2f",
                    coTotal+1, InpPyrMax, g_pyrComboPullCount, lot, cost)); }
            }
            g_pyrComboPullCount = 0; g_pyrComboReady = false;
         }

         //--- Tipo 2: add no proximo brick a favor
         if(InpPyrType == 2 && g_pyrComboReady && favBrick)
         {
            double lot = InpComboLot * MathPow(InpPyrDecay, coTotal);
            if(lot < SymbolInfoDouble(g_activeSymbol, SYMBOL_VOLUME_MIN))
               lot = SymbolInfoDouble(g_activeSymbol, SYMBOL_VOLUME_MIN);

            if(CheckSession() && CheckMaxExposure(lot))
            {
               double cost = 0;
               bool canExec = !InpUseStressLab || SimulateExecution("PYR_CO", lot, cost);
               if(canExec && isBuy && g_tradeCombo.Buy(lot, g_activeSymbol, 0, 0, 0, "PYR_CO_BUY"))
               { g_pyrAdds++;
                 CLogger::Info("PYR", StringFormat("COMBO BUY #%d/%d | resume | lot=%.2f | $%.2f",
                    coTotal+1, InpPyrMax, lot, cost)); }
               else if(canExec && !isBuy && g_tradeCombo.Sell(lot, g_activeSymbol, 0, 0, 0, "PYR_CO_SELL"))
               { g_pyrAdds++;
                 CLogger::Info("PYR", StringFormat("COMBO SELL #%d/%d | resume | lot=%.2f | $%.2f",
                    coTotal+1, InpPyrMax, lot, cost)); }
            }
            g_pyrComboReady = false;
         }
      }
      else { g_pyrComboPullCount = 0; g_pyrComboReady = false; }
   }
}

//=====================================================================
// SECAO 16: VISUAL
//=====================================================================

void DrawCELines(datetime barTime)
{
   if(g_vizPrevTime==0) { g_vizPrevTime=barTime;
      g_viz1PrevBull=g_ce1Bull; g_viz1PrevBear=g_ce1Bear;
      g_viz2PrevBull=g_ce2Bull; g_viz2PrevBear=g_ce2Bear; return; }
   g_vizCount++;
   // CE1 — solida
   if(g_ce1Dir==1&&g_ce1Bull>0) { string n="CE1B_"+IntegerToString(g_vizCount);
      ObjectCreate(0,n,OBJ_TREND,0,g_vizPrevTime,g_viz1PrevBull,barTime,g_ce1Bull);
      ObjectSetInteger(0,n,OBJPROP_COLOR,InpCE1ColorBull);
      ObjectSetInteger(0,n,OBJPROP_WIDTH,InpCE1LineWidth);
      ObjectSetInteger(0,n,OBJPROP_STYLE,InpCE1LineStyle);
      ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,n,OBJPROP_BACK,true);
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); }
   if(g_ce1Dir==-1&&g_ce1Bear>0) { string n="CE1S_"+IntegerToString(g_vizCount);
      ObjectCreate(0,n,OBJ_TREND,0,g_vizPrevTime,g_viz1PrevBear,barTime,g_ce1Bear);
      ObjectSetInteger(0,n,OBJPROP_COLOR,InpCE1ColorBear);
      ObjectSetInteger(0,n,OBJPROP_WIDTH,InpCE1LineWidth);
      ObjectSetInteger(0,n,OBJPROP_STYLE,InpCE1LineStyle);
      ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,n,OBJPROP_BACK,true);
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); }
   // CE2 — pontilhada
   if(g_ce2Ready) {
      if(g_ce2Dir==1&&g_ce2Bull>0) { string n="CE2B_"+IntegerToString(g_vizCount);
         ObjectCreate(0,n,OBJ_TREND,0,g_vizPrevTime,g_viz2PrevBull,barTime,g_ce2Bull);
         ObjectSetInteger(0,n,OBJPROP_COLOR,InpCE2ColorBull);
         ObjectSetInteger(0,n,OBJPROP_WIDTH,InpCE2LineWidth);
         ObjectSetInteger(0,n,OBJPROP_STYLE,InpCE2LineStyle);
         ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);
         ObjectSetInteger(0,n,OBJPROP_BACK,true);
         ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); }
      if(g_ce2Dir==-1&&g_ce2Bear>0) { string n="CE2S_"+IntegerToString(g_vizCount);
         ObjectCreate(0,n,OBJ_TREND,0,g_vizPrevTime,g_viz2PrevBear,barTime,g_ce2Bear);
         ObjectSetInteger(0,n,OBJPROP_COLOR,InpCE2ColorBear);
         ObjectSetInteger(0,n,OBJPROP_WIDTH,InpCE2LineWidth);
         ObjectSetInteger(0,n,OBJPROP_STYLE,InpCE2LineStyle);
         ObjectSetInteger(0,n,OBJPROP_RAY_RIGHT,false);
         ObjectSetInteger(0,n,OBJPROP_BACK,true);
         ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false); } }
   g_vizPrevTime=barTime;
   g_viz1PrevBull=g_ce1Bull; g_viz1PrevBear=g_ce1Bear;
   g_viz2PrevBull=g_ce2Bull; g_viz2PrevBear=g_ce2Bear;
}

//=====================================================================
// SECAO 17: COMMENT
//=====================================================================

void UpdateComment()
{
   string regime = InpUseRegime ? (g_regimeTrend ? "TREND" : "LATERAL") : "OFF";
   int pCE1 = CountPosByMagic(POSITION_TYPE_BUY,InpMagic+MAGIC_CE1)+CountPosByMagic(POSITION_TYPE_SELL,InpMagic+MAGIC_CE1);
   int pCE2 = CountPosByMagic(POSITION_TYPE_BUY,InpMagic+MAGIC_CE2)+CountPosByMagic(POSITION_TYPE_SELL,InpMagic+MAGIC_CE2);
   int pCo  = CountPosByMagic(POSITION_TYPE_BUY,InpMagic+MAGIC_COMBO)+CountPosByMagic(POSITION_TYPE_SELL,InpMagic+MAGIC_COMBO);
   int pBox = CountPosByMagic(POSITION_TYPE_BUY,InpMagic+MAGIC_BOX)+CountPosByMagic(POSITION_TYPE_SELL,InpMagic+MAGIC_BOX);

   Comment(StringFormat(
      "CE-PRO V1.0 | Regime: %s | DD lock: %s\n"
      "CE1: %s %s (d=%.1f) | CE2: %s %s (d=%.1f)\n"
      "Pos: CE1=%d CE2=%d Co=%d BOX=%d | Exp=%.2f\n"
      "CE1: t=%d re=%d pyr=%d | CE2: t=%d re=%d ts=F%d\n"
      "Combo: t=%d re=%d ts=F%d stag=%d/%d\n"
      "Bricks: %d (B:%d S:%d)",
      regime, g_dailyLocked?"LOCKED":"OK",
      g_ce1Dir==1?"BULL":"BEAR", g_ce1Flat?"F":"I", g_ce1FlatDiff,
      g_ce2Dir==1?"BULL":"BEAR", g_ce2Flat?"F":"I", g_ce2FlatDiff,
      pCE1, pCE2, pCo, pBox, GetTotalExposure(),
      g_ce1Trades, g_ce1ReCount, g_ce1PyrAdds,
      g_ce2Trades, g_ce2ReCount, g_ce2TsPhase,
      g_comboTrades, g_comboReCount, g_comboTsPhase,
      g_comboStagnant, InpComboExitTimeout?InpComboTimeoutN:0,
      g_bricksTotal, g_bricksBull, g_bricksBear));
}

//=====================================================================
// SECAO 18: AUXILIARES
//=====================================================================

bool SelectPos(ulong ticket, ENUM_POSITION_TYPE type, int magic)
{
   if(ticket==0||!PositionSelectByTicket(ticket)) return false;
   if(PositionGetString(POSITION_SYMBOL)!=g_activeSymbol) return false;
   if(PositionGetInteger(POSITION_MAGIC)!=magic) return false;
   if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=type) return false;
   return true;
}

int CountPosByMagic(ENUM_POSITION_TYPE type, int magic)
{
   int c=0; for(int i=PositionsTotal()-1; i>=0; i--)
   { ulong t=PositionGetTicket(i); if(!SelectPos(t,type,magic)) continue; c++; }
   return c;
}

void CloseByMagic(ENUM_POSITION_TYPE type, int magic)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   { ulong t=PositionGetTicket(i); if(!SelectPos(t,type,magic)) continue;
     if(InpDebugMode) { double pnl=PositionGetDouble(POSITION_PROFIT);
       CLogger::Debug("CLOSE",StringFormat("M%d #%I64u P&L=$%.2f",magic-InpMagic,t,pnl)); }
     // Usa o CTrade correto por magic
     int offset = magic - InpMagic;
     if(offset==MAGIC_CE1)      g_tradeCE1.PositionClose(t);
     else if(offset==MAGIC_CE2) g_tradeCE2.PositionClose(t);
     else if(offset==MAGIC_COMBO) g_tradeCombo.PositionClose(t);
     else                       g_tradeBox.PositionClose(t);
   }
}

//=====================================================================
// SECAO 19: RELATORIOS
//=====================================================================

void PrintConfig()
{
   Print("═══════════════════════════════════════════");
   Print("          CE-PRO V1.0 — CONFIG            ");
   Print("═══════════════════════════════════════════");
   PrintFormat(" Symbol: %s | Brick: $%.2f | %s", g_csName, g_brickSize, g_isTester?"TESTER":"LIVE");
   PrintFormat(" CE1: %s Per=%d Mult=%.1f Lot=%.2f", InpUseCE1?"ON":"OFF", InpCE1Period, InpCE1Mult, InpCE1Lot);
   PrintFormat(" CE2: %s Per=%d Mult=%.1f Lot=%.2f", InpUseCE2?"ON":"OFF", InpCE2Period, InpCE2Mult, InpCE2Lot);
   PrintFormat(" Combo: %s Lot=%.2f Hier=%s", InpUseCombo?"ON":"OFF", InpComboLot, InpComboHierarchy?"ON":"OFF");
   PrintFormat(" BOX: %s Lot=%.2f Entry=%d Exit=%d", InpUseBox?"ON":"OFF", InpBoxLot, InpBoxEntry, InpBoxExitBricks);
   PrintFormat(" Regime: %s | Pyramid: %s (CE2=%s Co=%s)",
      InpUseRegime?"ON":"OFF", InpUsePyramid?"ON":"OFF", InpPyrCE2?"ON":"OFF", InpPyrCombo?"ON":"OFF");
   PrintFormat(" Risco: MaxExp=%s(%.2f) MaxDD=%s(%.1f%%) AntiHedge=%s",
      InpUseMaxExposure?"ON":"OFF", InpMaxExposure,
      InpUseMaxDD?"ON":"OFF", InpMaxDDPct,
      InpUseAntiHedge?"ON":"OFF");
   PrintFormat(" StressLab: %s | Magic: %d-%d", InpUseStressLab?"ON":"OFF", InpMagic, InpMagic+MAGIC_BOX);
   Print("═══════════════════════════════════════════");
}

void PrintFinalReport()
{
   long dur=(long)(TimeCurrent()-g_startTime);
   int dH=(int)(dur/3600),dM=(int)((dur%3600)/60),dS=(int)(dur%60);
   double tc=g_costSpread+g_costSlippage+g_costCommission+g_costSwap;
   Print("");
   Print("═══════════════════════════════════════════");
   Print("        CE-PRO V1.0 — RELATORIO FINAL     ");
   Print("═══════════════════════════════════════════");
   PrintFormat(" Duracao: %02d:%02d:%02d | Bricks: %d (B:%d S:%d)", dH,dM,dS, g_bricksTotal, g_bricksBull, g_bricksBear);
   Print("───────────────────────────────────────────");
   PrintFormat(" CE1 Solo:  Trades=%d (B:%d S:%d)", g_ce1Trades, g_ce1Buys, g_ce1Sells);
   PrintFormat(" CE2 Solo:  Trades=%d (B:%d S:%d)", g_ce2Trades, g_ce2Buys, g_ce2Sells);
   PrintFormat(" Combo:     Trades=%d (B:%d S:%d)", g_comboTrades, g_comboBuys, g_comboSells);
   PrintFormat(" BOX:       Trades=%d (B:%d S:%d) Triggers=%d", g_boxTrades, g_boxBuys, g_boxSells, g_boxTriggers);
   PrintFormat(" Pyramid:   Adds=%d", g_pyrAdds);
   Print("───────────────────────────────────────────");
   PrintFormat(" Bloqueios: Flat=%d Regime=%d Sessao=%d Hedge=%d Exp=%d",
      g_flatBlocked, g_regimeBlocked, g_sessionBlocked, g_hedgeBlocked, g_exposureBlocked);
   if(InpUseStressLab)
   { PrintFormat(" StressLab: Trades=%d Rej=%d Req=%d", g_statTrades, g_statRejections, g_statRequotes);
     PrintFormat(" Custos: Spread=$%.2f Slip=$%.2f Com=$%.2f Total=$%.2f", g_costSpread, g_costSlippage, g_costCommission, tc); }
   if(g_spreadSamples>0)
     PrintFormat(" Spread real: avg=%.0f min=%.0f max=%.0f", g_spreadSum/g_spreadSamples, g_spreadMin, g_spreadMax);
   Print("═══════════════════════════════════════════");
}
//+------------------------------------------------------------------+