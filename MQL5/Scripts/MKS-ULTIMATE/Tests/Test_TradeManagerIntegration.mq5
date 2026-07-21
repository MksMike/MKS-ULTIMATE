//+------------------------------------------------------------------+
//| @file           : Test_TradeManagerIntegration.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : E5.1/E5.2 — prova o CMksTradeManager num composition
//|                   root REAL (não mock): compõe a cadeia
//|                     CMksCostModel -> CMksSimulatedBroker
//|                       -> CMksRiskGatedBroker(+CMksRiskManager+Sizer+book)
//|                       -> CMksTradeManager(+CMksSimPositionBook)
//|                   e exercita BE/trailing/partial contra FILLS REAIS do
//|                   simulador, o auto-close de SL/TP, o auto-detach via
//|                   IPositionBook, a rejeição do gate de risco, e o
//|                   tratamento de fill de fechamento PARCIAL (E5.2 —
//|                   acumula residual, fecha exatamente o alvo, não
//|                   re-fecha). Fecha os achados [trademanager-not-wired-
//|                   in-ea] e [partial-close-partial-status-reapplies].
//|                   Reframe (checkpoint §7): prova DETERMINISMO sim↔sim +
//|                   wiring, NÃO fidelidade ao broker real.
//| @depends_on     : Core/Broker/CMksSimulatedBroker.mqh + CMksCostModel,
//|                   Core/Position/CMksSimPositionBook.mqh,
//|                   Core/Risk/CMksRiskManager.mqh + CMksRiskGatedBroker,
//|                   Core/Trade/CMksTradeManager.mqh + CMksFixedLotSizer,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_TradeManagerIntegration.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Broker/CMksCostModel.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksSimulatedBroker.mqh>
#include <MKS-ULTIMATE/Core/Position/CMksSimPositionBook.mqh>
#include <MKS-ULTIMATE/Core/Risk/CMksRiskManager.mqh>
#include <MKS-ULTIMATE/Core/Risk/CMksRiskGatedBroker.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksTradeManager.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksFixedLotSizer.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

#define TMI_TOL     1e-9
#define TMI_LOT_TOL 1e-9

// Cenário base: XAU-like point=0.01 (digits=2, tickValue=1 — defaults do
// CMksFakeSymbol). CostModel ZERADO (spread/slip/comissão = 0) para que o
// fill do sim seja o próprio mid e a geometria de SL/BE/trail seja exata e
// auditável. O eixo de custo já é provado no E4 (Test_CMksTradeJournal /
// Test_CMksStressLabReport); aqui o foco é o WIRING da gestão.
const double PT       = 0.01;
const double OPEN_MID = 2000.00;
const double LOTS     = 0.10;
const double SL_PTS   = 100.0;   // SL inicial protetor a 1999.00 no BUY

//+------------------------------------------------------------------+
//| Tick com bid==ask==price (spread 0). timeMsc monotônico via seq.  |
//+------------------------------------------------------------------+
MksTick Mk(double price, ulong seq)
{
   MksTick t;
   t.seq     = seq;
   t.timeMsc = (long)seq * 1000;
   t.bid     = price;
   t.ask     = price;
   return t;
}

//+------------------------------------------------------------------+
//| Abre um BUY de `lots`/`slPoints` via a cadeia gated, no mid        |
//| `price`. Retorna o positionId (0 se rejeitada) e preenche o entry  |
//| e o SL absoluto que o simulador gravou. Mesma sequência que um EA  |
//| faria: sim.OnTick (fixa o mid) ANTES do Send (fill sai desse mid). |
//+------------------------------------------------------------------+
ulong OpenBuy(CMksSimulatedBroker *sim, CMksRiskGatedBroker *gated,
              double price, double lots, double slPoints,
              ulong seq, double &entryOut, double &slOut)
{
   MksTick t = Mk(price, seq);
   sim.OnTick(t);

   MksOrderRequest req;
   req.side     = MKS_ORDER_BUY;
   req.lots     = lots;
   req.slPoints = slPoints;
   req.tpPoints = 0.0;
   req.comment  = "TMI";

   MksExecutionResult r = gated.Send(req);
   if(r.status != MKS_EXEC_FILLED) { entryOut = 0.0; slOut = 0.0; return 0; }

   entryOut = r.fillPrice;
   MksSimPosition pos;
   sim.TryGetPosition(r.positionId, pos);
   slOut = pos.sl;
   return r.positionId;
}

//==================================================================
// 1. Wiring base: risco valida, gate abre, sim reflete a posição.
//==================================================================
void Test_TMI_Wiring_ValidatesAndOpens()
{
   CMksFakeSymbol sym; sym.SetPoint(PT);
   CMksCostModel  cost(0.0, 0.0, 0.0);
   CMksSimulatedBroker sim(GetPointer(sym), GetPointer(cost), 0.0);
   CMksSimPositionBook book(GetPointer(sim));
   CMksFixedLotSizer   sizer(GetPointer(sym), LOTS);

   CMksRiskTradeParams    tp;  // requireSl=true por default
   CMksRiskStrategyParams sp;  sp.maxOpenPositions = 1;
   CMksRiskManager risk(tp, sp, GetPointer(book), GetPointer(sizer), NULL);
   MksError verr;
   MKS_ASSERT_TRUE(risk.Validate(verr), "risk wiring valida");

   CMksRiskGatedBroker gated(GetPointer(sim), GetPointer(risk));

   double entry, sl;
   ulong pid = OpenBuy(GetPointer(sim), GetPointer(gated),
                       OPEN_MID, LOTS, SL_PTS, 1, entry, sl);

   MKS_ASSERT_TRUE(pid > 0, "posição aberta pelo gate");
   MKS_ASSERT_NEAR_DOUBLE(OPEN_MID, entry, TMI_TOL, "entry = mid (spread 0)");
   MKS_ASSERT_NEAR_DOUBLE(OPEN_MID - SL_PTS * PT, sl, TMI_TOL, "SL inicial = entry - slPts");
   MKS_ASSERT_EQ_INT(1, sim.OpenPositionsCount(), "sim: 1 posição aberta");
   MKS_ASSERT_TRUE(book.IsOpen(pid), "book reflete posição aberta");
}

//==================================================================
// 2. Ciclo completo BE + partial + trail contra fills reais + idem.
//==================================================================
void Test_TMI_FullLifecycle_BePartialTrail_RealSim()
{
   CMksFakeSymbol sym; sym.SetPoint(PT);
   CMksCostModel  cost(0.0, 0.0, 0.0);
   CMksSimulatedBroker sim(GetPointer(sym), GetPointer(cost), 0.0);
   CMksSimPositionBook book(GetPointer(sim));
   CMksFixedLotSizer   sizer(GetPointer(sym), LOTS);
   CMksRiskTradeParams    tp;
   CMksRiskStrategyParams sp; sp.maxOpenPositions = 1;
   CMksRiskManager risk(tp, sp, GetPointer(book), GetPointer(sizer), NULL);
   CMksRiskGatedBroker gated(GetPointer(sim), GetPointer(risk));

   double entry, sl;
   ulong pid = OpenBuy(GetPointer(sim), GetPointer(gated),
                       OPEN_MID, LOTS, SL_PTS, 1, entry, sl);
   MKS_ASSERT_TRUE(pid > 0, "abriu");

   // TM: BE@50 off0 | partial@75 pct50 (alvo 0.05) | trail start100 step50.
   // Broker do TM = o MESMO gated broker (Modify/Close delegam ao sim).
   CMksTradeManagerParams p;
   p.beEnabled = true;      p.beActivationPoints   = 50.0;  p.beOffsetPoints  = 0.0;
   p.partialEnabled = true; p.partialTriggerPoints = 75.0;  p.partialClosePct = 50.0;
   p.trailEnabled = true;   p.trailStartPoints     = 100.0; p.trailStepPoints = 50.0;
   CMksTradeManager tm(GetPointer(gated), GetPointer(sym), p, NULL, GetPointer(book));
   tm.Attach(pid, MKS_ORDER_BUY, entry, LOTS, sl, 0.0);

   // Tick com lucro 120 pts (price 2001.20) dispara os três no mesmo tick.
   MksTick t = Mk(OPEN_MID + 120.0 * PT, 2);
   sim.OnTick(t);                        // sem auto-close (SL 1999 << 2001.20)
   MksTradeManagerStep step = tm.Update(t);

   MKS_ASSERT_TRUE(step.beApplied,    "BE aplicado");
   MKS_ASSERT_TRUE(step.partialDone,  "partial concluído");
   MKS_ASSERT_TRUE(step.trailUpdated, "trail moveu");
   MKS_ASSERT_EQ_INT(3, step.brokerCalls, "3 chamadas de broker (BE+partial+trail)");

   // Estado do SIMULADOR (fill real), não só o interno do TM:
   MksSimPosition pos;
   MKS_ASSERT_TRUE(sim.TryGetPosition(pid, pos), "posição existe");
   MKS_ASSERT_TRUE(pos.isOpen, "posição segue aberta após partial");
   MKS_ASSERT_NEAR_DOUBLE(0.05, pos.lots, TMI_LOT_TOL, "sim: lots reduzido ao residual (0.10-0.05)");
   double trailSl = (OPEN_MID + 120.0 * PT) - 50.0 * PT; // 2000.70
   MKS_ASSERT_NEAR_DOUBLE(trailSl, pos.sl, TMI_TOL, "sim: SL = trail (não mais o BE)");
   MKS_ASSERT_NEAR_DOUBLE(0.05, tm.PartialFilledLots(), TMI_LOT_TOL, "TM: partial filled = alvo");
   MKS_ASSERT_NEAR_DOUBLE(0.05, book.TotalLots(), TMI_LOT_TOL, "book: lots totais = residual");

   // Idempotência: re-Update do MESMO tick não re-aplica nada.
   MksTradeManagerStep step2 = tm.Update(t);
   MKS_ASSERT_EQ_INT(0, step2.brokerCalls, "re-Update mesmo tick: 0 chamadas (idempotente)");
   MKS_ASSERT_FALSE(step2.beApplied,    "BE não re-aplica");
   MKS_ASSERT_FALSE(step2.partialDone,  "partial não re-aplica");
}

//==================================================================
// 3. Auto-detach: BE move o SL do sim p/ entry; preço recua e o
//    SIMULADOR auto-fecha; o TM auto-detacha sem tocar broker fantasma.
//==================================================================
void Test_TMI_AutoDetach_OnBeThenSlHit()
{
   CMksFakeSymbol sym; sym.SetPoint(PT);
   CMksCostModel  cost(0.0, 0.0, 0.0);
   CMksSimulatedBroker sim(GetPointer(sym), GetPointer(cost), 0.0);
   CMksSimPositionBook book(GetPointer(sim));
   CMksFixedLotSizer   sizer(GetPointer(sym), LOTS);
   CMksRiskTradeParams    tp;
   CMksRiskStrategyParams sp; sp.maxOpenPositions = 1;
   CMksRiskManager risk(tp, sp, GetPointer(book), GetPointer(sizer), NULL);
   CMksRiskGatedBroker gated(GetPointer(sim), GetPointer(risk));

   double entry, sl;
   ulong pid = OpenBuy(GetPointer(sim), GetPointer(gated),
                       OPEN_MID, LOTS, SL_PTS, 1, entry, sl);

   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 50.0; p.beOffsetPoints = 0.0;
   CMksTradeManager tm(GetPointer(gated), GetPointer(sym), p, NULL, GetPointer(book));
   tm.Attach(pid, MKS_ORDER_BUY, entry, LOTS, sl, 0.0);

   // Tick lucro 60: dispara BE → SL do sim vai p/ entry (2000.00).
   MksTick t1 = Mk(OPEN_MID + 60.0 * PT, 2);
   sim.OnTick(t1);
   MksTradeManagerStep s1 = tm.Update(t1);
   MKS_ASSERT_TRUE(s1.beApplied, "BE aplicado");
   MksSimPosition posAfterBe;
   sim.TryGetPosition(pid, posAfterBe);
   MKS_ASSERT_NEAR_DOUBLE(OPEN_MID, posAfterBe.sl, TMI_TOL, "sim: SL movido p/ entry (BE)");

   // Preço recua p/ 1999.50: ACIMA do SL original (1999) mas ABAIXO do BE
   // (2000) → o simulador auto-fecha por SL. Prova que o BE do TM alterou
   // de fato o SL do broker.
   MksTick t2 = Mk(1999.50, 3);
   sim.OnTick(t2);
   MKS_ASSERT_EQ_INT(0, sim.OpenPositionsCount(), "sim auto-fechou por SL do BE");
   MKS_ASSERT_EQ_LONG(1, sim.AutoCloseTotal(), "1 auto-close registrado");

   MksTradeManagerStep s2 = tm.Update(t2);
   MKS_ASSERT_TRUE(s2.autoDetached, "TM auto-detachou");
   MKS_ASSERT_FALSE(tm.IsAttached(), "TM não mais attached");
   MKS_ASSERT_EQ_INT(0, s2.brokerCalls, "0 chamadas de broker fantasma");

   // O evento de auto-close está disponível p/ o runner drenar (journal/conta).
   MksSimAutoCloseEvent evs[];
   int n = sim.PollAutoCloses(evs);
   MKS_ASSERT_EQ_INT(1, n, "1 evento de auto-close drenado");
   MKS_ASSERT_TRUE(evs[0].hitSl, "evento marcado como SL hit");
   MKS_ASSERT_EQ_ULONG(pid, evs[0].positionId, "evento referencia a posição");
}

//==================================================================
// 4. Gate rejeita 2ª abertura (maxOpenPositions=1) → sem posição
//    fantasma, composition root não vincula TM.
//==================================================================
void Test_TMI_GateRejectsSecondOpen_MaxPositions()
{
   CMksFakeSymbol sym; sym.SetPoint(PT);
   CMksCostModel  cost(0.0, 0.0, 0.0);
   CMksSimulatedBroker sim(GetPointer(sym), GetPointer(cost), 0.0);
   CMksSimPositionBook book(GetPointer(sim));
   CMksFixedLotSizer   sizer(GetPointer(sym), LOTS);
   CMksRiskTradeParams    tp;
   CMksRiskStrategyParams sp; sp.maxOpenPositions = 1;
   CMksRiskManager risk(tp, sp, GetPointer(book), GetPointer(sizer), NULL);
   CMksRiskGatedBroker gated(GetPointer(sim), GetPointer(risk));

   double e1, s1;
   ulong pid1 = OpenBuy(GetPointer(sim), GetPointer(gated),
                        OPEN_MID, LOTS, SL_PTS, 1, e1, s1);
   MKS_ASSERT_TRUE(pid1 > 0, "1ª abertura ok");

   // 2ª abertura no mesmo mid — book já tem 1 aberta → gate rejeita.
   MksTick t = Mk(OPEN_MID, 2);
   sim.OnTick(t);
   MksOrderRequest req;
   req.side = MKS_ORDER_BUY; req.lots = LOTS; req.slPoints = SL_PTS; req.tpPoints = 0.0;
   MksExecutionResult r2 = gated.Send(req);

   MKS_ASSERT_EQ_INT((int)MKS_EXEC_REJECTED, (int)r2.status, "2ª abertura rejeitada");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_OPEN_POSITIONS, r2.brokerRetcode,
                     "retcode = maxOpenPositions");
   MKS_ASSERT_EQ_ULONG(0, r2.positionId, "sem positionId (nada a vincular)");
   MKS_ASSERT_EQ_INT(1, sim.OpenPositionsCount(), "sim segue com 1 posição (sem fantasma)");
}

//==================================================================
// 5. Gate rejeita abertura sem SL (requireSl) → sem posição.
//==================================================================
void Test_TMI_GateRejectsMissingSl_NoAttach()
{
   CMksFakeSymbol sym; sym.SetPoint(PT);
   CMksCostModel  cost(0.0, 0.0, 0.0);
   CMksSimulatedBroker sim(GetPointer(sym), GetPointer(cost), 0.0);
   CMksSimPositionBook book(GetPointer(sim));
   CMksFixedLotSizer   sizer(GetPointer(sym), LOTS);
   CMksRiskTradeParams    tp;  // requireSl = true
   CMksRiskStrategyParams sp; sp.maxOpenPositions = 1;
   CMksRiskManager risk(tp, sp, GetPointer(book), GetPointer(sizer), NULL);
   CMksRiskGatedBroker gated(GetPointer(sim), GetPointer(risk));

   MksTick t = Mk(OPEN_MID, 1);
   sim.OnTick(t);
   MksOrderRequest req;
   req.side = MKS_ORDER_BUY; req.lots = LOTS; req.slPoints = 0.0; req.tpPoints = 0.0;
   MksExecutionResult r = gated.Send(req);

   MKS_ASSERT_EQ_INT((int)MKS_EXEC_REJECTED, (int)r.status, "rejeitada sem SL");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_SL_MISSING, r.brokerRetcode,
                     "retcode = SL faltando");
   MKS_ASSERT_EQ_INT(0, sim.OpenPositionsCount(), "nenhuma posição aberta");
}

//==================================================================
// 6. E5.2 — fill de fechamento PARCIAL: acumula residual e fecha
//    EXATAMENTE o alvo (não re-fecha o alvo inteiro sobre o residual).
//    Regressão de [partial-close-partial-status-reapplies].
//==================================================================
void Test_TMI_PartialFill_AccumulatesResidual_ClosesExactTarget()
{
   CMksFakeSymbol sym; sym.SetPoint(PT);
   CMksCostModel  cost(0.0, 0.0, 0.0);
   CMksSimulatedBroker sim(GetPointer(sym), GetPointer(cost), 0.0);
   CMksSimPositionBook book(GetPointer(sim));
   CMksFixedLotSizer   sizer(GetPointer(sym), LOTS);
   CMksRiskTradeParams    tp;
   CMksRiskStrategyParams sp; sp.maxOpenPositions = 1;
   CMksRiskManager risk(tp, sp, GetPointer(book), GetPointer(sizer), NULL);
   CMksRiskGatedBroker gated(GetPointer(sim), GetPointer(risk));

   double entry, sl;
   ulong pid = OpenBuy(GetPointer(sim), GetPointer(gated),
                       OPEN_MID, LOTS, SL_PTS, 1, entry, sl);

   // Partial pct 80 → alvo = 0.08. Trigger 75.
   CMksTradeManagerParams p;
   p.partialEnabled = true; p.partialTriggerPoints = 75.0; p.partialClosePct = 80.0;
   CMksTradeManager tm(GetPointer(gated), GetPointer(sym), p, NULL, GetPointer(book));
   tm.Attach(pid, MKS_ORDER_BUY, entry, LOTS, sl, 0.0);

   // Injeta: o PRÓXIMO Close preenche só 0.05 (< alvo 0.08) → PARTIAL.
   sim.SetNextCloseStatus(MKS_EXEC_PARTIAL, 0.05);

   // Tick 1 (lucro 80): TM pede Close(0.08); sim devolve PARTIAL filled=0.05.
   MksTick t1 = Mk(OPEN_MID + 80.0 * PT, 2);
   sim.OnTick(t1);
   MksTradeManagerStep s1 = tm.Update(t1);
   MKS_ASSERT_FALSE(s1.partialDone, "partial NÃO concluído (só 0.05 de 0.08)");
   MKS_ASSERT_FALSE(tm.IsPartialDone(), "IsPartialDone false");
   MKS_ASSERT_NEAR_DOUBLE(0.05, tm.PartialFilledLots(), TMI_LOT_TOL, "acumulado = 0.05");
   MksSimPosition pos1; sim.TryGetPosition(pid, pos1);
   MKS_ASSERT_NEAR_DOUBLE(0.05, pos1.lots, TMI_LOT_TOL, "sim: residual 0.10-0.05=0.05");

   // Tick 2 (lucro 80): sem injeção (consumida) → Close(residual 0.03)
   // preenche integral. Acumulado 0.08 = alvo → concluído.
   MksTick t2 = Mk(OPEN_MID + 80.0 * PT, 3);
   sim.OnTick(t2);
   MksTradeManagerStep s2 = tm.Update(t2);
   MKS_ASSERT_TRUE(s2.partialDone, "partial concluído no 2º tick");
   MKS_ASSERT_TRUE(tm.IsPartialDone(), "IsPartialDone true");
   MKS_ASSERT_NEAR_DOUBLE(0.08, tm.PartialFilledLots(), TMI_LOT_TOL, "acumulado = alvo 0.08");
   MksSimPosition pos2; sim.TryGetPosition(pid, pos2);
   MKS_ASSERT_NEAR_DOUBLE(0.02, pos2.lots, TMI_LOT_TOL, "sim: residual final 0.10-0.08=0.02");

   // Tick 3: partial já concluído → nenhuma nova Close (não re-fecha).
   MksTick t3 = Mk(OPEN_MID + 80.0 * PT, 4);
   sim.OnTick(t3);
   MksTradeManagerStep s3 = tm.Update(t3);
   MKS_ASSERT_EQ_INT(0, s3.brokerCalls, "sem re-fechamento após concluído");
   MksSimPosition pos3; sim.TryGetPosition(pid, pos3);
   MKS_ASSERT_NEAR_DOUBLE(0.02, pos3.lots, TMI_LOT_TOL, "sim: residual intacto (0.02)");

   // Prova o antídoto do bug: total fechado pelo partial = 0.08 = alvo
   // (LOTS - residual). Sem o fix, o PARTIAL do tick 1 re-emitiria o alvo
   // inteiro sobre o residual (over-close) ou travaria em rejeições.
   MKS_ASSERT_NEAR_DOUBLE(0.08, LOTS - pos3.lots, TMI_LOT_TOL,
                          "volume total fechado pelo partial == alvo exato");
}

//==================================================================
// 7. Determinismo do caminho integrado: duas cadeias independentes
//    com a MESMA sequência produzem estado idêntico do simulador.
//==================================================================
void Test_TMI_Deterministic_TwoRunsIdentical()
{
   double slA = 0.0, slB = 0.0, lotsA = 0.0, lotsB = 0.0;
   int    callsA = 0, callsB = 0;

   for(int run = 0; run < 2; run++)
   {
      CMksFakeSymbol sym; sym.SetPoint(PT);
      CMksCostModel  cost(0.0, 0.0, 0.0);
      CMksSimulatedBroker sim(GetPointer(sym), GetPointer(cost), 0.0);
      CMksSimPositionBook book(GetPointer(sim));
      CMksFixedLotSizer   sizer(GetPointer(sym), LOTS);
      CMksRiskTradeParams    tp;
      CMksRiskStrategyParams sp; sp.maxOpenPositions = 1;
      CMksRiskManager risk(tp, sp, GetPointer(book), GetPointer(sizer), NULL);
      CMksRiskGatedBroker gated(GetPointer(sim), GetPointer(risk));

      double entry, sl;
      ulong pid = OpenBuy(GetPointer(sim), GetPointer(gated),
                          OPEN_MID, LOTS, SL_PTS, 1, entry, sl);

      CMksTradeManagerParams p;
      p.beEnabled = true;    p.beActivationPoints = 50.0; p.beOffsetPoints = 0.0;
      p.trailEnabled = true; p.trailStartPoints = 100.0;  p.trailStepPoints = 50.0;
      CMksTradeManager tm(GetPointer(gated), GetPointer(sym), p, NULL, GetPointer(book));
      tm.Attach(pid, MKS_ORDER_BUY, entry, LOTS, sl, 0.0);

      int calls = 0;
      double prices[] = {2000.60, 2001.20, 2001.80, 2002.40};
      for(int i = 0; i < ArraySize(prices); i++)
      {
         MksTick t = Mk(prices[i], (ulong)(i + 2));
         sim.OnTick(t);
         MksTradeManagerStep st = tm.Update(t);
         calls += st.brokerCalls;
      }
      MksSimPosition pos; sim.TryGetPosition(pid, pos);
      if(run == 0) { slA = pos.sl; lotsA = pos.lots; callsA = calls; }
      else         { slB = pos.sl; lotsB = pos.lots; callsB = calls; }
   }

   MKS_ASSERT_NEAR_DOUBLE(slA, slB, TMI_TOL, "SL final idêntico entre runs");
   MKS_ASSERT_NEAR_DOUBLE(lotsA, lotsB, TMI_LOT_TOL, "lots final idêntico entre runs");
   MKS_ASSERT_EQ_INT(callsA, callsB, "total de chamadas de broker idêntico entre runs");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_TradeManagerIntegration (E5.1/E5.2) ===");

   MKS_RUN(Test_TMI_Wiring_ValidatesAndOpens);
   MKS_RUN(Test_TMI_FullLifecycle_BePartialTrail_RealSim);
   MKS_RUN(Test_TMI_AutoDetach_OnBeThenSlHit);
   MKS_RUN(Test_TMI_GateRejectsSecondOpen_MaxPositions);
   MKS_RUN(Test_TMI_GateRejectsMissingSl_NoAttach);
   MKS_RUN(Test_TMI_PartialFill_AccumulatesResidual_ClosesExactTarget);
   MKS_RUN(Test_TMI_Deterministic_TwoRunsIdentical);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
