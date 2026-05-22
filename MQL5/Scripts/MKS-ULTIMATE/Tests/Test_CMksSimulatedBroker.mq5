//+------------------------------------------------------------------+
//| @file           : Test_CMksSimulatedBroker.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksSimulatedBroker — initialization,
//|                   Send (custos, SL/TP), Close (full/partial),
//|                   Modify, hedging, determinismo. ADR-017.
//|                   Migrado para o framework Core/Testing (ADR-005).
//| @depends_on     : Core/Broker/CMksSimulatedBroker.mqh,
//|                   Core/Broker/CMksCostModel.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh,
//|                   Core/Types/*
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksSimulatedBroker.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Broker/CMksSimulatedBroker.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksCostModel.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//+------------------------------------------------------------------+
//| Helpers: construtores de dados de teste (não são mocks)            |
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
   CMksFakeSymbol sym;
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));

   MksOrderRequest req = MakeRequest(MKS_ORDER_BUY, 0.1);
   MksExecutionResult r = b.Send(req);
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_ERROR, (int)r.status, "status=ERROR");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_BROKER_NOT_INITIALIZED,
                     r.brokerRetcode, "retcode=NOT_INITIALIZED");
}

//+------------------------------------------------------------------+
//| 2. Send com request inválido → REJECTED                            |
//+------------------------------------------------------------------+
void Test_InvalidRequest()
{
   CMksFakeSymbol sym;
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(100.0, 100.0));

   MksOrderRequest req = MakeRequest(MKS_ORDER_BUY, 0.0); // lots inválido
   MksExecutionResult r = b.Send(req);
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_REJECTED, (int)r.status, "status=REJECTED");
}

//+------------------------------------------------------------------+
//| 3. Send básico sem custos → fillPrice = mid                       |
//+------------------------------------------------------------------+
void Test_SendBasicNoCosts()
{
   CMksFakeSymbol sym;
   CMksCostModel cm; // zero custos
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(2000.0, 2000.0, 12345));

   MksOrderRequest req = MakeRequest(MKS_ORDER_BUY, 0.1);
   MksExecutionResult r = b.Send(req);

   MKS_ASSERT_EQ_INT((int)MKS_EXEC_FILLED, (int)r.status, "status=FILLED");
   MKS_ASSERT_NEAR_DOUBLE(2000.0, r.fillPrice,      1e-9, "fillPrice = mid");
   MKS_ASSERT_NEAR_DOUBLE(2000.0, r.requestedPrice, 1e-9, "requestedPrice = mid");
   MKS_ASSERT_NEAR_DOUBLE(0.1,    r.filledLots,     1e-9, "lots");
   MKS_ASSERT_NEAR_DOUBLE(0.0,    r.commission,     1e-9, "commission = 0");
   MKS_ASSERT_NEAR_DOUBLE(0.0,    r.swap,           1e-9, "swap = 0");
   MKS_ASSERT_EQ_ULONG((ulong)1,  r.positionId,           "positionId = 1");
   MKS_ASSERT_EQ_ULONG((ulong)1,  r.dealId,               "dealId = 1");
   MKS_ASSERT_EQ_INT(1,           r.attempts,             "attempts = 1");
   MKS_ASSERT_EQ_LONG((long)12345, r.execTimeMsc,         "execTimeMsc");
}

//+------------------------------------------------------------------+
//| 4. Spread aplicado simetricamente nos dois lados                   |
//+------------------------------------------------------------------+
void Test_SpreadApplied()
{
   CMksFakeSymbol sym;
   // spread=2 points; point=0.01 → halfSpread = 0.01
   CMksCostModel cm(2.0, 0.0, 0.0);
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(2000.0, 2000.0));

   MksExecutionResult rb = b.Send(MakeRequest(MKS_ORDER_BUY, 0.1));
   MKS_ASSERT_NEAR_DOUBLE(2000.01, rb.fillPrice, 1e-9, "BUY fill = mid + halfSpread");

   MksExecutionResult rs = b.Send(MakeRequest(MKS_ORDER_SELL, 0.1));
   MKS_ASSERT_NEAR_DOUBLE(1999.99, rs.fillPrice, 1e-9, "SELL fill = mid - halfSpread");
}

//+------------------------------------------------------------------+
//| 5. Slippage adverso aplicado                                       |
//+------------------------------------------------------------------+
void Test_SlippageAdverse()
{
   CMksFakeSymbol sym;
   // sem spread, slippage=3 points
   CMksCostModel cm(0.0, 3.0, 0.0);
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(2000.0, 2000.0));

   MksExecutionResult rb = b.Send(MakeRequest(MKS_ORDER_BUY, 0.1));
   MKS_ASSERT_NEAR_DOUBLE(2000.03, rb.fillPrice, 1e-9, "BUY pays mid + slip");

   MksExecutionResult rs = b.Send(MakeRequest(MKS_ORDER_SELL, 0.1));
   MKS_ASSERT_NEAR_DOUBLE(1999.97, rs.fillPrice, 1e-9, "SELL receives mid - slip");
}

//+------------------------------------------------------------------+
//| 6. Comissão por lote                                              |
//+------------------------------------------------------------------+
void Test_CommissionPerLot()
{
   CMksFakeSymbol sym;
   CMksCostModel cm(0.0, 0.0, 5.0); // $5 por lote
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(100.0, 100.0));

   MksExecutionResult r = b.Send(MakeRequest(MKS_ORDER_BUY, 0.5));
   MKS_ASSERT_NEAR_DOUBLE(2.5, r.commission, 1e-9, "commission = 5 * 0.5");
}

//+------------------------------------------------------------------+
//| 7. SL/TP computados em preço absoluto                              |
//+------------------------------------------------------------------+
void Test_SlTpComputed()
{
   CMksFakeSymbol sym;
   CMksCostModel cm; // sem custos
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(2000.0, 2000.0));

   // BUY: SL abaixo, TP acima.
   MksExecutionResult rb = b.Send(MakeRequest(MKS_ORDER_BUY, 0.1, 10.0, 20.0));
   MksSimPosition pb;
   MKS_ASSERT_TRUE(b.TryGetPosition(rb.positionId, pb), "buy position exists");
   MKS_ASSERT_NEAR_DOUBLE(1999.90, pb.sl, 1e-9, "BUY sl = fill - 10*point");
   MKS_ASSERT_NEAR_DOUBLE(2000.20, pb.tp, 1e-9, "BUY tp = fill + 20*point");

   // SELL: SL acima, TP abaixo.
   MksExecutionResult rs = b.Send(MakeRequest(MKS_ORDER_SELL, 0.1, 10.0, 20.0));
   MksSimPosition ps;
   MKS_ASSERT_TRUE(b.TryGetPosition(rs.positionId, ps), "sell position exists");
   MKS_ASSERT_NEAR_DOUBLE(2000.10, ps.sl, 1e-9, "SELL sl = fill + 10*point");
   MKS_ASSERT_NEAR_DOUBLE(1999.80, ps.tp, 1e-9, "SELL tp = fill - 20*point");
}

//+------------------------------------------------------------------+
//| 8. Close full + close partial                                     |
//+------------------------------------------------------------------+
void Test_CloseFullAndPartial()
{
   CMksFakeSymbol sym;
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(100.0, 100.0));

   MksExecutionResult open = b.Send(MakeRequest(MKS_ORDER_BUY, 1.0));
   MKS_ASSERT_EQ_INT(1, b.OpenPositionsCount(), "1 position open");

   // Partial: 0.4 fora
   MksExecutionResult closeP = b.Close(open.positionId, 0.4);
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_FILLED, (int)closeP.status, "partial close filled");
   MKS_ASSERT_NEAR_DOUBLE(0.4, closeP.filledLots, 1e-9, "partial lots");
   MKS_ASSERT_EQ_INT(1, b.OpenPositionsCount(), "still 1 open after partial");
   MksSimPosition pAfter;
   MKS_ASSERT_TRUE(b.TryGetPosition(open.positionId, pAfter), "position survives");
   MKS_ASSERT_NEAR_DOUBLE(0.6, pAfter.lots, 1e-9, "lots reduced to 0.6");

   // Full: o restante (0.6) fora
   MksExecutionResult closeF = b.Close(open.positionId, 0.6);
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_FILLED, (int)closeF.status, "full close filled");
   MKS_ASSERT_EQ_INT(0, b.OpenPositionsCount(), "no positions open");
}

//+------------------------------------------------------------------+
//| 9. Close de positionId inexistente → REJECTED                      |
//+------------------------------------------------------------------+
void Test_CloseInexistent()
{
   CMksFakeSymbol sym;
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(100.0, 100.0));

   MksExecutionResult r = b.Close(999, 0.1);
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_REJECTED, (int)r.status, "status=REJECTED");
}

//+------------------------------------------------------------------+
//| 10. Modify atualiza SL/TP                                          |
//+------------------------------------------------------------------+
void Test_Modify()
{
   CMksFakeSymbol sym;
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(2000.0, 2000.0));

   MksExecutionResult open = b.Send(MakeRequest(MKS_ORDER_BUY, 0.1));
   MKS_ASSERT_TRUE(b.Modify(open.positionId, 1995.0, 2010.0), "modify ok");

   MksSimPosition p;
   MKS_ASSERT_TRUE(b.TryGetPosition(open.positionId, p), "position found");
   MKS_ASSERT_NEAR_DOUBLE(1995.0, p.sl, 1e-9, "new sl");
   MKS_ASSERT_NEAR_DOUBLE(2010.0, p.tp, 1e-9, "new tp");

   MKS_ASSERT_FALSE(b.Modify(999, 0, 0), "modify inexistent = false");
}

//+------------------------------------------------------------------+
//| 11. Hedging — múltiplos Sends abrem posições distintas             |
//+------------------------------------------------------------------+
void Test_MultipleSendsHedging()
{
   CMksFakeSymbol sym;
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   b.OnTick(MakeTick(100.0, 100.0));

   MksExecutionResult r1 = b.Send(MakeRequest(MKS_ORDER_BUY, 0.1));
   MksExecutionResult r2 = b.Send(MakeRequest(MKS_ORDER_BUY, 0.2));
   MksExecutionResult r3 = b.Send(MakeRequest(MKS_ORDER_SELL, 0.3));

   MKS_ASSERT_EQ_ULONG((ulong)1, r1.positionId, "id1=1");
   MKS_ASSERT_EQ_ULONG((ulong)2, r2.positionId, "id2=2");
   MKS_ASSERT_EQ_ULONG((ulong)3, r3.positionId, "id3=3");
   MKS_ASSERT_EQ_INT(3, b.OpenPositionsCount(), "3 positions open");

   // IDs de deal também monotônicos.
   MKS_ASSERT_EQ_ULONG((ulong)1, r1.dealId, "deal1=1");
   MKS_ASSERT_EQ_ULONG((ulong)2, r2.dealId, "deal2=2");
   MKS_ASSERT_EQ_ULONG((ulong)3, r3.dealId, "deal3=3");
}

//+------------------------------------------------------------------+
//| 12. Determinismo: dois brokers idênticos → outputs idênticos       |
//+------------------------------------------------------------------+
void Test_Determinism()
{
   CMksFakeSymbol sym;
   CMksCostModel cm(2.0, 1.0, 3.0);
   CMksSimulatedBroker b1(GetPointer(sym), GetPointer(cm));
   CMksSimulatedBroker b2(GetPointer(sym), GetPointer(cm));

   // Sequência: 5 ticks variados + Send + Send + Close
   double bids[]  = {100.0, 100.5, 101.0, 100.7, 100.3};
   double asks[]  = {100.1, 100.6, 101.1, 100.8, 100.4};
   long   times[] = {1000, 2000, 3000, 4000, 5000};

   for(int i = 0; i < 5; i++)
   {
      MksTick t = MakeTick(bids[i], asks[i], times[i]);
      b1.OnTick(t);
      b2.OnTick(t);
   }

   MksExecutionResult r1a = b1.Send(MakeRequest(MKS_ORDER_BUY, 0.5, 10.0, 15.0));
   MksExecutionResult r2a = b2.Send(MakeRequest(MKS_ORDER_BUY, 0.5, 10.0, 15.0));
   MKS_ASSERT_NEAR_DOUBLE(r1a.fillPrice,    r2a.fillPrice,    1e-9, "fillPrice match 1");
   MKS_ASSERT_NEAR_DOUBLE(r1a.commission,   r2a.commission,   1e-9, "commission match 1");
   MKS_ASSERT_EQ_ULONG(r1a.positionId,      r2a.positionId,         "positionId match 1");

   MksExecutionResult r1b = b1.Send(MakeRequest(MKS_ORDER_SELL, 0.3));
   MksExecutionResult r2b = b2.Send(MakeRequest(MKS_ORDER_SELL, 0.3));
   MKS_ASSERT_NEAR_DOUBLE(r1b.fillPrice, r2b.fillPrice, 1e-9, "fillPrice match 2");

   MksExecutionResult r1c = b1.Close(r1a.positionId, 0.5);
   MksExecutionResult r2c = b2.Close(r2a.positionId, 0.5);
   MKS_ASSERT_NEAR_DOUBLE(r1c.fillPrice,  r2c.fillPrice,  1e-9, "close fillPrice match");
   MKS_ASSERT_NEAR_DOUBLE(r1c.commission, r2c.commission, 1e-9, "close commission match");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksSimulatedBroker ===");

   MKS_RUN(Test_NotInitializedNoTick);
   MKS_RUN(Test_InvalidRequest);
   MKS_RUN(Test_SendBasicNoCosts);
   MKS_RUN(Test_SpreadApplied);
   MKS_RUN(Test_SlippageAdverse);
   MKS_RUN(Test_CommissionPerLot);
   MKS_RUN(Test_SlTpComputed);
   MKS_RUN(Test_CloseFullAndPartial);
   MKS_RUN(Test_CloseInexistent);
   MKS_RUN(Test_Modify);
   MKS_RUN(Test_MultipleSendsHedging);
   MKS_RUN(Test_Determinism);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
