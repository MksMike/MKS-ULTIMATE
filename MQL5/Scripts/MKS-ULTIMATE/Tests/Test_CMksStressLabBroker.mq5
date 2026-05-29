//+------------------------------------------------------------------+
//| @file           : Test_CMksStressLabBroker.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksStressLabBroker — passthrough sem
//|                   stress, rejeicao probabilistica, slippage FIXED
//|                   e NORMAL, requote loop, spread multiplier,
//|                   metricas. Determinismo via seed do CMksRandom.
//|                   Fase 7 ADR-019.
//| @depends_on     : StressLab/CMksStressLabBroker.mqh,
//|                   StressLab/CMksStressParams.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksRecordingBroker.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksStressLabBroker.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/StressLab/CMksStressLabBroker.mqh>
#include <MKS-ULTIMATE/StressLab/CMksStressParams.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksRecordingBroker.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksSimulatedBroker.mqh>  // exit-stress tests (ADR-030)

#define SL_TOL 1e-9

const double POINT_XAU = 0.01;
const double BASE_FILL = 2050.00;

//+------------------------------------------------------------------+
//| Helper: monta request padrão                                      |
//+------------------------------------------------------------------+
MksOrderRequest MakeBuy(double lots = 0.1)
{
   MksOrderRequest r;
   r.side = MKS_ORDER_BUY;
   r.lots = lots;
   r.slPoints = 100.0;
   r.tpPoints = 200.0;
   r.comment  = "stress test";
   return r;
}

MksOrderRequest MakeSell(double lots = 0.1)
{
   MksOrderRequest r;
   r.side = MKS_ORDER_SELL;
   r.lots = lots;
   r.slPoints = 100.0;
   r.tpPoints = 200.0;
   r.comment  = "stress test";
   return r;
}

//==================================================================
// Passthrough (sem stress)
//==================================================================

void Test_SL_NoStressPassthrough()
{
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksStressParams p = MksStressNone();
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeBuy());
   MKS_ASSERT_TRUE(r.IsFilled(), "FILLED sem stress");
   MKS_ASSERT_NEAR_DOUBLE(BASE_FILL, r.fillPrice, SL_TOL, "fillPrice intacto");
   MKS_ASSERT_EQ_INT(1, under.SendCount(), "underlying chamado 1x");
}

//==================================================================
// Rejection
//==================================================================

void Test_SL_RejectionAlways()
{
   CMksRecordingBroker under;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksStressParams p;
   p.rejectionProb = 1.0;
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   for(int i = 0; i < 10; i++)
   {
      MksExecutionResult r = stress.Send(MakeBuy());
      MKS_ASSERT_TRUE(r.status == MKS_EXEC_REJECTED, "REJECTED com prob=1");
   }
   MKS_ASSERT_EQ_INT(0, under.SendCount(), "underlying NUNCA chamado");
   MKS_ASSERT_EQ_LONG(10, stress.Metrics().sendsRejectedPre, "metrics.sendsRejectedPre=10");
}

void Test_SL_RejectionZero()
{
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksStressParams p;
   p.rejectionProb = 0.0;
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   for(int i = 0; i < 10; i++)
      stress.Send(MakeBuy());
   MKS_ASSERT_EQ_INT(10, under.SendCount(), "underlying chamado 10x");
   MKS_ASSERT_EQ_LONG(0, stress.Metrics().sendsRejectedPre, "0 rejeicoes pre");
}

//==================================================================
// Slippage FIXED
//==================================================================

void Test_SL_FixedSlippageBUY()
{
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksStressParams p;
   p.slippageDist = MKS_STRESS_DIST_FIXED;
   p.slippageMean = 2.0; // 2 pontos de slip
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeBuy());
   double expected = BASE_FILL + 2.0 * POINT_XAU;
   MKS_ASSERT_NEAR_DOUBLE(expected, r.fillPrice, SL_TOL, "BUY paga mais caro com slip+");
}

void Test_SL_FixedSlippageSELL()
{
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksStressParams p;
   p.slippageDist = MKS_STRESS_DIST_FIXED;
   p.slippageMean = 2.0;
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeSell());
   double expected = BASE_FILL - 2.0 * POINT_XAU;
   MKS_ASSERT_NEAR_DOUBLE(expected, r.fillPrice, SL_TOL, "SELL recebe menos com slip");
}

//==================================================================
// Slippage NORMAL — determinismo via seed
//==================================================================

void Test_SL_NormalSlippageDeterministic()
{
   CMksRecordingBroker under1, under2;
   under1.SetNextSendFillPrice(BASE_FILL);
   under2.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);

   CMksStressParams p;
   p.slippageDist = MKS_STRESS_DIST_NORMAL;
   p.slippageMean = 3.0; p.slippageStdev = 1.0;
   p.rngSeed = 12345;

   CMksStressLabBroker stress1(GetPointer(under1), GetPointer(sym), p);
   CMksStressLabBroker stress2(GetPointer(under2), GetPointer(sym), p);

   for(int i = 0; i < 50; i++)
   {
      MksExecutionResult r1 = stress1.Send(MakeBuy());
      MksExecutionResult r2 = stress2.Send(MakeBuy());
      MKS_ASSERT_NEAR_DOUBLE(r1.fillPrice, r2.fillPrice, SL_TOL,
                             StringFormat("fillPrice deterministico [%d]", i));
   }
}

//==================================================================
// Spread multiplier compõe sobre baseline (ADR-027 §7.2)
//==================================================================

void Test_SL_SpreadMultiplierComposesWithBaseline()
{
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);

   // Baseline=10pts (spread real do CostModel), mult=3.0 → spread efetivo
   // ficou 30pts (+20pts extras), distribuídos como +10pts adversos por lado.
   // Sem slip da distribuição. Fórmula: (3-1)*(10/2) = 10pts extras.
   CMksStressParams p;
   p.slippageDist          = MKS_STRESS_DIST_FIXED;
   p.slippageMean          = 0.0;
   p.spreadMultiplier      = 3.0;
   p.baselineSpreadPoints  = 10.0;
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeBuy());
   double expected = BASE_FILL + 10.0 * POINT_XAU;
   MKS_ASSERT_NEAR_DOUBLE(expected, r.fillPrice, SL_TOL,
                          "spread mult 3x sobre baseline=10 = +10 pts adversos");
}

void Test_SL_SpreadMultiplierNoOpWithoutBaseline()
{
   // Mesmo com mult=10, sem baseline configurado, não há composição.
   // Garante que comportamento legado (baseline=0) não dispara slip
   // espúrio — mudança da fórmula nunca silenciosamente quebra setups
   // antigos que não conhecem baselineSpreadPoints.
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);

   CMksStressParams p;
   p.slippageDist     = MKS_STRESS_DIST_FIXED;
   p.slippageMean     = 0.0;
   p.spreadMultiplier = 10.0;
   // baselineSpreadPoints default = 0
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeBuy());
   MKS_ASSERT_NEAR_DOUBLE(BASE_FILL, r.fillPrice, SL_TOL,
                          "sem baseline, spreadMultiplier não afeta fill");
}

//==================================================================
// Latency drift adverso (ADR-027 §7.1)
//==================================================================

void Test_SL_LatencyDriftAdverseFixed()
{
   // Latency 0 stdev → mean exato. 100ms × 0.01pts/ms = 1pt adverso.
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);

   CMksStressParams p;
   p.slippageDist           = MKS_STRESS_DIST_FIXED;
   p.slippageMean           = 0.0;
   p.latencyMeanMs          = 100.0;
   p.latencyStdevMs         = 0.0;
   p.latencyDriftPointsPerMs = 0.01;
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeBuy());
   // Stdev=0: NextGaussian retorna mean exato → latency = 100ms → +1pt.
   double expected = BASE_FILL + 1.0 * POINT_XAU;
   MKS_ASSERT_NEAR_DOUBLE(expected, r.fillPrice, SL_TOL,
                          "100ms × 0.01pts/ms = +1pt adverso no BUY");

   CMksStressMetrics m = stress.Metrics();
   MKS_ASSERT_NEAR_DOUBLE(100.0, m.latencyTotalMs, 1e-6, "latency contabilizada");
   MKS_ASSERT_NEAR_DOUBLE(100.0, m.latencyMaxMs,   1e-6, "max latency");
}

void Test_SL_LatencyZeroDriftPreservesLegacy()
{
   // driftPerMs=0 → latency é sorteada mas não afeta o fill.
   // Preserva semântica "informativa" antiga onde latency só era log.
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);

   CMksStressParams p;
   p.latencyMeanMs          = 500.0;
   p.latencyStdevMs         = 100.0;
   p.latencyDriftPointsPerMs = 0.0; // legado
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeBuy());
   MKS_ASSERT_NEAR_DOUBLE(BASE_FILL, r.fillPrice, SL_TOL,
                          "drift=0 preserva fill mesmo com latency alta");
}

//==================================================================
// Requote — modelado internamente (ADR-030), independente do underlying
//==================================================================

void Test_SL_RequoteStormRejects()
{
   // requoteProb=1.0, maxRequotes=3 → 3 requotes consecutivos → tempestade
   // → REJECTED. Modelo novo (ADR-030): requote e interno; o underlying NEM
   // e chamado no storm (antes dependia dele retornar REJECTED — knob morto
   // contra o broker simulado, que sempre preenche).
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);

   CMksStressParams p;
   p.rejectionProb = 0.0;
   p.requoteProb   = 1.0;
   p.maxRequotes   = 3;
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeBuy());
   MKS_ASSERT_TRUE(r.status == MKS_EXEC_REJECTED, "REJECTED por tempestade de requote");
   MKS_ASSERT_EQ_INT(0, under.SendCount(), "underlying NAO chamado em storm (requote interno)");
   MKS_ASSERT_EQ_LONG(3, stress.Metrics().requoteEvents, "3 requoteEvents");
   MKS_ASSERT_EQ_LONG(1, stress.Metrics().sendsRejectedRequote, "1 rejeicao por requote");
}

void Test_SL_RequoteCleanFillWhenProbZero()
{
   // requoteProb=0 → nenhum requote, fill limpo com slip base. Garante que
   // o knob desligado nao dispara requote e que o underlying e chamado 1x.
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);

   CMksStressParams p;
   p.requoteProb  = 0.0;
   p.maxRequotes  = 5;
   p.slippageDist = MKS_STRESS_DIST_FIXED;
   p.slippageMean = 1.0;
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeBuy());
   MKS_ASSERT_TRUE(r.IsFilled(), "FILLED sem requote");
   MKS_ASSERT_EQ_INT(1, under.SendCount(), "underlying chamado 1x");
   MKS_ASSERT_EQ_LONG(0, stress.Metrics().requoteEvents, "0 requotes com prob=0");
   MKS_ASSERT_NEAR_DOUBLE(BASE_FILL + 1.0 * POINT_XAU, r.fillPrice, SL_TOL, "fill com slip base");
}

//==================================================================
// Saidas estressadas (ADR-030) — exitSim concreto destrava close/auto-close
//==================================================================

void Test_SL_CloseAppliesAdverseSlip()
{
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksCostModel  cm; // custos zero → fill do sim = mid exato
   CMksSimulatedBroker sim(GetPointer(sym), GetPointer(cm));

   MksTick t; t.bid = 2050.00; t.ask = 2050.00; t.timeMsc = 1000; t.seq = 1;
   sim.OnTick(t);
   MksExecutionResult open = sim.Send(MakeBuy()); // BUY @ mid=2050
   MKS_ASSERT_TRUE(open.IsFilled(), "abertura FILLED");

   CMksStressParams p;
   p.slippageDist = MKS_STRESS_DIST_FIXED;
   p.slippageMean = 2.0;
   // exitSim = o MESMO sim broker → destrava slip de saida (ADR-030).
   CMksStressLabBroker stress(GetPointer(sim), GetPointer(sym), p, GetPointer(sim));

   MksExecutionResult c = stress.Close(open.positionId, 0.1);
   MKS_ASSERT_TRUE(c.IsFilled(), "close FILLED");
   // BUY → close = SELL → adverso = recebe MENOS → fill abaixo do mid.
   double expected = 2050.00 - 2.0 * POINT_XAU;
   MKS_ASSERT_NEAR_DOUBLE(expected, c.fillPrice, SL_TOL, "close de BUY recebe menos (slip adverso)");
   MKS_ASSERT_EQ_LONG(1, stress.Metrics().closesStressed, "1 close estressado");
}

void Test_SL_AutoCloseAppliesAdverseSlip()
{
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksCostModel  cm; // custos zero
   CMksSimulatedBroker sim(GetPointer(sym), GetPointer(cm));

   MksTick t1; t1.bid = 2050.00; t1.ask = 2050.00; t1.timeMsc = 1000; t1.seq = 1;
   sim.OnTick(t1);
   MksExecutionResult open = sim.Send(MakeBuy()); // BUY @ 2050, SL 100pts = 2049.0
   MKS_ASSERT_TRUE(open.IsFilled(), "abertura FILLED");

   CMksStressParams p;
   p.slippageDist = MKS_STRESS_DIST_FIXED;
   p.slippageMean = 3.0;
   CMksStressLabBroker stress(GetPointer(sim), GetPointer(sym), p, GetPointer(sim));

   // Preco cai para 2048 → bidProxy=2048 <= SL=2049 → SL hit.
   MksTick t2; t2.bid = 2048.00; t2.ask = 2048.00; t2.timeMsc = 2000; t2.seq = 2;
   stress.OnTick(t2); // delega ao sim → SL dispara → StressLab aplica slip

   MksSimAutoCloseEvent evs[];
   int n = stress.PollAutoCloses(evs);
   MKS_ASSERT_EQ_INT(1, n, "1 auto-close drenado do StressLab");
   MKS_ASSERT_TRUE(evs[0].hitSl, "foi SL hit");
   // sim fecha SL a mid=2048 (cm zero); BUY → close SELL → adverso → -3pts.
   double expected = 2048.00 - 3.0 * POINT_XAU;
   MKS_ASSERT_NEAR_DOUBLE(expected, evs[0].closePrice, SL_TOL, "auto-close de SL recebe slip adverso");
   MKS_ASSERT_EQ_LONG(1, stress.Metrics().autoClosesStressed, "1 auto-close estressado");
}

//==================================================================
// Metricas
//==================================================================

void Test_SL_MetricsAggregate()
{
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);

   CMksStressParams p;
   p.slippageDist = MKS_STRESS_DIST_FIXED;
   p.slippageMean = 1.5;
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   for(int i = 0; i < 5; i++) stress.Send(MakeBuy());
   CMksStressMetrics m = stress.Metrics();
   MKS_ASSERT_EQ_LONG(5, m.sendAttempts, "5 attempts");
   MKS_ASSERT_EQ_LONG(5, m.sendsFilled,  "5 filled");
   MKS_ASSERT_NEAR_DOUBLE(7.5, m.slippageTotalPoints, SL_TOL, "5 * 1.5 = 7.5 pts");
   MKS_ASSERT_NEAR_DOUBLE(1.5, m.slippageMaxPoints,   SL_TOL, "max=1.5");
}

void Test_SL_ResetMetrics()
{
   CMksRecordingBroker under;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksStressParams p;
   p.slippageDist = MKS_STRESS_DIST_FIXED;
   p.slippageMean = 1.0;
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   for(int i = 0; i < 3; i++) stress.Send(MakeBuy());
   MKS_ASSERT_EQ_LONG(3, stress.Metrics().sendAttempts, "antes do reset");
   stress.ResetMetrics();
   MKS_ASSERT_EQ_LONG(0, stress.Metrics().sendAttempts, "apos reset");
   MKS_ASSERT_NEAR_DOUBLE(0.0, stress.Metrics().slippageTotalPoints, SL_TOL, "slip zerado");
}

//==================================================================
// Passthrough Close / Modify
//==================================================================

void Test_SL_CloseAndModifyPassthrough()
{
   CMksRecordingBroker under;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksStressParams p = MksStressHigh(); // SEM exitSim → Close/Modify passthrough (ADR-030)
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   stress.Close(123, 0.1);
   MKS_ASSERT_EQ_INT(1, under.CloseCount(), "Close delegado");

   bool ok = stress.Modify(123, 2000.0, 2100.0);
   MKS_ASSERT_TRUE(ok, "Modify retorna true");
   MKS_ASSERT_EQ_INT(1, under.ModifyCount(), "Modify delegado");
}

//==================================================================
// Null underlying
//==================================================================

void Test_SL_NullUnderlyingReturnsError()
{
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksStressParams p = MksStressNone();
   CMksStressLabBroker stress(NULL, GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeBuy());
   MKS_ASSERT_TRUE(r.status == MKS_EXEC_ERROR, "ERROR com underlying NULL");
}

//==================================================================
// Presets — smoke
//==================================================================

void Test_SL_PresetsSmoke()
{
   // Verifica que os 5 presets sao construiveis e tem propriedades esperadas.
   CMksStressParams none      = MksStressNone();
   CMksStressParams light     = MksStressLight();
   CMksStressParams medium    = MksStressMedium();
   CMksStressParams high      = MksStressHigh();
   CMksStressParams nightmare = MksStressNightmare();

   MKS_ASSERT_NEAR_DOUBLE(1.0, none.spreadMultiplier, SL_TOL, "none.spread=1.0");
   MKS_ASSERT_NEAR_DOUBLE(0.0, none.rejectionProb,    SL_TOL, "none.rej=0.0");

   // Severidade monotonicamente crescente em rejectionProb
   MKS_ASSERT_TRUE(none.rejectionProb < light.rejectionProb,         "none < light");
   MKS_ASSERT_TRUE(light.rejectionProb < medium.rejectionProb,       "light < medium");
   MKS_ASSERT_TRUE(medium.rejectionProb < high.rejectionProb,        "medium < high");
   MKS_ASSERT_TRUE(high.rejectionProb < nightmare.rejectionProb,     "high < nightmare");

   // Severidade monotonicamente crescente em spreadMultiplier
   MKS_ASSERT_TRUE(light.spreadMultiplier < medium.spreadMultiplier,    "spread light<medium");
   MKS_ASSERT_TRUE(medium.spreadMultiplier < high.spreadMultiplier,     "spread medium<high");
   MKS_ASSERT_TRUE(high.spreadMultiplier < nightmare.spreadMultiplier,  "spread high<nightmare");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksStressLabBroker ===");

   MKS_RUN(Test_SL_NoStressPassthrough);

   MKS_RUN(Test_SL_RejectionAlways);
   MKS_RUN(Test_SL_RejectionZero);

   MKS_RUN(Test_SL_FixedSlippageBUY);
   MKS_RUN(Test_SL_FixedSlippageSELL);
   MKS_RUN(Test_SL_NormalSlippageDeterministic);

   MKS_RUN(Test_SL_SpreadMultiplierComposesWithBaseline);
   MKS_RUN(Test_SL_SpreadMultiplierNoOpWithoutBaseline);

   MKS_RUN(Test_SL_LatencyDriftAdverseFixed);
   MKS_RUN(Test_SL_LatencyZeroDriftPreservesLegacy);

   MKS_RUN(Test_SL_RequoteStormRejects);
   MKS_RUN(Test_SL_RequoteCleanFillWhenProbZero);

   MKS_RUN(Test_SL_CloseAppliesAdverseSlip);
   MKS_RUN(Test_SL_AutoCloseAppliesAdverseSlip);

   MKS_RUN(Test_SL_MetricsAggregate);
   MKS_RUN(Test_SL_ResetMetrics);

   MKS_RUN(Test_SL_CloseAndModifyPassthrough);
   MKS_RUN(Test_SL_NullUnderlyingReturnsError);

   MKS_RUN(Test_SL_PresetsSmoke);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
