//+------------------------------------------------------------------+
//| @file           : Test_CMksCircuitBreaker.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksCircuitBreaker (ADR-040) — o breaker
//|                   CORRETIVO. Cobre: breach de equity → trip (sticky) +
//|                   flatten de todas as posições + Send bloqueado; conta
//|                   saudável nunca tripa; risk NULL = inerte; Reset destrava.
//|                   Usa o mesmo predicado Por Conta do gate preventivo
//|                   (CMksRiskManager.AccountBreached) — fonte única.
//| @depends_on     : Core/Risk/CMksCircuitBreaker.mqh,
//|                   Core/Broker/CMksSimulatedBroker.mqh + CMksCostModel,
//|                   Core/Account/CMksSimAccount.mqh + CMksAccountSnapshot.mqh,
//|                   Core/Position/CMksSimPositionBook.mqh,
//|                   Core/Clock/CMksFeedClock.mqh,
//|                   Core/Testing/Asserts.mqh + Mocks/CMksFakeSymbol.mqh,
//|                   Core/Types/OrderRequest.mqh, Core/Types/Tick.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksCircuitBreaker.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Risk/CMksCircuitBreaker.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksSimulatedBroker.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksSimAccount.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksAccountSnapshot.mqh>
#include <MKS-ULTIMATE/Core/Position/CMksSimPositionBook.mqh>
#include <MKS-ULTIMATE/Core/Clock/CMksFeedClock.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>

MksTick MkTick(double price, long seq)
{
   MksTick t;
   t.bid = price; t.ask = price; t.last = price;
   t.timeMsc = seq * 1000; t.seq = (ulong)seq;
   return t;
}

MksOrderRequest MkBuy(double lots)
{
   MksOrderRequest r;
   r.side = MKS_ORDER_BUY; r.lots = lots; r.slPoints = 0.0; r.tpPoints = 0.0;
   return r;
}

//==================================================================
// Breach de equity → trip + flatten + Send bloqueado (sticky) + Reset
//==================================================================

void Test_CB_TripsFlattensAndBlocks()
{
   CMksFakeSymbol sym;                        // point 0.01, money = dpreco·100·lots
   CMksCostModel  cost;                        // custos 0
   CMksSimulatedBroker sim(GetPointer(sym), GetPointer(cost));
   CMksSimAccount acc(GetPointer(sym), 10000.0);
   CMksSimPositionBook book(GetPointer(sim));
   CMksFeedClock clock;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clock));

   // Risco com camada Por Conta: circuit breaker absoluto em 9990.
   CMksRiskTradeParams tp; tp.requireSl = false;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.minEquityAbs = 9990.0;
   CMksRiskManager risk(tp, sp, ap, GetPointer(book), GetPointer(snap), NULL, NULL);

   CMksCircuitBreaker cb(GetPointer(sim), GetPointer(risk), GetPointer(book));

   // Estado inicial: mid 2000, conta OK.
   MksTick t0 = MkTick(2000.0, 1);
   sim.OnTick(t0);
   clock.SetNow(1000);
   acc.SetMid(2000.0);
   snap.Init();

   // Abre 1 posição PELO breaker (não tripado → delega ao sim). Espelha na conta.
   MksExecutionResult o = cb.Send(MkBuy(1.0));
   MKS_ASSERT_TRUE(o.status == MKS_EXEC_FILLED, "Send passa quando não tripado");
   MKS_ASSERT_EQ_INT(1, book.OpenCount(), "1 posição aberta no book");
   acc.OnOpen(o.positionId, MKS_ORDER_BUY, o.fillPrice, o.filledLots, 0.0);

   // Sem breach ainda (equity 10000) → OnTick não tripa.
   cb.OnTick();
   MKS_ASSERT_FALSE(cb.IsTripped(), "conta saudável: não tripa");
   MKS_ASSERT_EQ_INT(1, book.OpenCount(), "posição intacta sem breach");

   // Equity cai abaixo do mínimo: mid 1999.85 → MTM = -0.15·100·1.0 = -15 →
   // equity 9985 < 9990.
   acc.SetMid(1999.85);
   cb.OnTick();
   MKS_ASSERT_TRUE(cb.IsTripped(), "breach de equity → TRIPOU");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_MIN_EQUITY, cb.TripCode(),
                     "código do trip = min equity (mesmo do gate preventivo)");
   MKS_ASSERT_EQ_INT(0, book.OpenCount(), "flatten fechou TODAS as posições");
   MKS_ASSERT_TRUE(cb.FlattenClosed() >= 1, "ao menos 1 close no flatten");

   // Sticky: Send agora rejeitado, mesmo tick após tick.
   MksExecutionResult o2 = cb.Send(MkBuy(1.0));
   MKS_ASSERT_TRUE(o2.status == MKS_EXEC_REJECTED, "tripado → Send REJEITADO");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_MIN_EQUITY, o2.brokerRetcode,
                     "rejeição carrega o código do breach");
   MKS_ASSERT_TRUE(cb.SendsBlocked() >= 1, "contou o send bloqueado");

   // Sticky não re-arma sozinho.
   cb.OnTick();
   MKS_ASSERT_TRUE(cb.IsTripped(), "segue tripado (sticky)");

   // Reset destrava.
   cb.Reset();
   MKS_ASSERT_FALSE(cb.IsTripped(), "Reset destrava");
   MksExecutionResult o3 = cb.Send(MkBuy(1.0));
   MKS_ASSERT_TRUE(o3.status == MKS_EXEC_FILLED, "pós-Reset: Send volta a passar");
}

//==================================================================
// Conta saudável nunca tripa
//==================================================================

void Test_CB_HealthyNeverTrips()
{
   CMksFakeSymbol sym;
   CMksCostModel  cost;
   CMksSimulatedBroker sim(GetPointer(sym), GetPointer(cost));
   CMksSimAccount acc(GetPointer(sym), 10000.0);
   CMksSimPositionBook book(GetPointer(sim));
   CMksFeedClock clock;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clock));

   CMksRiskTradeParams tp; tp.requireSl = false;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.minEquityAbs = 5000.0;   // longe do equity
   CMksRiskManager risk(tp, sp, ap, GetPointer(book), GetPointer(snap), NULL, NULL);

   CMksCircuitBreaker cb(GetPointer(sim), GetPointer(risk), GetPointer(book));

   sim.OnTick(MkTick(2000.0, 1));
   clock.SetNow(1000);
   acc.SetMid(2000.0);
   snap.Init();

   for(int i = 0; i < 10; i++) { acc.SetMid(2000.0 - i * 0.5); cb.OnTick(); }
   MKS_ASSERT_FALSE(cb.IsTripped(), "equity acima do mínimo: nunca tripa");
   MKS_ASSERT_TRUE(cb.Send(MkBuy(0.1)).status == MKS_EXEC_FILLED, "Send passa");
}

//==================================================================
// risk NULL → breaker inerte (defensivo)
//==================================================================

void Test_CB_NullRiskInert()
{
   CMksFakeSymbol sym;
   CMksCostModel  cost;
   CMksSimulatedBroker sim(GetPointer(sym), GetPointer(cost));

   CMksCircuitBreaker cb(GetPointer(sim), NULL, NULL);
   sim.OnTick(MkTick(2000.0, 1));

   cb.OnTick();
   MKS_ASSERT_FALSE(cb.IsTripped(), "risk NULL: OnTick não tripa (inerte)");
   MKS_ASSERT_TRUE(cb.Send(MkBuy(0.1)).status == MKS_EXEC_FILLED,
                   "risk NULL: Send delega normalmente");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksCircuitBreaker ===");

   MKS_RUN(Test_CB_TripsFlattensAndBlocks);
   MKS_RUN(Test_CB_HealthyNeverTrips);
   MKS_RUN(Test_CB_NullRiskInert);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
