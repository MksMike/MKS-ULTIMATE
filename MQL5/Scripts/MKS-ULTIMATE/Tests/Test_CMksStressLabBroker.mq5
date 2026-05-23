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
// Spread multiplier
//==================================================================

void Test_SL_SpreadMultiplierAddsSlip()
{
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);

   // Sem slip base, so spread x3 = 2 pontos extras (3.0 - 1.0 = 2.0)
   CMksStressParams p;
   p.slippageDist     = MKS_STRESS_DIST_FIXED;
   p.slippageMean     = 0.0;
   p.spreadMultiplier = 3.0;
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeBuy());
   double expected = BASE_FILL + 2.0 * POINT_XAU; // 0 slip + 2 do spread
   MKS_ASSERT_NEAR_DOUBLE(expected, r.fillPrice, SL_TOL, "spread mult 3x = +2 pts");
}

//==================================================================
// Requote
//==================================================================

void Test_SL_RequoteEsgota()
{
   // Underlying sempre retorna REJECTED, requoteProb=1.0, maxRequotes=3
   // → 1 send inicial + 3 requotes = 4 chamadas no underlying, fim com REJECTED.
   CMksRecordingBroker under;
   under.SetNextSendStatus(MKS_EXEC_REJECTED);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);

   CMksStressParams p;
   p.rejectionProb = 0.0;  // sem rejeicao pre
   p.requoteProb   = 1.0;  // sempre requota
   p.maxRequotes   = 3;
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeBuy());
   MKS_ASSERT_TRUE(r.status == MKS_EXEC_REJECTED, "REJECTED apos esgotar requotes");
   MKS_ASSERT_EQ_INT(4, under.SendCount(), "underlying chamado 1+3=4 vezes");
   MKS_ASSERT_EQ_LONG(3, stress.Metrics().requoteEvents, "3 requoteEvents");
   MKS_ASSERT_EQ_LONG(1, stress.Metrics().sendsRejectedRequote, "1 rejeicao por requote esgotado");
}

void Test_SL_RequoteSucessoNaPrimeira()
{
   CMksRecordingBroker under;
   under.SetNextSendFillPrice(BASE_FILL); // FILLED por default
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);

   CMksStressParams p;
   p.requoteProb = 1.0;
   p.maxRequotes = 5;
   CMksStressLabBroker stress(GetPointer(under), GetPointer(sym), p);

   MksExecutionResult r = stress.Send(MakeBuy());
   MKS_ASSERT_TRUE(r.IsFilled(), "FILLED na primeira tentativa");
   MKS_ASSERT_EQ_INT(1, under.SendCount(), "underlying chamado 1x");
   MKS_ASSERT_EQ_LONG(0, stress.Metrics().requoteEvents, "0 requotes");
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
   CMksStressParams p = MksStressHigh(); // mesmo com stress, Close/Modify nao sao afetados
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

   MKS_RUN(Test_SL_SpreadMultiplierAddsSlip);

   MKS_RUN(Test_SL_RequoteEsgota);
   MKS_RUN(Test_SL_RequoteSucessoNaPrimeira);

   MKS_RUN(Test_SL_MetricsAggregate);
   MKS_RUN(Test_SL_ResetMetrics);

   MKS_RUN(Test_SL_CloseAndModifyPassthrough);
   MKS_RUN(Test_SL_NullUnderlyingReturnsError);

   MKS_RUN(Test_SL_PresetsSmoke);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
