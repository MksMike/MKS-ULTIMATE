//+------------------------------------------------------------------+
//| @file           : StressReplayer.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Experts / MKS-ULTIMATE
//| @responsibility : EA de estresse liga/desliga (ADR-038, fatia 3). Replaya
//|                   UM .mkstick alimentando N CMksStressRunner em paralelo
//|                   (um por nível None->Nightmare, numa ÚNICA passada pelo
//|                   arquivo) e, ao EOF, imprime a tabela comparativa
//|                   (MksStressLabPrintComparison) — o net por nível lado a
//|                   lado. Liga/desliga = None (off) vs Light..Nightmare (on).
//|                   Irmão do DecisionReplayer (que emite journal de decisão);
//|                   este mede a SOBREVIVÊNCIA da estratégia sob estresse
//|                   MODELADO. Reframe honesto (ADR-038 §5): mede degradação
//|                   sob stress sintético, NÃO fidelidade ao broker real —
//|                   "sobreviveu ao Nightmare" só ganha sentido após a
//|                   calibração (fatia à parte). Fora do Strategy Tester.
//| @depends_on     : Core/Data/CMksFileTickSource.mqh,
//|                   Core/Data/CMksTickFileReader.mqh,
//|                   Core/Symbol/CMksMt5Symbol.mqh,
//|                   Core/Log/CMksLogger.mqh,
//|                   Strategy/Runner/CMksStressRunner.mqh,
//|                   StressLab/CMksStressParams.mqh,
//|                   StressLab/CMksStressLabReport.mqh,
//|                   Core/Types/Tick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Experts/MKS-ULTIMATE/StressReplayer.mq5
//+------------------------------------------------------------------+
#property strict
#property copyright "MKS-ULTIMATE"
#property version   "1.00"

#include <MKS-ULTIMATE/Core/Data/CMksFileTickSource.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksTickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Symbol/CMksMt5Symbol.mqh>
#include <MKS-ULTIMATE/Core/Log/CMksLogger.mqh>
#include <MKS-ULTIMATE/Strategy/Runner/CMksStressRunner.mqh>
#include <MKS-ULTIMATE/StressLab/CMksStressParams.mqh>
#include <MKS-ULTIMATE/StressLab/CMksStressLabReport.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//--- Inputs --------------------------------------------------------
input group "=== Fonte de ticks ==="
input string InpTickFilePath  = "MKS-ULTIMATE\\Ticks\\XAUUSDm_CR_20260720T165526.mkstick"; // .mkstick a replayar

input group "=== Níveis de estresse (liga/desliga) ==="
input bool   InpRunNone       = true;  // baseline (desligado) — referência
input bool   InpRunLight      = true;
input bool   InpRunMedium     = true;
input bool   InpRunHigh       = true;
input bool   InpRunNightmare  = true;

input group "=== Brick (classic, ADR-026) ==="
input double InpBrickSize        = 3.0;    // mesmo valor do ColorReversal/golden
input int    InpInvalidTickLimit = 10;     // L (ADR-006)
input int    InpThresholdLimit   = 20;     // K (ADR-011)

input group "=== Estratégia (ColorReversal) ==="
input double InpSlBricks         = 10.0;   // SL em BRICKS (ADR-032; distância = InpSlBricks·InpBrickSize)
input long   InpMagic            = 527001;

input group "=== Sizing ==="
input string InpLotMode          = "FIXED"; // "FIXED" | "PERCENT"
input double InpFixedLots         = 0.01;
input double InpRiskPct           = 1.0;

input group "=== Conta sim + CostModel base ==="
input double InpStartBalance     = 10000.0;
input double InpSpreadPts         = 240.0;  // spread base do CostModel (pts). CALIBRADO Exness XAUUSDm (ADR-039): 240 pts = 0.24 USD (mediana de 417k ticks). CostModel aplica half (120/lado). Custom p/ outro símbolo.
input double InpSlipPts           = 0.0;    // slippage base do CostModel (pontos)
input double InpCommPerLot        = 0.0;    // comissão por lote (moeda)
input double InpBaselineSpreadPts = 240.0;  // base p/ o spread-stress compor (ADR-027 §7.2). CALIBRADO = 240 (mesmo spread real). Multiplicador do preset compõe: High 3× ≈ 720 ≈ max real (700). 0 = spread-stress inerte.

input group "=== Piso de SL (E0.3/M12) ==="
input int    InpMinSlBricks      = 1;
input double InpMinSlFloorPts     = 0.0;

input group "=== Risco por estratégia / conta ==="
input int    InpMaxOpenPositions = 1;
input double InpMaxDailyLossPct   = 0.0;    // 0 = sem limite
input double InpMaxDrawdownPct    = 0.0;    // 0 = sem limite
input double InpMinEquityAbs      = 0.0;    // 0 = sem circuit breaker

input group "=== Output / Performance ==="
input bool   InpLogToFile        = true;
input int    InpTimerMs          = 1;
input int    InpTicksPerCycle    = 10000;

//--- Estado global -------------------------------------------------
ISymbol            *g_iSymbol      = NULL;
CMksFileTickSource *g_source       = NULL;
CMksLogger         *g_logger       = NULL;
CMksStressRunner   *g_runners[];    // um por nível habilitado (ownership)
string              g_levelNames[]; // paralelo a g_runners

string  g_sourceSymbol  = "";
string  g_sourceBroker  = "";
long    g_sourceAccount = 0;
int     g_sourceDigits  = 0;
string  g_logPath       = "";

bool    g_eof           = false;
long    g_ticksConsumed = 0;
ulong   g_startMs       = 0;
bool    g_finished      = false;

//+------------------------------------------------------------------+
//| Lê proveniência do .mkstick (header-only).                        |
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
//| Acrescenta um nível (params + nome) às listas paralelas.          |
//+------------------------------------------------------------------+
void AddLevel(CMksStressParams &params[], string &names[], int &n,
              const CMksStressParams &p, const string nm)
{
   ArrayResize(params, n + 1);
   ArrayResize(names,  n + 1);
   params[n] = p;
   names[n]  = nm;
   n++;
}

//+------------------------------------------------------------------+
//| Cleanup global ordenado. Cada runner é dono do próprio grafo.     |
//+------------------------------------------------------------------+
void Cleanup()
{
   for(int i = 0; i < ArraySize(g_runners); i++)
      if(g_runners[i] != NULL) { delete g_runners[i]; g_runners[i] = NULL; }
   ArrayResize(g_runners, 0);
   ArrayResize(g_levelNames, 0);

   if(g_source  != NULL) { delete g_source;  g_source  = NULL; }
   if(g_logger  != NULL) { delete g_logger;  g_logger  = NULL; }
   if(g_iSymbol != NULL) { delete g_iSymbol; g_iSymbol = NULL; }
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_startMs = GetTickCount();

   if(StringLen(InpTickFilePath) == 0)
   {
      Print("StressReplayer: InpTickFilePath vazio");
      return INIT_PARAMETERS_INCORRECT;
   }

   // 1. Proveniência do .mkstick.
   MksError err;
   if(!ReadFirstFileProvenance(InpTickFilePath, g_sourceBroker, g_sourceAccount,
                               g_sourceSymbol, g_sourceDigits, err))
   {
      PrintFormat("StressReplayer: proveniência de '%s' falhou: %s",
                  InpTickFilePath, err.ToString());
      return INIT_FAILED;
   }

   // 2. Símbolo real (fornece Point/TickSize/TickValue à conta sim e ao sizer).
   bool symbolSelected = SymbolSelect(g_sourceSymbol, true);
   g_iSymbol = new CMksMt5Symbol(g_sourceSymbol);

   FolderCreate("MKS-ULTIMATE");
   FolderCreate("MKS-ULTIMATE\\Logs");

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   string stamp = StringFormat("%04d%02d%02dT%02d%02d%02d",
                               dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);

   // 3. Logger.
   g_logger = new CMksLogger();
   g_logPath = StringFormat("MKS-ULTIMATE\\Logs\\StressReplayer_%s_%s.log",
                            g_sourceSymbol, stamp);
   if(!g_logger.Open(g_logPath, MKS_LOG_INFO, true, InpLogToFile, err))
   {
      PrintFormat("StressReplayer: logger.Open falhou: %s", err.ToString());
      Cleanup();
      return INIT_FAILED;
   }
   g_logger.WriteHeader(g_sourceBroker, g_sourceAccount, g_sourceSymbol,
                        g_sourceDigits, "StressReplayer", (long)now * 1000);

   // 4. Numéricos do símbolo são LOAD-BEARING (sizer, piso de SL, conta, PnL).
   //    Símbolo indisponível (ex.: .mkstick de outra corretora) → point/tick=0
   //    → sizing/risco/PnL degenerados e silenciosos. Falha na causa-raiz.
   if(g_iSymbol.Point() <= 0.0 || g_iSymbol.TickSize() <= 0.0 ||
      g_iSymbol.TickValue() <= 0.0)
   {
      string smsg = StringFormat(
         "símbolo '%s' sem numéricos usáveis (point=%.6f tickSize=%.6f "
         "tickValue=%.6f, selected=%s). O terminal tem esse símbolo disponível?",
         g_sourceSymbol, g_iSymbol.Point(), g_iSymbol.TickSize(),
         g_iSymbol.TickValue(), (symbolSelected ? "true" : "false"));
      g_logger.Error("StressReplayer", "symbol numerics unusable",
         StringFormat("\"msg\":\"%s\"", MksJsonEscape(smsg)));
      Alert("StressReplayer: " + smsg);
      Cleanup();
      return INIT_FAILED;
   }

   // 5. Source (single-file).
   g_source = new CMksFileTickSource(InpTickFilePath, g_sourceBroker,
                                     g_sourceAccount, g_sourceSymbol);
   if(!g_source.Open(err))
   {
      g_logger.Error("StressReplayer", "source open failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_FAILED;
   }

   // 6. Config compartilhado por todos os níveis (o que varia é o preset).
   double slPoints = InpSlBricks * (InpBrickSize / g_iSymbol.Point());
   MksStressRunnerConfig cfg;
   cfg.brickSize            = InpBrickSize;
   cfg.invalidLimit         = InpInvalidTickLimit;
   cfg.thresholdLimit       = InpThresholdLimit;
   cfg.spreadPoints         = InpSpreadPts;
   cfg.slippagePoints       = InpSlipPts;
   cfg.commissionPerLot     = InpCommPerLot;
   cfg.baselineSpreadPoints = InpBaselineSpreadPts;
   cfg.startBalance         = InpStartBalance;
   cfg.applySwap            = false;
   cfg.slPoints             = slPoints;
   cfg.magic                = InpMagic;
   cfg.lotMode              = InpLotMode;
   cfg.fixedLots            = InpFixedLots;
   cfg.riskPct              = InpRiskPct;
   cfg.requireSl            = true;
   cfg.maxLotsPerTrade      = 0.0;
   cfg.minSlFloorPts        = InpMinSlFloorPts;
   cfg.minSlBricks          = InpMinSlBricks;
   cfg.maxOpenPositions     = InpMaxOpenPositions;
   cfg.maxTotalLots         = 0.0;
   cfg.maxDailyLossPct      = InpMaxDailyLossPct;
   cfg.maxDrawdownPct       = InpMaxDrawdownPct;
   cfg.minEquityAbs         = InpMinEquityAbs;

   // 7. Lista de níveis habilitados (None sempre primeiro se ligado = baseline).
   CMksStressParams lvlParams[];
   string           lvlNames[];
   int              nLevels = 0;
   if(InpRunNone)      AddLevel(lvlParams, lvlNames, nLevels, MksStressNone(),      "None");
   if(InpRunLight)     AddLevel(lvlParams, lvlNames, nLevels, MksStressLight(),     "Light");
   if(InpRunMedium)    AddLevel(lvlParams, lvlNames, nLevels, MksStressMedium(),    "Medium");
   if(InpRunHigh)      AddLevel(lvlParams, lvlNames, nLevels, MksStressHigh(),      "High");
   if(InpRunNightmare) AddLevel(lvlParams, lvlNames, nLevels, MksStressNightmare(), "Nightmare");

   if(nLevels == 0)
   {
      g_logger.Error("StressReplayer", "nenhum nível habilitado",
         "\"msg\":\"ligue ao menos um InpRun*\"");
      Alert("StressReplayer: nenhum nível de estresse habilitado (ligue ao menos um).");
      Cleanup();
      return INIT_PARAMETERS_INCORRECT;
   }

   // 8. Um runner por nível — grafo independente, alimentado em paralelo.
   ArrayResize(g_runners, nLevels);
   ArrayResize(g_levelNames, nLevels);
   for(int k = 0; k < nLevels; k++)
   {
      g_runners[k]    = new CMksStressRunner(g_iSymbol, cfg, lvlParams[k],
                                             lvlNames[k], g_logger);
      g_levelNames[k] = lvlNames[k];
      if(!g_runners[k].Init(err))
      {
         g_logger.Error("StressReplayer", "runner init failed",
            StringFormat("\"level\":\"%s\",\"err\":\"%s\"",
                         lvlNames[k], MksJsonEscape(err.ToString())));
         Cleanup();
         return INIT_FAILED;
      }
   }

   g_logger.Info("StressReplayer", "starting",
      StringFormat("\"path\":\"%s\",\"symbol\":\"%s\",\"tickCount\":%I64d,"
                   "\"levels\":%d,\"S\":%.5f,\"slBricks\":%.2f,\"slPoints\":%.2f,"
                   "\"baselineSpreadPts\":%.2f,\"startBalance\":%.2f",
                   MksJsonEscape(InpTickFilePath), g_sourceSymbol,
                   g_source.TickCount(), nLevels, InpBrickSize, InpSlBricks,
                   slPoints, InpBaselineSpreadPts, InpStartBalance));
   if(InpBaselineSpreadPts <= 0.0)
      g_logger.Info("StressReplayer", "spread-stress inerte",
         "\"msg\":\"InpBaselineSpreadPts=0 → o eixo de spread não estressa; degradação vem de slippage/requote/rejeição. Calibrar ao broker real é fatia à parte (ADR-038).\"");

   // 9. Timer.
   int timerMs = (InpTimerMs > 0) ? InpTimerMs : 1;
   EventSetMillisecondTimer(timerMs);

   g_logger.Info("StressReplayer", "OnInit done — replay via OnTimer",
      StringFormat("\"timerMs\":%d,\"ticksPerCycle\":%d", timerMs, InpTicksPerCycle));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Processa N ticks por chamada, alimentando TODOS os runners com o  |
//| mesmo tick (uma passada pelo arquivo). true = EOF.                |
//+------------------------------------------------------------------+
bool ProcessBatch()
{
   if(g_eof) return true;

   int processed = 0;
   int nRunners = ArraySize(g_runners);
   MksTick t;
   while(processed < InpTicksPerCycle)
   {
      if(!g_source.Next(t))
      {
         g_eof = true;
         return true;
      }
      g_ticksConsumed++;
      for(int k = 0; k < nRunners; k++)
         g_runners[k].OnTick(t);
      processed++;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Termina: captura o report de cada nível, imprime a comparação e   |
//| loga o summary por nível. Idempotente.                            |
//+------------------------------------------------------------------+
void FinishReplay()
{
   EventKillTimer();
   if(g_finished) { ExpertRemove(); return; }
   g_finished = true;

   int n = ArraySize(g_runners);
   CMksStressLabReport reports[];
   ArrayResize(reports, n);
   for(int k = 0; k < n; k++)
      reports[k] = g_runners[k].Report();

   // Tabela comparativa (Print direto — vai para a aba Experts).
   MksStressLabPrintComparison(reports);

   ulong elapsedMs = GetTickCount() - g_startMs;
   double ticksPerSec = (elapsedMs > 0) ? (double)g_ticksConsumed * 1000.0 / elapsedMs : 0.0;

   if(g_logger != NULL)
   {
      for(int k = 0; k < n; k++)
      {
         CMksColorReversalMetrics m = g_runners[k].StrategyMetrics();
         g_logger.Info("StressReplayer", "level summary",
            StringFormat("\"level\":\"%s\",\"bricksSeen\":%I64d,\"flips\":%I64d,"
                         "\"tradesClosed\":%d,\"netPnLPoints\":%.1f,"
                         "\"slippageTotalPoints\":%.1f,\"balance\":%.2f,"
                         "\"equity\":%.2f,\"openAtEnd\":%d",
                         g_levelNames[k], g_runners[k].BricksSeen(),
                         m.flipsDetected, reports[k].tradesClosed,
                         reports[k].netPnLPoints, reports[k].slippageTotalPoints,
                         g_runners[k].Balance(), g_runners[k].Equity(),
                         g_runners[k].OpenPositions()));
      }
      g_logger.Info("StressReplayer", "replay summary",
         StringFormat("\"eof\":%s,\"ticksConsumed\":%I64d,\"levels\":%d,"
                      "\"elapsedMs\":%I64u,\"ticksPerSec\":%.0f,\"logPath\":\"%s\"",
                      (g_eof ? "true" : "false"), g_ticksConsumed, n,
                      elapsedMs, ticksPerSec, MksJsonEscape(g_logPath)));
      g_logger.Close();
   }

   ExpertRemove();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_eof) return;
   if(ProcessBatch()) FinishReplay();
}

//+------------------------------------------------------------------+
//| OnTick: StressReplayer NÃO consome ticks live — o feed é o        |
//| .mkstick. Vazio de propósito; o motor roda em OnTimer.            |
//+------------------------------------------------------------------+
void OnTick() {}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(!g_finished && g_logger != NULL)
      g_logger.Info("StressReplayer", "deinit before EOF",
         StringFormat("\"reason\":%d,\"ticksConsumed\":%I64d", reason, g_ticksConsumed));
   Cleanup();
}
//+------------------------------------------------------------------+
