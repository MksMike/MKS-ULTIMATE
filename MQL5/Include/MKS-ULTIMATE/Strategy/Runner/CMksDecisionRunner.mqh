//+------------------------------------------------------------------+
//| @file           : CMksDecisionRunner.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Strategy / Runner
//| @responsibility : Núcleo determinístico da paridade de DECISÃO (DDR,
//|                   E2). Monta o grafo canônico
//|                     feed -> CMksRenkoBuilder -> CMksColorReversalStrategy
//|                       -> CMksJournalingBroker -> CMksRiskGatedBroker
//|                       -> CMksSimulatedBroker (+CMksSimAccount, book,
//|                          FeedClock, AccountSnapshot, DecisionJournal)
//|                   e expõe UM helper de ordem-por-tick (OnTick). Essa
//|                   ordem é load-bearing e ÚNICA: qualquer consumidor
//|                   (Replayer live/replay E2.1, golden headless E2.2)
//|                   dirige o MESMO grafo pela MESMA rotina — anti-
//|                   bifurcação por construção. Emite um decision journal
//|                   TSV determinístico: mesmo .mkstick + config pinada
//|                   -> mesmo journal byte-a-byte.
//|                   Acoplado ao CMksColorReversalStrategy (a estratégia
//|                   da Fase 9, INTOCADA) — daí residir em Strategy/, não
//|                   em Core/ (não inverter Core->Strategy).
//| @depends_on     : Core/Broker/CMksSimulatedBroker.mqh + CMksCostModel,
//|                   Core/Account/CMksSimAccount + CMksAccountSnapshot,
//|                   Core/Position/CMksSimPositionBook.mqh,
//|                   Core/Clock/CMksFeedClock.mqh,
//|                   Core/RenkoBuilder/CMksRenkoBuilder + CMksFixedBrickSizer,
//|                   Core/Trade/CMksFixedLotSizer + CMksPercentRiskSizer +
//|                     CMksDecisionJournal + CMksJournalingBroker,
//|                   Core/Risk/CMksRiskManager + CMksRiskGatedBroker,
//|                   Core/Output/CMksMultiSink.mqh,
//|                   Strategy/CMksColorReversalStrategy.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Strategy/Runner/CMksDecisionRunner.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_STRATEGY_RUNNER_CMKSDECISIONRUNNER_MQH
#define MKS_ULTIMATE_STRATEGY_RUNNER_CMKSDECISIONRUNNER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ILogger.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IPositionSizer.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>
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
#include <MKS-ULTIMATE/Core/Trade/CMksDecisionJournal.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksJournalingBroker.mqh>
#include <MKS-ULTIMATE/Core/Risk/CMksRiskManager.mqh>
#include <MKS-ULTIMATE/Core/Risk/CMksRiskGatedBroker.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksMultiSink.mqh>
#include <MKS-ULTIMATE/Strategy/CMksColorReversalStrategy.mqh>

//+------------------------------------------------------------------+
//| Sink de contexto: roda ANTES da estratégia no MultiSink. A cada    |
//| brick fechado, carimba o journal com (brickIdx, triggerTickId) —   |
//| o SEND/CLOSE que a estratégia disparar em seguida herda esse       |
//| contexto. brickIdx é 0-based e monotônico.                         |
//+------------------------------------------------------------------+
class CMksDecisionContextSink : public IRenkoSink
{
private:
   CMksDecisionJournal *m_journal;
   long                 m_brickIdx;

public:
   CMksDecisionContextSink(CMksDecisionJournal *journal)
   {
      m_journal  = journal;
      m_brickIdx = 0;
   }

   void OnBrickClose(const MksBrick &brick) override
   {
      if(m_journal != NULL)
         m_journal.SetBrickContext(m_brickIdx, brick.triggerTickId);
      m_brickIdx++;
   }

   // Nº de bricks vistos (== próximo brickIdx a atribuir).
   long BrickIndex() const { return m_brickIdx; }
};

//+------------------------------------------------------------------+
//| Bundle pinado do runner. É a unidade versionada do golden (E2.2):  |
//| feed + CostModel + modelo-de-conta + config-da-estratégia + risco. |
//| Defaults sãos p/ XAU classic (brick 3.0, SL >= 1 brick).           |
//+------------------------------------------------------------------+
struct MksDecisionRunnerConfig
{
   //--- Journal / proveniência do feed (vai para o header, ignorado no diff)
   string journalPath;
   string feedBroker;
   long   feedAccount;
   bool   isShadow;        // E2.5: banner de captura-shadow
   int    fillDays;        // E2.3: paridade exige 0 (aqui só anotado)

   //--- Brick (classic, ADR-026)
   double brickSize;       // unidades de preço
   int    invalidLimit;    // L (ADR-006)
   int    thresholdLimit;  // K (ADR-011)
   int    kRecoverAfter;   // recovery de gap (ADR-011 nota)

   //--- CostModel
   double spreadPoints;
   double slippagePoints;
   double commissionPerLot;

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
   double minSlFloorPts;   // belt absoluto do piso de SL (pontos)
   int    minSlBricks;     // piso de SL ancorado em bricks (E0.3/M12)

   //--- Risco: por estratégia
   int    maxOpenPositions;
   double maxTotalLots;

   //--- Risco: por conta
   double maxDailyLossPct;
   double maxDrawdownPct;
   double minEquityAbs;

   MksDecisionRunnerConfig()
   {
      journalPath      = "";
      feedBroker       = "SIM";
      feedAccount      = 0;
      isShadow         = false;
      fillDays         = 0;

      brickSize        = 3.0;
      invalidLimit     = 10;
      thresholdLimit   = 20;
      kRecoverAfter    = 5;

      spreadPoints     = 0.0;
      slippagePoints   = 0.0;
      commissionPerLot = 0.0;

      startBalance     = 10000.0;
      applySwap        = false;

      slPoints         = 3000.0;
      magic            = 527001;

      lotMode          = "FIXED";
      fixedLots        = 0.01;
      riskPct          = 1.0;

      requireSl        = true;
      maxLotsPerTrade  = 0.0;
      minSlFloorPts    = 0.0;
      minSlBricks      = 1;

      maxOpenPositions = 1;
      maxTotalLots     = 0.0;

      maxDailyLossPct  = 0.0;
      maxDrawdownPct   = 0.0;
      minEquityAbs     = 0.0;
   }
};

//+------------------------------------------------------------------+
//| CMksDecisionRunner — dono do grafo + helper de ordem-por-tick.     |
//| Uso:                                                               |
//|   CMksDecisionRunner run(GetPointer(sym), cfg, GetPointer(log));   |
//|   MksError err;                                                    |
//|   if(!run.Init(err)) { ...trata... }                              |
//|   ... por cada tick do feed:  run.OnTick(t);                       |
//|   run.Finish();   // escreve rodapé + fecha o journal              |
//+------------------------------------------------------------------+
class CMksDecisionRunner
{
private:
   //--- Injetados (não possuídos)
   ISymbol *m_symbol;
   ILogger *m_logger;
   MksDecisionRunnerConfig m_cfg;

   //--- Possuídos (grafo)
   MksRenkoGeometry           m_geom;
   CMksCostModel             *m_costModel;
   CMksSimulatedBroker       *m_simBroker;
   CMksSimAccount            *m_account;
   CMksSimPositionBook       *m_book;
   CMksFeedClock             *m_clock;
   CMksAccountSnapshot       *m_snapshot;
   CMksFixedBrickSizer       *m_brickSizer;
   IPositionSizer            *m_posSizer;
   CMksRiskManager           *m_risk;
   CMksRiskGatedBroker       *m_gatedBroker;
   CMksDecisionJournal       *m_journal;
   CMksJournalingBroker      *m_journalBroker;
   CMksColorReversalStrategy *m_strategy;
   CMksDecisionContextSink   *m_contextSink;
   CMksMultiSink             *m_multiSink;
   CMksRenkoBuilder          *m_builder;

   //--- Estado / observabilidade
   bool m_initialized;
   bool m_headerWritten;
   bool m_finished;
   long m_ticksFed;
   long m_ticksInvalid;
   long m_ticksK102;
   long m_ticksK105;
   bool m_halted;

   //--- Buffer reusado para drenar auto-closes
   MksSimAutoCloseEvent m_evBuf[];

   void NullAll()
   {
      m_costModel     = NULL;
      m_simBroker     = NULL;
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
      m_contextSink   = NULL;
      m_multiSink     = NULL;
      m_builder       = NULL;
   }

   // Destrói o grafo em ordem reversa da construção. Idempotente
   // (deleta só não-NULL). Não toca em symbol/logger (injetados).
   void Teardown()
   {
      if(m_builder      != NULL) { delete m_builder;      m_builder      = NULL; }
      if(m_multiSink    != NULL) { delete m_multiSink;    m_multiSink    = NULL; }
      if(m_contextSink  != NULL) { delete m_contextSink;  m_contextSink  = NULL; }
      if(m_strategy     != NULL) { delete m_strategy;     m_strategy     = NULL; }
      if(m_journalBroker!= NULL) { delete m_journalBroker;m_journalBroker= NULL; }
      if(m_journal      != NULL) { delete m_journal;      m_journal      = NULL; }
      if(m_gatedBroker  != NULL) { delete m_gatedBroker;  m_gatedBroker  = NULL; }
      if(m_risk         != NULL) { delete m_risk;         m_risk         = NULL; }
      if(m_posSizer     != NULL) { delete m_posSizer;     m_posSizer     = NULL; }
      if(m_brickSizer   != NULL) { delete m_brickSizer;   m_brickSizer   = NULL; }
      if(m_snapshot     != NULL) { delete m_snapshot;     m_snapshot     = NULL; }
      if(m_clock        != NULL) { delete m_clock;        m_clock        = NULL; }
      if(m_book         != NULL) { delete m_book;         m_book         = NULL; }
      if(m_account      != NULL) { delete m_account;      m_account      = NULL; }
      if(m_simBroker    != NULL) { delete m_simBroker;    m_simBroker    = NULL; }
      if(m_costModel    != NULL) { delete m_costModel;    m_costModel    = NULL; }
   }

   // Escreve o header do journal na 1ª vez que um tick VÁLIDO chega —
   // captura a âncora (seedMid/seedTickSeq) do feed. O 1º tick válido só
   // inicializa o builder (sem brick/evento), então o header sempre
   // precede qualquer linha de decisão.
   void WriteHeaderOnce(const MksTick &t)
   {
      if(m_headerWritten || m_journal == NULL) return;
      if(!t.IsValid()) return;

      MksDecisionJournalHeader h;
      h.symbol       = m_symbol.Name();
      h.broker       = m_cfg.feedBroker;
      h.account      = m_cfg.feedAccount;
      h.digits       = m_symbol.Digits();
      h.point        = m_symbol.Point();
      h.tickSize     = m_symbol.TickSize();
      h.seedMid      = (t.bid + t.ask) / 2.0;
      h.seedTickSeq  = t.seq;
      h.spreadPts    = m_cfg.spreadPoints;
      h.slipPts      = m_cfg.slippagePoints;
      h.commPerLot   = m_cfg.commissionPerLot;
      h.startBalance = m_cfg.startBalance;
      h.applySwap    = m_cfg.applySwap;
      h.slPoints     = m_cfg.slPoints;
      h.magic        = m_cfg.magic;
      h.lotMode      = m_cfg.lotMode;
      h.fixedLots    = m_cfg.fixedLots;
      h.riskPct      = m_cfg.riskPct;
      h.fillDays     = m_cfg.fillDays;
      h.isShadow     = m_cfg.isShadow;

      m_journal.WriteHeader(h);
      m_headerWritten = true;
   }

   // Drena os auto-closes de SL/TP que o simulador enfileirou no OnTick.
   // Journal primeiro (oráculo da decisão), depois o modelo de dinheiro.
   // Só o runner alimenta a conta neste caminho — o JournalingBroker
   // cuida de Send/Close; sem alimentação dupla.
   void DrainAutoCloses()
   {
      int n = m_simBroker.PollAutoCloses(m_evBuf);
      for(int i = 0; i < n; i++)
      {
         m_journal.RecordAutoClose(m_evBuf[i].side, m_evBuf[i].positionId,
                                   m_evBuf[i].lots, m_evBuf[i].triggerTickSeq);
         if(m_account != NULL)
            m_account.OnClose(m_evBuf[i].positionId, m_evBuf[i].closePrice,
                              m_evBuf[i].commissionClose);
      }
   }

public:
   // symbol obrigatório (borda cria CMksMt5Symbol em live/replay,
   // CMksFakeSymbol em teste). logger opcional (NULL desliga o log
   // estruturado — e mantém o journal livre de wall-clock; o journal
   // NUNCA passa por logger).
   CMksDecisionRunner(ISymbol *symbol, const MksDecisionRunnerConfig &cfg,
                      ILogger *logger = NULL)
   {
      m_symbol = symbol;
      m_logger = logger;
      m_cfg    = cfg;

      m_initialized   = false;
      m_headerWritten = false;
      m_finished      = false;
      m_ticksFed      = 0;
      m_ticksInvalid  = 0;
      m_ticksK102     = 0;
      m_ticksK105     = 0;
      m_halted        = false;

      NullAll();
   }

   ~CMksDecisionRunner()
   {
      Teardown();
   }

   // Monta o grafo, valida cada peça e abre o journal. false + err em
   // qualquer falha (grafo é desmontado antes de retornar — sem leak).
   bool Init(MksError &err)
   {
      if(m_initialized)
      {
         MKS_SET_ERROR(err, MKS_ERR_CORE_INVALID_ARGUMENT,
                       "runner já inicializado (Init chamado duas vezes)", "");
         return false;
      }
      if(m_symbol == NULL)
      {
         MKS_SET_ERROR(err, MKS_ERR_CORE_INVALID_ARGUMENT,
                       "symbol nulo no runner", "");
         return false;
      }

      // Geometria classic (produtor único; estratégia opera sobre close real).
      m_geom = MksGeometryClassic();
      if(!m_geom.Validate(err)) { Teardown(); return false; }

      // CostModel + simulador (backstop de piso OFF — o gate é autoritativo).
      m_costModel = new CMksCostModel(m_cfg.spreadPoints, m_cfg.slippagePoints,
                                      m_cfg.commissionPerLot);
      if(!m_costModel.Validate(err)) { Teardown(); return false; }
      m_simBroker = new CMksSimulatedBroker(m_symbol, m_costModel, 0.0);

      // Conta sim + book + clock do feed + snapshot temporal.
      m_account  = new CMksSimAccount(m_symbol, m_cfg.startBalance, m_cfg.applySwap);
      m_book     = new CMksSimPositionBook(m_simBroker);
      m_clock    = new CMksFeedClock();
      m_snapshot = new CMksAccountSnapshot(m_account, m_clock);

      // Brick sizer (constante).
      m_brickSizer = new CMksFixedBrickSizer(m_cfg.brickSize);
      if(!m_brickSizer.Validate(err)) { Teardown(); return false; }

      // Position sizer (FIXED canônico; PERCENT lastreado na conta sim).
      if(m_cfg.lotMode == "PERCENT")
         m_posSizer = new CMksPercentRiskSizer(m_symbol, m_account, m_cfg.riskPct);
      else
         m_posSizer = new CMksFixedLotSizer(m_symbol, m_cfg.fixedLots);
      if(!m_posSizer.Validate(err)) { Teardown(); return false; }

      // RiskManager (3 camadas; book/snapshot sempre injetados — camadas
      // com params 0 ficam inativas, mas o wiring é único e válido).
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

      m_gatedBroker = new CMksRiskGatedBroker(m_simBroker, m_risk);

      // Journal + broker de journaling (o mais EXTERNO — enxerga REJECT do gate).
      m_journal = new CMksDecisionJournal();
      if(!m_journal.Open(m_cfg.journalPath))
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_FILE_IO,
                       "falha ao abrir o decision journal",
                       StringFormat("path=%s", m_cfg.journalPath));
         Teardown();
         return false;
      }
      m_journalBroker = new CMksJournalingBroker(m_gatedBroker, m_journal, m_account);

      // Estratégia (broker = journaling broker; book habilita auto-detach).
      m_strategy = new CMksColorReversalStrategy(m_journalBroker, m_posSizer,
                                                 m_symbol, m_cfg.slPoints,
                                                 m_cfg.magic, m_logger, m_book, NULL);

      // MultiSink: contexto ANTES da estratégia (contrato de ordem).
      m_contextSink = new CMksDecisionContextSink(m_journal);
      m_multiSink   = new CMksMultiSink();
      m_multiSink.Add(m_contextSink);
      m_multiSink.Add(m_strategy);

      // Builder (produtor único). Sem OnBrickForming (nenhum CS aqui).
      m_builder = new CMksRenkoBuilder(m_geom, m_brickSizer, m_multiSink,
                                       m_cfg.invalidLimit, m_cfg.thresholdLimit,
                                       m_cfg.kRecoverAfter);
      m_builder.SetEmitForming(false);

      m_initialized = true;
      return true;
   }

   //--- Helper de ordem-por-tick (ÚNICO, load-bearing, anti-bifurcação).
   //
   // Ordem exata (§4.2 do design DDR):
   //   clock.SetNow -> account.SetMid -> simBroker.OnTick
   //     -> drena PollAutoCloses (conta+journal)
   //     -> builder.IngestTick (brick -> contextSink -> estratégia:
   //        Send/Close via JournalingBroker gravam journal + alimentam conta)
   //     -> snapshot.Update.
   //
   // Por que simBroker.OnTick ANTES de builder.IngestTick: o Send da
   // estratégia (disparado DENTRO do IngestTick) preenche pelo m_lastMid
   // do simulador — que precisa ser o mid DESTE tick. Inverter faria o
   // fill sair do tick anterior (stale) e, no 1º tick, sem mid nenhum
   // (Send=ERROR). Test_DriveOrder trava se a ordem inverter.
   //
   // Ticks inválidos: só o builder os vê (guarda ADR-006 conta L); conta/
   // broker/clock não avançam sobre tick inválido — mesma semântica do
   // Replayer.
   void OnTick(const MksTick &t)
   {
      if(!m_initialized) return;

      WriteHeaderOnce(t);

      if(t.IsValid())
      {
         double mid = (t.bid + t.ask) / 2.0;
         m_clock.SetNow(t.timeMsc);
         m_account.SetMid(mid);
         m_simBroker.OnTick(t);   // pode enfileirar auto-closes de SL/TP
         DrainAutoCloses();       // alimenta journal + conta
      }

      MksError err;
      if(!m_builder.IngestTick(t, err))
      {
         if(err.code == MKS_ERR_RENKO_INVALID_TICK)              m_ticksInvalid++;
         else if(err.code == MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED) m_ticksK102++;
         else if(err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP)   m_ticksK105++;
         else if(err.code == MKS_ERR_RENKO_TICK_STREAM_CORRUPT)  m_halted = true;
      }

      if(t.IsValid())
         m_snapshot.Update();   // rollover-aware, peak monotônico (E2.4)

      m_ticksFed++;
   }

   // Escreve o rodapé (# total=N) e fecha o journal. Idempotente.
   // OBRIGATÓRIO para um journal completo/comparável byte-a-byte.
   void Finish()
   {
      if(m_finished) return;
      if(m_journal != NULL) m_journal.Close();
      m_finished = true;
   }

   //--- Observabilidade -------------------------------------------------+
   bool   IsReady()          const { return m_initialized; }
   long   TicksFed()         const { return m_ticksFed; }
   long   TicksInvalid()     const { return m_ticksInvalid; }
   long   TicksK102()        const { return m_ticksK102; }
   long   TicksK105()        const { return m_ticksK105; }
   bool   Halted()           const { return m_halted; }
   long   BricksSeen()       const { return (m_contextSink != NULL) ? m_contextSink.BrickIndex() : 0; }
   long   JournalEvents()    const { return (m_journal != NULL) ? m_journal.EventCount() : 0; }
   double Balance()          const { return (m_account != NULL) ? m_account.Balance() : 0.0; }
   double Equity()           const { return (m_account != NULL) ? m_account.Equity() : 0.0; }
   int    OpenPositions()    const { return (m_simBroker != NULL) ? m_simBroker.OpenPositionsCount() : 0; }
   long   AutoCloseTotal()   const { return (m_simBroker != NULL) ? m_simBroker.AutoCloseTotal() : 0; }
   string JournalPath()      const { return m_cfg.journalPath; }

   CMksColorReversalMetrics StrategyMetrics() const
   {
      if(m_strategy != NULL) return m_strategy.Metrics();
      CMksColorReversalMetrics empty;
      return empty;
   }

   // Ponteiro read-mostly ao simulador — para inspeção em teste
   // (preço de abertura de posição, contagem) e summary do Replayer.
   CMksSimulatedBroker *SimBroker() { return m_simBroker; }
};

#endif // MKS_ULTIMATE_STRATEGY_RUNNER_CMKSDECISIONRUNNER_MQH
