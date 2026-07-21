//+------------------------------------------------------------------+
//| @file           : CMksStressRunner.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Strategy / Runner
//| @responsibility : Runner de estresse de UM nível (ADR-038, fatia 2).
//|                   Monta o grafo
//|                     feed -> CMksRenkoBuilder -> CMksColorReversalStrategy
//|                       -> CMksTradeJournalingBroker -> CMksRiskGatedBroker
//|                       -> CMksStressLabBroker -> CMksSimulatedBroker
//|                       (+CMksSimAccount, book, FeedClock, snapshot,
//|                        CMksTradeJournal)
//|                   e dirige a MESMA ordem-por-tick do CMksDecisionRunner —
//|                   só que o auto-close de SL/TP é drenado do STRESS broker
//|                   (slip adverso aplicado). Ao fim, Report() captura um
//|                   CMksStressLabReport (métricas REAIS do broker + PnL do
//|                   journal). O EA loopa níveis (None->Nightmare) criando um
//|                   runner por nível e agrega os reports.
//|                   Acoplado ao CMksColorReversalStrategy (Fase 9, INTOCADA)
//|                   — reside em Strategy/, não Core/.
//| @depends_on     : Core/Broker/CMksSimulatedBroker.mqh + CMksCostModel,
//|                   Core/Account/CMksSimAccount + CMksAccountSnapshot,
//|                   Core/Position/CMksSimPositionBook.mqh,
//|                   Core/Clock/CMksFeedClock.mqh,
//|                   Core/RenkoBuilder/CMksRenkoBuilder + CMksFixedBrickSizer,
//|                   Core/Trade/CMksFixedLotSizer + CMksPercentRiskSizer +
//|                     CMksTradeJournal + CMksTradeJournalingBroker,
//|                   Core/Risk/CMksRiskManager + CMksRiskGatedBroker,
//|                   Core/Output/CMksMultiSink.mqh,
//|                   StressLab/CMksStressParams + CMksStressLabBroker +
//|                     CMksStressLabReport,
//|                   Strategy/CMksColorReversalStrategy.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Strategy/Runner/CMksStressRunner.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_STRATEGY_RUNNER_CMKSSTRESSRUNNER_MQH
#define MKS_ULTIMATE_STRATEGY_RUNNER_CMKSSTRESSRUNNER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ILogger.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IPositionSizer.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksCostModel.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksSimulatedBroker.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksSimAccount.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksAccountSnapshot.mqh>
#include <MKS-ULTIMATE/Core/Position/CMksSimPositionBook.mqh>
#include <MKS-ULTIMATE/Core/Clock/CMksFeedClock.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksRenkoBuilder.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksFixedBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksFixedLotSizer.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksPercentRiskSizer.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksTradeJournal.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksTradeJournalingBroker.mqh>
#include <MKS-ULTIMATE/Core/Risk/CMksRiskManager.mqh>
#include <MKS-ULTIMATE/Core/Risk/CMksRiskGatedBroker.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksMultiSink.mqh>
#include <MKS-ULTIMATE/StressLab/CMksStressParams.mqh>
#include <MKS-ULTIMATE/StressLab/CMksStressLabBroker.mqh>
#include <MKS-ULTIMATE/StressLab/CMksStressLabReport.mqh>
#include <MKS-ULTIMATE/Strategy/CMksColorReversalStrategy.mqh>

//+------------------------------------------------------------------+
//| Config fixa de uma corrida de estresse (compartilhada por todos  |
//| os níveis; o que varia entre níveis é o CMksStressParams). Sem   |
//| campos de journal-de-arquivo — o trade journal é in-memory.      |
//| Defaults sãos p/ XAU classic (brick 3.0, SL >= 1 brick).         |
//+------------------------------------------------------------------+
struct MksStressRunnerConfig
{
   //--- Brick (classic, ADR-026)
   double brickSize;
   int    invalidLimit;    // L (ADR-006)
   int    thresholdLimit;  // K (ADR-011)
   int    kRecoverAfter;

   //--- CostModel base (o StressLabBroker compõe adversidade POR CIMA)
   double spreadPoints;
   double slippagePoints;
   double commissionPerLot;
   // Base p/ o spread-stress compor (ADR-027 §7.2). 0 = spread-stress
   // inerte — CALIBRADO XAU = 240 pts (ADR-039).
   double baselineSpreadPoints;
   // Drift adverso de latência: pts somados ao fill por ms de latência
   // sorteada (slip = latencyMs · este; ADR-027 §7.1 / ADR-039). Compõe com
   // o latencyMeanMs do preset. 0 = latência-stress inerte. CALIBRADO XAU
   // ~0.25 (adverso, deslocamento líquido @ ~260ms). Linear superestima em
   // L alto (aceitável em Nightmare).
   double latencyDriftPointsPerMs;

   //--- Conta sim
   double startBalance;
   bool   applySwap;       // v1: false

   //--- Estratégia
   double slPoints;
   long   magic;

   //--- Sizing
   string lotMode;         // "FIXED" | "PERCENT"
   double fixedLots;
   double riskPct;

   //--- Risco: por trade
   bool   requireSl;
   double maxLotsPerTrade;
   double minSlFloorPts;
   int    minSlBricks;

   //--- Risco: por estratégia
   int    maxOpenPositions;
   double maxTotalLots;

   //--- Risco: por conta
   double maxDailyLossPct;
   double maxDrawdownPct;
   double minEquityAbs;

   MksStressRunnerConfig()
   {
      brickSize            = 3.0;
      invalidLimit         = 10;
      thresholdLimit       = 20;
      kRecoverAfter        = 5;

      spreadPoints         = 0.0;
      slippagePoints       = 0.0;
      commissionPerLot     = 0.0;
      baselineSpreadPoints = 0.0;
      latencyDriftPointsPerMs = 0.0;

      startBalance         = 10000.0;
      applySwap            = false;

      slPoints             = 3000.0;
      magic                = 527001;

      lotMode              = "FIXED";
      fixedLots            = 0.01;
      riskPct              = 1.0;

      requireSl            = true;
      maxLotsPerTrade      = 0.0;
      minSlFloorPts        = 0.0;
      minSlBricks          = 1;

      maxOpenPositions     = 1;
      maxTotalLots         = 0.0;

      maxDailyLossPct      = 0.0;
      maxDrawdownPct       = 0.0;
      minEquityAbs         = 0.0;
   }
};

//+------------------------------------------------------------------+
//| CMksStressRunner — dono do grafo de UM nível de estresse.        |
//| Uso:                                                             |
//|   CMksStressRunner run(GetPointer(sym), cfg, MksStressHigh(),    |
//|                        "High", GetPointer(log));                 |
//|   MksError err;                                                  |
//|   if(!run.Init(err)) { ...trata... }                            |
//|   ... por cada tick do feed:  run.OnTick(t);                     |
//|   CMksStressLabReport r = run.Report();                          |
//+------------------------------------------------------------------+
class CMksStressRunner
{
private:
   //--- Injetados (não possuídos)
   ISymbol *m_symbol;
   ILogger *m_logger;
   MksStressRunnerConfig m_cfg;
   CMksStressParams      m_stressParams;  // cópia (baselineSpread ajustado no Init)
   string                m_levelName;

   //--- Possuídos (grafo)
   MksRenkoGeometry           m_geom;
   CMksCostModel             *m_costModel;
   CMksSimulatedBroker       *m_simBroker;
   CMksStressLabBroker       *m_stressBroker;
   CMksSimAccount            *m_account;
   CMksSimPositionBook       *m_book;
   CMksFeedClock             *m_clock;
   CMksAccountSnapshot       *m_snapshot;
   CMksFixedBrickSizer       *m_brickSizer;
   IPositionSizer            *m_posSizer;
   CMksRiskManager           *m_risk;
   CMksRiskGatedBroker       *m_gatedBroker;
   CMksTradeJournal          *m_journal;
   CMksTradeJournalingBroker *m_journalBroker;
   CMksColorReversalStrategy *m_strategy;
   CMksMultiSink             *m_multiSink;
   CMksRenkoBuilder          *m_builder;

   //--- Estado / observabilidade
   bool m_initialized;
   long m_ticksFed;
   long m_ticksInvalid;
   bool m_halted;

   //--- Buffer reusado para drenar auto-closes
   MksSimAutoCloseEvent m_evBuf[];

   void NullAll()
   {
      m_costModel     = NULL;
      m_simBroker     = NULL;
      m_stressBroker  = NULL;
      m_account       = NULL;
      m_book          = NULL;
      m_clock         = NULL;
      m_snapshot      = NULL;
      m_brickSizer    = NULL;
      m_posSizer      = NULL;
      m_risk          = NULL;
      m_gatedBroker   = NULL;
      m_journal       = NULL;
      m_journalBroker = NULL;
      m_strategy      = NULL;
      m_multiSink     = NULL;
      m_builder       = NULL;
   }

   // Destrói o grafo em ordem reversa da construção. Idempotente.
   // Não toca em symbol/logger (injetados).
   void Teardown()
   {
      if(m_builder      != NULL) { delete m_builder;       m_builder       = NULL; }
      if(m_multiSink    != NULL) { delete m_multiSink;     m_multiSink     = NULL; }
      if(m_strategy     != NULL) { delete m_strategy;      m_strategy      = NULL; }
      if(m_journalBroker!= NULL) { delete m_journalBroker; m_journalBroker = NULL; }
      if(m_journal      != NULL) { delete m_journal;       m_journal       = NULL; }
      if(m_gatedBroker  != NULL) { delete m_gatedBroker;   m_gatedBroker   = NULL; }
      if(m_risk         != NULL) { delete m_risk;          m_risk          = NULL; }
      if(m_posSizer     != NULL) { delete m_posSizer;      m_posSizer      = NULL; }
      if(m_brickSizer   != NULL) { delete m_brickSizer;    m_brickSizer    = NULL; }
      if(m_snapshot     != NULL) { delete m_snapshot;      m_snapshot      = NULL; }
      if(m_clock        != NULL) { delete m_clock;         m_clock         = NULL; }
      if(m_book         != NULL) { delete m_book;          m_book          = NULL; }
      if(m_account      != NULL) { delete m_account;       m_account       = NULL; }
      if(m_stressBroker != NULL) { delete m_stressBroker;  m_stressBroker  = NULL; }
      if(m_simBroker    != NULL) { delete m_simBroker;     m_simBroker     = NULL; }
      if(m_costModel    != NULL) { delete m_costModel;     m_costModel     = NULL; }
   }

   // Drena os auto-closes de SL/TP que o STRESS broker enfileirou (com slip
   // adverso já aplicado — por isso drena do stress, não do sim). Journal +
   // conta. O TradeJournalingBroker cuida de Send/Close explícitos; aqui só
   // o auto-close — cada posição fecha uma vez, sem dupla contagem.
   void DrainAutoCloses()
   {
      int n = m_stressBroker.PollAutoCloses(m_evBuf);
      for(int i = 0; i < n; i++)
      {
         m_journal.RecordClose(m_evBuf[i].positionId, m_evBuf[i].closePrice,
                               m_evBuf[i].closeTimeMsc, m_evBuf[i].commissionClose);
         if(m_account != NULL)
            m_account.OnClose(m_evBuf[i].positionId, m_evBuf[i].closePrice,
                              m_evBuf[i].commissionClose);
      }
   }

public:
   CMksStressRunner(ISymbol *symbol, const MksStressRunnerConfig &cfg,
                    const CMksStressParams &stressParams, const string &levelName,
                    ILogger *logger = NULL)
   {
      m_symbol       = symbol;
      m_logger       = logger;
      m_cfg          = cfg;
      m_stressParams = stressParams;
      m_levelName    = levelName;

      m_initialized  = false;
      m_ticksFed     = 0;
      m_ticksInvalid = 0;
      m_halted       = false;

      NullAll();
   }

   ~CMksStressRunner()
   {
      Teardown();
   }

   // Monta o grafo, valida cada peça. false + err em qualquer falha (grafo
   // desmontado antes de retornar — sem leak).
   bool Init(MksError &err)
   {
      if(m_initialized)
      {
         MKS_SET_ERROR(err, MKS_ERR_CORE_INVALID_ARGUMENT,
                       "stress runner já inicializado (Init duas vezes)", "");
         return false;
      }
      if(m_symbol == NULL)
      {
         MKS_SET_ERROR(err, MKS_ERR_CORE_INVALID_ARGUMENT,
                       "symbol nulo no stress runner", "");
         return false;
      }

      m_geom = MksGeometryClassic();
      if(!m_geom.Validate(err)) { Teardown(); return false; }

      // CostModel base + simulador (backstop de piso OFF — o gate é autoritativo).
      m_costModel = new CMksCostModel(m_cfg.spreadPoints, m_cfg.slippagePoints,
                                      m_cfg.commissionPerLot);
      if(!m_costModel.Validate(err)) { Teardown(); return false; }
      m_simBroker = new CMksSimulatedBroker(m_symbol, m_costModel, 0.0);

      // Ancoragem de custo ao broker real (ADR-039): spread-stress compõe
      // sobre a base do CostModel; drift adverso de latência por ms.
      m_stressParams.baselineSpreadPoints    = m_cfg.baselineSpreadPoints;
      m_stressParams.latencyDriftPointsPerMs = m_cfg.latencyDriftPointsPerMs;
      // StressLabBroker envolve o sim; exitSim = o MESMO sim (adversidade de
      // saída/auto-close). underlying e exitSim apontam para o mesmo objeto.
      m_stressBroker = new CMksStressLabBroker(m_simBroker, m_symbol,
                                               m_stressParams, m_simBroker);

      // Conta sim + book + clock do feed + snapshot temporal.
      m_account  = new CMksSimAccount(m_symbol, m_cfg.startBalance, m_cfg.applySwap);
      m_book     = new CMksSimPositionBook(m_simBroker);
      m_clock    = new CMksFeedClock();
      m_snapshot = new CMksAccountSnapshot(m_account, m_clock);

      m_brickSizer = new CMksFixedBrickSizer(m_cfg.brickSize);
      if(!m_brickSizer.Validate(err)) { Teardown(); return false; }

      if(m_cfg.lotMode == "PERCENT")
         m_posSizer = new CMksPercentRiskSizer(m_symbol, m_account, m_cfg.riskPct);
      else
         m_posSizer = new CMksFixedLotSizer(m_symbol, m_cfg.fixedLots);
      if(!m_posSizer.Validate(err)) { Teardown(); return false; }

      // RiskManager (3 camadas). Gate envolve o STRESS broker.
      CMksRiskTradeParams tp;
      tp.requireSl       = m_cfg.requireSl;
      tp.requireTp       = false;
      tp.maxLotsPerTrade = m_cfg.maxLotsPerTrade;
      tp.minSlPoints     = m_cfg.minSlFloorPts;
      CMksRiskStrategyParams sp;
      sp.maxOpenPositions = m_cfg.maxOpenPositions;
      sp.maxTotalLots     = m_cfg.maxTotalLots;
      CMksRiskAccountParams ap;
      ap.maxDailyLossPct = m_cfg.maxDailyLossPct;
      ap.maxDrawdownPct  = m_cfg.maxDrawdownPct;
      ap.minEquityAbs    = m_cfg.minEquityAbs;

      m_risk = new CMksRiskManager(tp, sp, ap, m_book, m_snapshot, m_posSizer, m_logger);
      m_risk.SetSlFloorSource(m_brickSizer, m_symbol, m_cfg.minSlBricks);
      if(!m_risk.Validate(err)) { Teardown(); return false; }

      m_gatedBroker = new CMksRiskGatedBroker(m_stressBroker, m_risk);

      // Trade journal (in-memory, money-aware p/ o report em moeda) + decorator.
      m_journal = new CMksTradeJournal(m_symbol.Point());
      m_journal.SetMoneyConversion(m_symbol.TickSize(), m_symbol.TickValue());
      m_journalBroker = new CMksTradeJournalingBroker(m_gatedBroker, m_journal, m_account);

      // Estratégia (broker = journaling broker; book habilita auto-detach).
      m_strategy = new CMksColorReversalStrategy(m_journalBroker, m_posSizer,
                                                 m_symbol, m_cfg.slPoints,
                                                 m_cfg.magic, m_logger, m_book, NULL);

      m_multiSink = new CMksMultiSink();
      m_multiSink.Add(m_strategy);

      m_builder = new CMksRenkoBuilder(m_geom, m_brickSizer, m_multiSink,
                                       m_cfg.invalidLimit, m_cfg.thresholdLimit,
                                       m_cfg.kRecoverAfter);
      m_builder.SetEmitForming(false);

      m_initialized = true;
      return true;
   }

   //--- Ordem-por-tick (MESMA do CMksDecisionRunner; ponto load-bearing:
   // stressBroker.OnTick ANTES de builder.IngestTick — o Send da estratégia,
   // disparado DENTRO do IngestTick, preenche pelo mid DESTE tick).
   void OnTick(const MksTick &t)
   {
      if(!m_initialized) return;

      if(t.IsValid())
      {
         double mid = (t.bid + t.ask) / 2.0;
         m_clock.SetNow(t.timeMsc);
         m_account.SetMid(mid);
         m_stressBroker.OnTick(t);   // delega sim.OnTick + re-estressa auto-closes
         DrainAutoCloses();          // alimenta journal + conta
      }

      MksError err;
      if(!m_builder.IngestTick(t, err))
      {
         if(err.code == MKS_ERR_RENKO_INVALID_TICK)             m_ticksInvalid++;
         else if(err.code == MKS_ERR_RENKO_TICK_STREAM_CORRUPT) m_halted = true;
      }

      if(t.IsValid())
         m_snapshot.Update();

      m_ticksFed++;
   }

   // Captura o report do nível (métricas REAIS do stress broker + PnL do
   // journal). Chamável a qualquer momento; canônico após o último tick.
   CMksStressLabReport Report()
   {
      CMksStressLabReport r;
      if(m_stressBroker != NULL && m_journal != NULL)
         r.Capture(m_levelName, m_stressParams.rngSeed,
                   m_stressBroker.Metrics(), m_journal);
      return r;
   }

   //--- Observabilidade -------------------------------------------------+
   bool   IsReady()       const { return m_initialized; }
   long   TicksFed()      const { return m_ticksFed; }
   long   TicksInvalid()  const { return m_ticksInvalid; }
   bool   Halted()        const { return m_halted; }
   long   BricksSeen()    const { return (m_strategy != NULL) ? (long)m_strategy.Metrics().bricksSeen : 0; }
   int    TradesClosed()  const { return (m_journal != NULL) ? m_journal.ClosedCount() : 0; }
   double NetPnLPoints()  const { return (m_journal != NULL) ? m_journal.NetPnLPoints() : 0.0; }
   double Balance()       const { return (m_account != NULL) ? m_account.Balance() : 0.0; }
   double Equity()        const { return (m_account != NULL) ? m_account.Equity() : 0.0; }
   int    OpenPositions() const { return (m_simBroker != NULL) ? m_simBroker.OpenPositionsCount() : 0; }
   string LevelName()     const { return m_levelName; }

   CMksColorReversalMetrics StrategyMetrics() const
   {
      if(m_strategy != NULL) return m_strategy.Metrics();
      CMksColorReversalMetrics empty;
      return empty;
   }
};

#endif // MKS_ULTIMATE_STRATEGY_RUNNER_CMKSSTRESSRUNNER_MQH
