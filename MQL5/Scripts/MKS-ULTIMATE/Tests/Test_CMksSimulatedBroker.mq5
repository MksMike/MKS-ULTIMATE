//+------------------------------------------------------------------+
//| @file           : Test_CMksSimulatedBroker.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksSimulatedBroker — initialization,
//|                   Send (custos, SL/TP), Close (full/partial),
//|                   Modify, hedging, determinismo. ADR-017.
//| @depends_on     : Core/Broker/CMksSimulatedBroker.mqh,
//|                   Core/Broker/CMksCostModel.mqh,
//|                   Core/Interfaces/ISymbol.mqh, Core/Types/*
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksSimulatedBroker.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Broker/CMksSimulatedBroker.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksCostModel.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//+------------------------------------------------------------------+
//| Helpers de assertion (mesmo padrão dos outros testes do projeto)  |
//+------------------------------------------------------------------+
int    g_passed = 0;
int    g_failed = 0;
string g_currentTest = "";

void StartTest(const string name) { g_currentTest = name; }

void AssertEqualInt(int expected, int actual, const string what)
{
   if(expected == actual) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=%d actual=%d", g_currentTest, what, expected, actual);
}

void AssertEqualUlong(ulong expected, ulong actual, const string what)
{
   if(expected == actual) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=%I64u actual=%I64u",
               g_currentTest, what, expected, actual);
}

void AssertNearDouble(double expected, double actual, double tol, const string what)
{
   if(MathAbs(expected - actual) < tol) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=%.9f actual=%.9f tol=%.9f",
               g_currentTest, what, expected, actual, tol);
}

void AssertTrue(bool cond, const string what)
{
   if(cond) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=true", g_currentTest, what);
}

void AssertFalse(bool cond, const string what)
{
   if(!cond) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=false", g_currentTest, what);
}

//+------------------------------------------------------------------+
//| Symbol fake com valores hardcoded — broker não toca API global    |
//+------------------------------------------------------------------+
class CFakeSymbol : public ISymbol
{
public:
   string Name()           const override { return "FAKE"; }
   int    Digits()         const override { return 2; }
   double Point()          const override { return 0.01; }
   double TickSize()       const override { return 0.01; }
   double TickValue()      const override { return 1.0; }
   double ContractSize()   const override { return 100.0; }
   double VolumeMin()      const override { return 0.01; }
   double VolumeMax()      const override { return 100.0; }
   double VolumeStep()     const override { return 0.01; }
   int    StopsLevel()     const override { return 0; }
   int    FreezeLevel()    const override { return 0; }
   int    FillingMode()    const override { return 1; }
   string BaseCurrency()   const override { return "FAK"; }
   string ProfitCurrency() const override { return "USD"; }
   string MarginCurrency() const override { return "USD"; }
};

//+------------------------------------------------------------------+
//| Helper: monta MksTick válido com bid/ask                           |
//+------------------------------------------------------------------+
MksTick MakeTick(double bid, double ask, long timeMsc = 1000)
{
   MksTick t;
   t.seq = 1;
   t.timeMsc = timeMsc;
   t.bid = bid;
   t.ask = ask;
   t.last = 0;
   t.volume = 0;
   t.flags = 0;
   return t;
}

MksOrderRequest MakeRequest(ENUM_MKS_ORDER_SIDE side, double lots,
                            double slPoints = 0.0, double tpPoints = 0.0)
{
   MksOrderRequest r;
   r.side = side;
   r.lots = lots;
   r.slPoints = slPoints;
   r.tpPoints = tpPoints;
   r.comment = "test";
   return r;
}

//+------------------------------------------------------------------+
//| 1. Send sem OnTick prévio → BROKER_NOT_INITIALIZED                 |
//+------------------------------------------------------------------+
void Test_NotInitializedNoTick()
{
   StartTest("not_initialized_no_tick");
   CFakeSymbol sym;
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));

   MksOrderRequest req = MakeRequest(MKS_ORDER_BUY, 0.1);
   MksExecutionResult r = b.Send(req);
   AssertEqualInt((int)MKS_EXEC_ERROR, (int)r.status, "status=ERROR");
   AssertEqualInt((int)MKS_ERR_BROKER_NOT_INITIALIZED,
                  r.brokerRetcode, "retcode=NOT_INITIALIZED");
}

//+------------------------------------------------------------------+
//| 2. Send com request inválido → REJECTED                            |
//+------------------------------------------------------------------+
void Test_InvalidRequest()
{
   StartTest("invalid_request");
   CFakeSymbol sym;
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(100.0, 100.0));

   MksOrderRequest req = MakeRequest(MKS_ORDER_BUY, 0.0); // lots inválido
   MksExecutionResult r = b.Send(req);
   AssertEqualInt((int)MKS_EXEC_REJECTED, (int)r.status, "status=REJECTED");
}

//+------------------------------------------------------------------+
//| 3. Send básico sem custos → fillPrice = mid                       |
//+------------------------------------------------------------------+
void Test_SendBasicNoCosts()
{
   StartTest("send_basic_no_costs");
   CFakeSymbol sym;
   CMksCostModel cm; // zero custos
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(2000.0, 2000.0, 12345));

   MksOrderRequest req = MakeRequest(MKS_ORDER_BUY, 0.1);
   MksExecutionResult r = b.Send(req);

   AssertEqualInt((int)MKS_EXEC_FILLED, (int)r.status, "status=FILLED");
   AssertNearDouble(2000.0, r.fillPrice, 1e-9, "fillPrice = mid");
   AssertNearDouble(2000.0, r.requestedPrice, 1e-9, "requestedPrice = mid");
   AssertNearDouble(0.1, r.filledLots, 1e-9, "lots");
   AssertNearDouble(0.0, r.commission, 1e-9, "commission = 0");
   AssertNearDouble(0.0, r.swap, 1e-9, "swap = 0");
   AssertEqualUlong((ulong)1, r.positionId, "positionId = 1");
   AssertEqualUlong((ulong)1, r.dealId, "dealId = 1");
   AssertEqualInt(1, r.attempts, "attempts = 1");
   AssertEqualInt((int)12345, (int)r.execTimeMsc, "execTimeMsc");
}

//+------------------------------------------------------------------+
//| 4. Spread aplicado simetricamente nos dois lados                   |
//+------------------------------------------------------------------+
void Test_SpreadApplied()
{
   StartTest("spread_applied");
   CFakeSymbol sym;
   // spread=2 points; point=0.01 → halfSpread = 0.01
   CMksCostModel cm(2.0, 0.0, 0.0);
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(2000.0, 2000.0));

   MksExecutionResult rb = b.Send(MakeRequest(MKS_ORDER_BUY, 0.1));
   AssertNearDouble(2000.01, rb.fillPrice, 1e-9, "BUY fill = mid + halfSpread");

   MksExecutionResult rs = b.Send(MakeRequest(MKS_ORDER_SELL, 0.1));
   AssertNearDouble(1999.99, rs.fillPrice, 1e-9, "SELL fill = mid - halfSpread");
}

//+------------------------------------------------------------------+
//| 5. Slippage adverso aplicado                                       |
//+------------------------------------------------------------------+
void Test_SlippageAdverse()
{
   StartTest("slippage_adverse");
   CFakeSymbol sym;
   // sem spread, slippage=3 points
   CMksCostModel cm(0.0, 3.0, 0.0);
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(2000.0, 2000.0));

   MksExecutionResult rb = b.Send(MakeRequest(MKS_ORDER_BUY, 0.1));
   AssertNearDouble(2000.03, rb.fillPrice, 1e-9, "BUY pays mid + slip");

   MksExecutionResult rs = b.Send(MakeRequest(MKS_ORDER_SELL, 0.1));
   AssertNearDouble(1999.97, rs.fillPrice, 1e-9, "SELL receives mid - slip");
}

//+------------------------------------------------------------------+
//| 6. Comissão por lote                                              |
//+------------------------------------------------------------------+
void Test_CommissionPerLot()
{
   StartTest("commission_per_lot");
   CFakeSymbol sym;
   CMksCostModel cm(0.0, 0.0, 5.0); // $5 por lote
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(100.0, 100.0));

   MksExecutionResult r = b.Send(MakeRequest(MKS_ORDER_BUY, 0.5));
   AssertNearDouble(2.5, r.commission, 1e-9, "commission = 5 * 0.5");
}

//+------------------------------------------------------------------+
//| 7. SL/TP computados em preço absoluto                              |
//+------------------------------------------------------------------+
void Test_SlTpComputed()
{
   StartTest("sl_tp_computed");
   CFakeSymbol sym;
   CMksCostModel cm; // sem custos
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(2000.0, 2000.0));

   // BUY: SL abaixo, TP acima.
   MksExecutionResult rb = b.Send(MakeRequest(MKS_ORDER_BUY, 0.1, 10.0, 20.0));
   MksSimPosition pb;
   AssertTrue(b.TryGetPosition(rb.positionId, pb), "buy position exists");
   AssertNearDouble(1999.90, pb.sl, 1e-9, "BUY sl = fill - 10*point");
   AssertNearDouble(2000.20, pb.tp, 1e-9, "BUY tp = fill + 20*point");

   // SELL: SL acima, TP abaixo.
   MksExecutionResult rs = b.Send(MakeRequest(MKS_ORDER_SELL, 0.1, 10.0, 20.0));
   MksSimPosition ps;
   AssertTrue(b.TryGetPosition(rs.positionId, ps), "sell position exists");
   AssertNearDouble(2000.10, ps.sl, 1e-9, "SELL sl = fill + 10*point");
   AssertNearDouble(1999.80, ps.tp, 1e-9, "SELL tp = fill - 20*point");
}

//+------------------------------------------------------------------+
//| 8. Close full + close partial                                     |
//+------------------------------------------------------------------+
void Test_CloseFullAndPartial()
{
   StartTest("close_full_and_partial");
   CFakeSymbol sym;
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(100.0, 100.0));

   MksExecutionResult open = b.Send(MakeRequest(MKS_ORDER_BUY, 1.0));
   AssertEqualInt(1, b.OpenPositionsCount(), "1 position open");

   // Partial: 0.4 fora
   MksExecutionResult closeP = b.Close(open.positionId, 0.4);
   AssertEqualInt((int)MKS_EXEC_FILLED, (int)closeP.status, "partial close filled");
   AssertNearDouble(0.4, closeP.filledLots, 1e-9, "partial lots");
   AssertEqualInt(1, b.OpenPositionsCount(), "still 1 open after partial");
   MksSimPosition pAfter;
   AssertTrue(b.TryGetPosition(open.positionId, pAfter), "position survives");
   AssertNearDouble(0.6, pAfter.lots, 1e-9, "lots reduced to 0.6");

   // Full: o restante (0.6) fora
   MksExecutionResult closeF = b.Close(open.positionId, 0.6);
   AssertEqualInt((int)MKS_EXEC_FILLED, (int)closeF.status, "full close filled");
   AssertEqualInt(0, b.OpenPositionsCount(), "no positions open");
}

//+------------------------------------------------------------------+
//| 9. Close de positionId inexistente → REJECTED                      |
//+------------------------------------------------------------------+
void Test_CloseInexistent()
{
   StartTest("close_inexistent");
   CFakeSymbol sym;
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(100.0, 100.0));

   MksExecutionResult r = b.Close(999, 0.1);
   AssertEqualInt((int)MKS_EXEC_REJECTED, (int)r.status, "status=REJECTED");
}

//+------------------------------------------------------------------+
//| 10. Modify atualiza SL/TP                                          |
//+------------------------------------------------------------------+
void Test_Modify()
{
   StartTest("modify_sl_tp");
   CFakeSymbol sym;
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(2000.0, 2000.0));

   MksExecutionResult open = b.Send(MakeRequest(MKS_ORDER_BUY, 0.1));
   AssertTrue(b.Modify(open.positionId, 1995.0, 2010.0), "modify ok");

   MksSimPosition p;
   AssertTrue(b.TryGetPosition(open.positionId, p), "position found");
   AssertNearDouble(1995.0, p.sl, 1e-9, "new sl");
   AssertNearDouble(2010.0, p.tp, 1e-9, "new tp");

   AssertFalse(b.Modify(999, 0, 0), "modify inexistent = false");
}

//+------------------------------------------------------------------+
//| 11. Hedging — múltiplos Sends abrem posições distintas             |
//+------------------------------------------------------------------+
void Test_MultipleSendsHedging()
{
   StartTest("multiple_sends_hedging");
   CFakeSymbol sym;
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(100.0, 100.0));

   MksExecutionResult r1 = b.Send(MakeRequest(MKS_ORDER_BUY, 0.1));
   MksExecutionResult r2 = b.Send(MakeRequest(MKS_ORDER_BUY, 0.2));
   MksExecutionResult r3 = b.Send(MakeRequest(MKS_ORDER_SELL, 0.3));

   AssertEqualUlong((ulong)1, r1.positionId, "id1=1");
   AssertEqualUlong((ulong)2, r2.positionId, "id2=2");
   AssertEqualUlong((ulong)3, r3.positionId, "id3=3");
   AssertEqualInt(3, b.OpenPositionsCount(), "3 positions open");

   // IDs de deal também monotonicos.
   AssertEqualUlong((ulong)1, r1.dealId, "deal1=1");
   AssertEqualUlong((ulong)2, r2.dealId, "deal2=2");
   AssertEqualUlong((ulong)3, r3.dealId, "deal3=3");
}

//+------------------------------------------------------------------+
//| 12. Determinismo: dois brokers idênticos → outputs idênticos       |
//+------------------------------------------------------------------+
void Test_Determinism()
{
   StartTest("determinism");
   CFakeSymbol sym;
   CMksCostModel cm(2.0, 1.0, 3.0);
   CMksSimulatedBroker b1(GetPointer(sym), GetPointer(cm));
   CMksSimulatedBroker b2(GetPointer(sym), GetPointer(cm));

   // Sequência: 5 ticks variados + Send + Send + Close
   double bids[] = {100.0, 100.5, 101.0, 100.7, 100.3};
   double asks[] = {100.1, 100.6, 101.1, 100.8, 100.4};
   long   times[] = {1000, 2000, 3000, 4000, 5000};

   for(int i = 0; i < 5; i++)
   {
      MksTick t = MakeTick(bids[i], asks[i], times[i]);
      b1.OnTick(t);
      b2.OnTick(t);
   }

   MksExecutionResult r1a = b1.Send(MakeRequest(MKS_ORDER_BUY, 0.5, 10.0, 15.0));
   MksExecutionResult r2a = b2.Send(MakeRequest(MKS_ORDER_BUY, 0.5, 10.0, 15.0));
   AssertNearDouble(r1a.fillPrice,    r2a.fillPrice,    1e-9, "fillPrice match 1");
   AssertNearDouble(r1a.commission,   r2a.commission,   1e-9, "commission match 1");
   AssertEqualUlong(r1a.positionId,   r2a.positionId,   "positionId match 1");

   MksExecutionResult r1b = b1.Send(MakeRequest(MKS_ORDER_SELL, 0.3));
   MksExecutionResult r2b = b2.Send(MakeRequest(MKS_ORDER_SELL, 0.3));
   AssertNearDouble(r1b.fillPrice, r2b.fillPrice, 1e-9, "fillPrice match 2");

   MksExecutionResult r1c = b1.Close(r1a.positionId, 0.5);
   MksExecutionResult r2c = b2.Close(r2a.positionId, 0.5);
   AssertNearDouble(r1c.fillPrice,  r2c.fillPrice,  1e-9, "close fillPrice match");
   AssertNearDouble(r1c.commission, r2c.commission, 1e-9, "close commission match");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksSimulatedBroker ===");

   Test_NotInitializedNoTick();
   Test_InvalidRequest();
   Test_SendBasicNoCosts();
   Test_SpreadApplied();
   Test_SlippageAdverse();
   Test_CommissionPerLot();
   Test_SlTpComputed();
   Test_CloseFullAndPartial();
   Test_CloseInexistent();
   Test_Modify();
   Test_MultipleSendsHedging();
   Test_Determinism();

   PrintFormat("RESUMO: passed=%d  failed=%d", g_passed, g_failed);
   if(g_failed == 0)
      Print("=== TODOS OS TESTES PASSARAM ===");
   else
      PrintFormat("=== %d TESTES FALHARAM ===", g_failed);
}
//+------------------------------------------------------------------+
