//+------------------------------------------------------------------+
//| @file           : Test_CMksTradeManager.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksTradeManager — BE, trailing, partial
//|                   close, state machine, ordem de avaliacao e
//|                   integracao com IBroker via CMksRecordingBroker.
//|                   Slice 5b da ADR-019.
//| @depends_on     : Core/Trade/CMksTradeManager.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksRecordingBroker.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksTradeManager.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Trade/CMksTradeManager.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksRecordingBroker.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakePositionBook.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

#define TM_DOUBLE_TOL 1e-9

// Constantes do cenário base usado em quase todos os testes:
// XAUUSDm-like: point=0.01, entry=2000.00, lots=0.10, side=BUY
const double ENTRY_BUY  = 2000.00;
const double POINT_XAU  = 0.01;
const double LOTS_INIT  = 0.10;
const ulong  POS_ID     = 12345;

//+------------------------------------------------------------------+
//| Helper: monta tick com bid/ask a partir de delta em pontos        |
//| Para BUY: delta>0 = lucro (bid sobe). Para SELL: delta>0 = lucro  |
//| (ask desce).                                                       |
//+------------------------------------------------------------------+
MksTick TickFromPoints(double entry, double deltaPoints,
                       ENUM_MKS_ORDER_SIDE side, double point)
{
   MksTick t;
   if(side == MKS_ORDER_BUY)
   {
      t.bid = entry + deltaPoints * point;
      t.ask = t.bid + 0.05;
   }
   else
   {
      t.ask = entry - deltaPoints * point;
      t.bid = t.ask - 0.05;
   }
   t.timeMsc = 0;
   return t;
}

//==================================================================
// Validate
//==================================================================

void Test_TM_Validate_OkAllOff()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   MksError err;
   MKS_ASSERT_TRUE(tm.Validate(err), "Validate ok com tudo desligado");
}

void Test_TM_Validate_OkFullConfig()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 50.0; p.beOffsetPoints = 5.0;
   p.trailEnabled = true; p.trailStartPoints = 100.0; p.trailStepPoints = 50.0;
   p.partialEnabled = true; p.partialTriggerPoints = 75.0; p.partialClosePct = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   MksError err;
   MKS_ASSERT_TRUE(tm.Validate(err), "Validate ok com config completa");
}

void Test_TM_Validate_NullBrokerFails()
{
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   CMksTradeManager tm(NULL, GetPointer(sym), p);
   MksError err;
   MKS_ASSERT_FALSE(tm.Validate(err), "Validate falha — broker NULL");
}

void Test_TM_Validate_BeBadActivationFails()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 0.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   MksError err;
   MKS_ASSERT_FALSE(tm.Validate(err), "Validate falha — beActivation<=0");
}

void Test_TM_Validate_BeNegativeOffsetFails()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 50.0; p.beOffsetPoints = -1.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   MksError err;
   MKS_ASSERT_FALSE(tm.Validate(err), "Validate falha — beOffset<0");
}

void Test_TM_Validate_TrailBadParamsFails()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.trailEnabled = true; p.trailStartPoints = 100.0; p.trailStepPoints = 0.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   MksError err;
   MKS_ASSERT_FALSE(tm.Validate(err), "Validate falha — trailStep<=0");
}

void Test_TM_Validate_PartialBadPctFails()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.partialEnabled = true; p.partialTriggerPoints = 50.0; p.partialClosePct = 150.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   MksError err;
   MKS_ASSERT_FALSE(tm.Validate(err), "Validate falha — pct>=100");
}

//==================================================================
// Attach / Detach
//==================================================================

void Test_TM_AttachInitState()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);

   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);
   MKS_ASSERT_TRUE (tm.IsAttached(),    "attached");
   MKS_ASSERT_FALSE(tm.IsBeApplied(),   "BE nao aplicado");
   MKS_ASSERT_FALSE(tm.IsTrailing(),    "trail nao ativo");
   MKS_ASSERT_FALSE(tm.IsPartialDone(), "partial nao executado");
   MKS_ASSERT_NEAR_DOUBLE(1990.0, tm.CurrentSl(), TM_DOUBLE_TOL, "SL inicial");
   MKS_ASSERT_EQ_ULONG(POS_ID, tm.PositionId(), "positionId");
}

void Test_TM_Detach()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);

   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);
   tm.Detach();
   MKS_ASSERT_FALSE(tm.IsAttached(), "detach -> nao attached");
}

void Test_TM_UpdateNoOpWhenNotAttached()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);

   MksTick t = TickFromPoints(ENTRY_BUY, 100.0, MKS_ORDER_BUY, POINT_XAU);
   MksTradeManagerStep step = tm.Update(t);
   MKS_ASSERT_EQ_INT(0, step.brokerCalls, "no broker call sem attach");
   MKS_ASSERT_EQ_INT(0, br.ModifyCount(), "ModifyCount=0");
}

//==================================================================
// Break-even
//==================================================================

void Test_TM_BE_AppliesWhenProfitReached_BUY()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 50.0; p.beOffsetPoints = 5.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   // Profit = 60 pontos (>= 50 activation)
   MksTick t = TickFromPoints(ENTRY_BUY, 60.0, MKS_ORDER_BUY, POINT_XAU);
   MksTradeManagerStep step = tm.Update(t);

   MKS_ASSERT_TRUE(step.beApplied,    "step.beApplied");
   MKS_ASSERT_TRUE(tm.IsBeApplied(),  "IsBeApplied");
   MKS_ASSERT_EQ_INT(1, br.ModifyCount(), "1 Modify");

   double expectedSl = ENTRY_BUY + 5.0 * POINT_XAU; // 2000.05
   MKS_ASSERT_NEAR_DOUBLE(expectedSl, tm.CurrentSl(), TM_DOUBLE_TOL, "SL = entry + offset");
   MKS_ASSERT_NEAR_DOUBLE(expectedSl, br.LastModify().slPrice, TM_DOUBLE_TOL, "Modify SL price");
}

void Test_TM_BE_AppliesWhenProfitReached_SELL()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 50.0; p.beOffsetPoints = 5.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_SELL, ENTRY_BUY, LOTS_INIT, 2010.0, 1950.0);

   MksTick t = TickFromPoints(ENTRY_BUY, 60.0, MKS_ORDER_SELL, POINT_XAU);
   MksTradeManagerStep step = tm.Update(t);

   MKS_ASSERT_TRUE(step.beApplied, "BE aplicado SELL");
   double expectedSl = ENTRY_BUY - 5.0 * POINT_XAU; // 1999.95 (SELL: offset acima do entry virou abaixo)
   MKS_ASSERT_NEAR_DOUBLE(expectedSl, tm.CurrentSl(), TM_DOUBLE_TOL, "SL SELL = entry - offset");
}

void Test_TM_BE_DoesNotApplyBelowActivation()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 50.0; p.beOffsetPoints = 0.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   MksTick t = TickFromPoints(ENTRY_BUY, 30.0, MKS_ORDER_BUY, POINT_XAU);
   MksTradeManagerStep step = tm.Update(t);
   MKS_ASSERT_FALSE(step.beApplied,   "BE nao aplica abaixo do trigger");
   MKS_ASSERT_FALSE(tm.IsBeApplied(), "IsBeApplied false");
   MKS_ASSERT_EQ_INT(0, br.ModifyCount(), "sem Modify");
}

void Test_TM_BE_Idempotent()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 50.0; p.beOffsetPoints = 0.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   MksTick t = TickFromPoints(ENTRY_BUY, 60.0, MKS_ORDER_BUY, POINT_XAU);
   tm.Update(t);
   tm.Update(t);
   tm.Update(t);
   MKS_ASSERT_EQ_INT(1, br.ModifyCount(), "BE nao re-aplicado (idempotente)");
}

void Test_TM_BE_ModifyFailureKeepsBeUnset()
{
   CMksRecordingBroker br;
   br.SetNextModifyReturns(false); // Modify "falha"
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   MksTick t = TickFromPoints(ENTRY_BUY, 60.0, MKS_ORDER_BUY, POINT_XAU);
   MksTradeManagerStep step = tm.Update(t);
   MKS_ASSERT_FALSE(step.beApplied,   "step.beApplied false em falha");
   MKS_ASSERT_FALSE(tm.IsBeApplied(), "IsBeApplied false em falha");
   // SL não muda
   MKS_ASSERT_NEAR_DOUBLE(1990.0, tm.CurrentSl(), TM_DOUBLE_TOL, "SL original preservado");
}

//==================================================================
// Partial close
//==================================================================

void Test_TM_Partial_ExecutesWhenTriggerReached()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.partialEnabled = true; p.partialTriggerPoints = 75.0; p.partialClosePct = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   MksTick t = TickFromPoints(ENTRY_BUY, 80.0, MKS_ORDER_BUY, POINT_XAU);
   MksTradeManagerStep step = tm.Update(t);

   MKS_ASSERT_TRUE (step.partialDone,   "step.partialDone");
   MKS_ASSERT_TRUE (tm.IsPartialDone(), "IsPartialDone");
   MKS_ASSERT_EQ_INT(1, br.CloseCount(), "1 Close");
   MKS_ASSERT_NEAR_DOUBLE(0.05, br.LastClose().lots, TM_DOUBLE_TOL, "lots = initial*50%");
   MKS_ASSERT_EQ_ULONG(POS_ID, br.LastClose().positionId, "positionId");
}

void Test_TM_Partial_Idempotent()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.partialEnabled = true; p.partialTriggerPoints = 75.0; p.partialClosePct = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   MksTick t = TickFromPoints(ENTRY_BUY, 80.0, MKS_ORDER_BUY, POINT_XAU);
   tm.Update(t); tm.Update(t); tm.Update(t);
   MKS_ASSERT_EQ_INT(1, br.CloseCount(), "partial idempotente");
}

void Test_TM_Partial_CloseFailureKeepsPartialUnset()
{
   CMksRecordingBroker br;
   br.SetNextCloseStatus(MKS_EXEC_ERROR);
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.partialEnabled = true; p.partialTriggerPoints = 75.0; p.partialClosePct = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   MksTick t = TickFromPoints(ENTRY_BUY, 80.0, MKS_ORDER_BUY, POINT_XAU);
   MksTradeManagerStep step = tm.Update(t);
   MKS_ASSERT_FALSE(step.partialDone,   "step false em falha");
   MKS_ASSERT_FALSE(tm.IsPartialDone(), "IsPartialDone false em falha");
}

//==================================================================
// Trailing stop
//==================================================================

void Test_TM_Trail_ActivatesAtStart_BUY()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.trailEnabled = true; p.trailStartPoints = 100.0; p.trailStepPoints = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   // bid = entry + 100 = 2001.00; trail SL = bid - 50 pontos = 2000.50
   MksTick t = TickFromPoints(ENTRY_BUY, 100.0, MKS_ORDER_BUY, POINT_XAU);
   MksTradeManagerStep step = tm.Update(t);
   MKS_ASSERT_TRUE(step.trailUpdated, "trail update");
   MKS_ASSERT_TRUE(tm.IsTrailing(),   "IsTrailing");
   double expected = 2001.00 - 50.0 * POINT_XAU; // 2000.50
   MKS_ASSERT_NEAR_DOUBLE(expected, tm.CurrentSl(), TM_DOUBLE_TOL, "trail SL BUY");
}

void Test_TM_Trail_ActivatesAtStart_SELL()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.trailEnabled = true; p.trailStartPoints = 100.0; p.trailStepPoints = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_SELL, ENTRY_BUY, LOTS_INIT, 2010.0, 1950.0);

   // ask = entry - 100 = 1999.00; trail SL = ask + 50 pontos = 1999.50
   MksTick t = TickFromPoints(ENTRY_BUY, 100.0, MKS_ORDER_SELL, POINT_XAU);
   MksTradeManagerStep step = tm.Update(t);
   MKS_ASSERT_TRUE(step.trailUpdated, "trail update SELL");
   double expected = 1999.00 + 50.0 * POINT_XAU; // 1999.50
   MKS_ASSERT_NEAR_DOUBLE(expected, tm.CurrentSl(), TM_DOUBLE_TOL, "trail SL SELL");
}

void Test_TM_Trail_OnlyMovesFavorably_BUY()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.trailEnabled = true; p.trailStartPoints = 100.0; p.trailStepPoints = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   MksTick high  = TickFromPoints(ENTRY_BUY, 150.0, MKS_ORDER_BUY, POINT_XAU); // bid=2001.50
   tm.Update(high);
   double slAfterHigh = tm.CurrentSl(); // 2001.00

   // Preço cai mas ainda acima do start
   MksTick lower = TickFromPoints(ENTRY_BUY, 110.0, MKS_ORDER_BUY, POINT_XAU); // bid=2001.10
   MksTradeManagerStep step = tm.Update(lower);
   MKS_ASSERT_FALSE(step.trailUpdated, "trail nao move em queda");
   MKS_ASSERT_NEAR_DOUBLE(slAfterHigh, tm.CurrentSl(), TM_DOUBLE_TOL,
                          "SL preservado (trail so avanca)");
}

void Test_TM_Trail_AdvancesMultipleTicks()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.trailEnabled = true; p.trailStartPoints = 100.0; p.trailStepPoints = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   tm.Update(TickFromPoints(ENTRY_BUY, 100.0, MKS_ORDER_BUY, POINT_XAU));
   tm.Update(TickFromPoints(ENTRY_BUY, 150.0, MKS_ORDER_BUY, POINT_XAU));
   tm.Update(TickFromPoints(ENTRY_BUY, 200.0, MKS_ORDER_BUY, POINT_XAU));
   MKS_ASSERT_EQ_INT(3, br.ModifyCount(), "3 Modify (trail 3 ticks)");

   double finalSl = 2000.00 + 200.0 * POINT_XAU - 50.0 * POINT_XAU; // bid 2002 - 50pts = 2001.50
   MKS_ASSERT_NEAR_DOUBLE(finalSl, tm.CurrentSl(), TM_DOUBLE_TOL, "SL final do trail");
}

void Test_TM_Trail_DoesNotActivateBelowStart()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.trailEnabled = true; p.trailStartPoints = 100.0; p.trailStepPoints = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   tm.Update(TickFromPoints(ENTRY_BUY, 80.0, MKS_ORDER_BUY, POINT_XAU));
   MKS_ASSERT_FALSE(tm.IsTrailing(),       "trail nao ativa abaixo do start");
   MKS_ASSERT_EQ_INT(0, br.ModifyCount(),  "sem Modify");
}

//==================================================================
// Combinações + ordem
//==================================================================

void Test_TM_BeBeforeTrailInSameTick()
{
   // Tick que supera ambos os limites: BE (50pts) e Trail (100pts).
   // Esperado: BE aplica primeiro, depois trail (BE seta SL = entry,
   // trail avança para entry + 100 - 50 = entry + 50 = 2000.50).
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 50.0; p.beOffsetPoints = 0.0;
   p.trailEnabled = true; p.trailStartPoints = 100.0; p.trailStepPoints = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   MksTick t = TickFromPoints(ENTRY_BUY, 100.0, MKS_ORDER_BUY, POINT_XAU);
   MksTradeManagerStep step = tm.Update(t);
   MKS_ASSERT_TRUE(step.beApplied,    "BE aplicado");
   MKS_ASSERT_TRUE(step.trailUpdated, "trail aplicado");
   MKS_ASSERT_EQ_INT(2, br.ModifyCount(), "2 Modify (BE + trail)");

   // Primeiro Modify foi BE (SL = entry); segundo foi trail (SL = bid - step).
   MKS_ASSERT_NEAR_DOUBLE(ENTRY_BUY, br.ModifyAt(0).slPrice, TM_DOUBLE_TOL, "1o Modify = BE");
   double trailSl = (ENTRY_BUY + 100.0 * POINT_XAU) - 50.0 * POINT_XAU;
   MKS_ASSERT_NEAR_DOUBLE(trailSl, br.ModifyAt(1).slPrice, TM_DOUBLE_TOL, "2o Modify = trail");
   MKS_ASSERT_NEAR_DOUBLE(trailSl, tm.CurrentSl(), TM_DOUBLE_TOL, "SL final = trail");
}

void Test_TM_BePartialTrailAllInOneTick()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.beEnabled = true;      p.beActivationPoints   = 50.0;  p.beOffsetPoints      = 0.0;
   p.partialEnabled = true; p.partialTriggerPoints = 75.0;  p.partialClosePct     = 50.0;
   p.trailEnabled = true;   p.trailStartPoints     = 100.0; p.trailStepPoints     = 50.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 1990.0, 2050.0);

   MksTick t = TickFromPoints(ENTRY_BUY, 120.0, MKS_ORDER_BUY, POINT_XAU);
   MksTradeManagerStep step = tm.Update(t);
   MKS_ASSERT_TRUE(step.beApplied,    "BE");
   MKS_ASSERT_TRUE(step.partialDone,  "partial");
   MKS_ASSERT_TRUE(step.trailUpdated, "trail");
   MKS_ASSERT_EQ_INT(3, step.brokerCalls, "3 broker calls no mesmo tick");
   MKS_ASSERT_EQ_INT(2, br.ModifyCount(), "2 Modify (BE + trail)");
   MKS_ASSERT_EQ_INT(1, br.CloseCount(),  "1 Close (partial)");
}

//==================================================================
// Auto-detach via IPositionBook (Fase 9 prep + ADR-027 §7.3)
//==================================================================

void Test_TM_AutoDetach_WhenPositionClosedExternally()
{
   // Book injetado + posição marcada como fechada → Update auto-detacha
   // sem chamar broker e sinaliza autoDetached na step.
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksFakePositionBook book;
   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 50.0; p.beOffsetPoints = 5.0;
   p.trailEnabled = true; p.trailStartPoints = 100.0; p.trailStepPoints = 30.0;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p, NULL, GetPointer(book));
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT,
             ENTRY_BUY - 100*POINT_XAU, ENTRY_BUY + 200*POINT_XAU);

   // Tick que normalmente dispararia BE + trail (lucro 120pts).
   MksTick t = TickFromPoints(ENTRY_BUY, 120.0, MKS_ORDER_BUY, POINT_XAU);

   // Broker fechou a posição (ex.: SL/TP auto-trigger do CMksSimulatedBroker).
   book.MarkClosed(POS_ID);

   MksTradeManagerStep step = tm.Update(t);
   MKS_ASSERT_TRUE(step.autoDetached, "step.autoDetached marcado");
   MKS_ASSERT_FALSE(step.beApplied,    "BE NÃO disparou (posição já foi)");
   MKS_ASSERT_FALSE(step.trailUpdated, "trail NÃO disparou");
   MKS_ASSERT_EQ_INT(0, step.brokerCalls, "zero chamadas de broker");
   MKS_ASSERT_EQ_INT(0, br.ModifyCount(), "broker NÃO recebeu Modify");
   MKS_ASSERT_EQ_INT(0, br.CloseCount(),  "broker NÃO recebeu Close");
   MKS_ASSERT_FALSE(tm.IsAttached(), "manager auto-detachou");
}

void Test_TM_AutoDetach_SubsequentUpdateIsNoOp()
{
   // Após auto-detach, próximos Update voltam ao no-op (não pollam o book
   // de novo, não logam, não fazem nada).
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksFakePositionBook book;
   CMksTradeManagerParams p;
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p, NULL, GetPointer(book));
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT, 0, 0);
   book.MarkClosed(POS_ID);

   MksTradeManagerStep step1 = tm.Update(TickFromPoints(ENTRY_BUY, 50, MKS_ORDER_BUY, POINT_XAU));
   MKS_ASSERT_TRUE(step1.autoDetached, "1o Update auto-detacha");

   MksTradeManagerStep step2 = tm.Update(TickFromPoints(ENTRY_BUY, 60, MKS_ORDER_BUY, POINT_XAU));
   MKS_ASSERT_FALSE(step2.autoDetached, "2o Update já não auto-detacha");
   MKS_ASSERT_EQ_INT(0, step2.brokerCalls, "2o Update no-op total");
}

void Test_TM_NoBook_LegacyBehaviorPreserved()
{
   // Sem book → comportamento legado: TradeManager confia que posição
   // segue aberta, chama broker mesmo se ela tiver sumido. Garante que
   // código pré-existente que não conhece IPositionBook continua
   // funcionando idêntico ao antes da mudança.
   CMksRecordingBroker br;
   CMksFakeSymbol sym; sym.SetPoint(POINT_XAU);
   CMksTradeManagerParams p;
   p.beEnabled = true; p.beActivationPoints = 50.0; p.beOffsetPoints = 5.0;
   // Sem book — usa overload de 4 args (logger=NULL).
   CMksTradeManager tm(GetPointer(br), GetPointer(sym), p);
   tm.Attach(POS_ID, MKS_ORDER_BUY, ENTRY_BUY, LOTS_INIT,
             ENTRY_BUY - 100*POINT_XAU, ENTRY_BUY + 200*POINT_XAU);

   MksTick t = TickFromPoints(ENTRY_BUY, 60.0, MKS_ORDER_BUY, POINT_XAU);
   MksTradeManagerStep step = tm.Update(t);
   MKS_ASSERT_TRUE(step.beApplied, "BE aplica (sem book = legado)");
   MKS_ASSERT_FALSE(step.autoDetached, "autoDetached fica false sempre sem book");
   MKS_ASSERT_EQ_INT(1, br.ModifyCount(), "broker recebeu Modify normal");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksTradeManager ===");

   MKS_RUN(Test_TM_Validate_OkAllOff);
   MKS_RUN(Test_TM_Validate_OkFullConfig);
   MKS_RUN(Test_TM_Validate_NullBrokerFails);
   MKS_RUN(Test_TM_Validate_BeBadActivationFails);
   MKS_RUN(Test_TM_Validate_BeNegativeOffsetFails);
   MKS_RUN(Test_TM_Validate_TrailBadParamsFails);
   MKS_RUN(Test_TM_Validate_PartialBadPctFails);

   MKS_RUN(Test_TM_AttachInitState);
   MKS_RUN(Test_TM_Detach);
   MKS_RUN(Test_TM_UpdateNoOpWhenNotAttached);

   MKS_RUN(Test_TM_BE_AppliesWhenProfitReached_BUY);
   MKS_RUN(Test_TM_BE_AppliesWhenProfitReached_SELL);
   MKS_RUN(Test_TM_BE_DoesNotApplyBelowActivation);
   MKS_RUN(Test_TM_BE_Idempotent);
   MKS_RUN(Test_TM_BE_ModifyFailureKeepsBeUnset);

   MKS_RUN(Test_TM_Partial_ExecutesWhenTriggerReached);
   MKS_RUN(Test_TM_Partial_Idempotent);
   MKS_RUN(Test_TM_Partial_CloseFailureKeepsPartialUnset);

   MKS_RUN(Test_TM_Trail_ActivatesAtStart_BUY);
   MKS_RUN(Test_TM_Trail_ActivatesAtStart_SELL);
   MKS_RUN(Test_TM_Trail_OnlyMovesFavorably_BUY);
   MKS_RUN(Test_TM_Trail_AdvancesMultipleTicks);
   MKS_RUN(Test_TM_Trail_DoesNotActivateBelowStart);

   MKS_RUN(Test_TM_BeBeforeTrailInSameTick);
   MKS_RUN(Test_TM_BePartialTrailAllInOneTick);

   MKS_RUN(Test_TM_AutoDetach_WhenPositionClosedExternally);
   MKS_RUN(Test_TM_AutoDetach_SubsequentUpdateIsNoOp);
   MKS_RUN(Test_TM_NoBook_LegacyBehaviorPreserved);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
