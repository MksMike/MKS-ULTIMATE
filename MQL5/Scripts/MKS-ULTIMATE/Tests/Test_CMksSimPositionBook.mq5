//+------------------------------------------------------------------+
//| @file           : Test_CMksSimPositionBook.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksSimPositionBook e do CMksFeedClock
//|                   (E2.0). O book espelha o CMksSimulatedBroker:
//|                   IsOpen reflete posição aberta; IsOpen(desconhecido)
//|                   = false (semântica do book REAL, NÃO a inversão do
//|                   mock); auto-close de SL torna IsOpen=false;
//|                   OpenCount/TotalLots/PositionAt enumeram. FeedClock:
//|                   NowMsc reflete o alimentado, IsReady só após ≥1.
//| @depends_on     : Core/Position/CMksSimPositionBook.mqh,
//|                   Core/Clock/CMksFeedClock.mqh,
//|                   Core/Broker/CMksSimulatedBroker.mqh,
//|                   Core/Broker/CMksCostModel.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksSimPositionBook.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Position/CMksSimPositionBook.mqh>
#include <MKS-ULTIMATE/Core/Clock/CMksFeedClock.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksCostModel.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>

#define SPB_TOL 1e-9

MksTick MakeTick(double bid, double ask, long timeMsc, ulong seq)
{
   MksTick t;
   t.seq = seq; t.timeMsc = timeMsc; t.bid = bid; t.ask = ask;
   t.last = 0; t.volume = 0; t.flags = 0;
   return t;
}

MksOrderRequest MakeReq(ENUM_MKS_ORDER_SIDE side, double lots, double slPoints)
{
   MksOrderRequest r;
   r.side = side; r.lots = lots; r.slPoints = slPoints; r.tpPoints = 0.0;
   r.comment = "test";
   return r;
}

//==================================================================
// CMksFeedClock
//==================================================================

void Test_FeedClock_ReflectsFedTime()
{
   CMksFeedClock clk;
   MKS_ASSERT_FALSE(clk.IsReady(), "clock virgem não está pronto");
   MKS_ASSERT_EQ_LONG(0, clk.NowMsc(), "NowMsc=0 virgem");
   clk.SetNow(1779797744000);
   MKS_ASSERT_TRUE(clk.IsReady(), "pronto após 1º SetNow");
   MKS_ASSERT_EQ_LONG(1779797744000, clk.NowMsc(), "NowMsc reflete o alimentado");
   clk.SetNow(1779797745000);
   MKS_ASSERT_EQ_LONG(1779797745000, clk.NowMsc(), "NowMsc avança");
}

//==================================================================
// CMksSimPositionBook
//==================================================================

void Test_SPB_ReflectsOpenPosition()
{
   CMksFakeSymbol sym; sym.SetPoint(1.0);
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   CMksSimPositionBook book(GetPointer(b));
   b.OnTick(MakeTick(2000.0, 2000.0, 1000, 1));

   MksExecutionResult open = b.Send(MakeReq(MKS_ORDER_BUY, 0.1, 10.0)); // SL 1990
   MKS_ASSERT_TRUE(book.IsOpen(open.positionId), "book vê a posição aberta");
   MKS_ASSERT_EQ_INT(1, book.OpenCount(), "OpenCount=1");
   MKS_ASSERT_NEAR_DOUBLE(0.1, book.TotalLots(), SPB_TOL, "TotalLots=0.1");
}

void Test_SPB_IsOpenUnknownIsFalse()
{
   CMksFakeSymbol sym; sym.SetPoint(1.0);
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   CMksSimPositionBook book(GetPointer(b));
   b.OnTick(MakeTick(2000.0, 2000.0, 1000, 1));
   b.Send(MakeReq(MKS_ORDER_BUY, 0.1, 10.0));

   // O ponto crítico: id desconhecido => false (book REAL), NÃO true
   // (inversão do mock CMksFakePositionBook). Sem isso o auto-detach
   // mentiria.
   MKS_ASSERT_FALSE(book.IsOpen(999999), "id desconhecido => IsOpen=false");
}

void Test_SPB_PositionAtEnumerates()
{
   CMksFakeSymbol sym; sym.SetPoint(1.0);
   CMksCostModel cm;
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   CMksSimPositionBook book(GetPointer(b));
   b.OnTick(MakeTick(2000.0, 2000.0, 1000, 1));
   MksExecutionResult open = b.Send(MakeReq(MKS_ORDER_SELL, 0.2, 10.0));

   ulong id = 0; ENUM_MKS_ORDER_SIDE side = MKS_ORDER_BUY; double lots = 0.0;
   MKS_ASSERT_TRUE(book.PositionAt(0, id, side, lots), "PositionAt(0) ok");
   MKS_ASSERT_EQ_ULONG(open.positionId, id, "id enumerado bate");
   MKS_ASSERT_EQ_INT((int)MKS_ORDER_SELL, (int)side, "side=SELL");
   MKS_ASSERT_NEAR_DOUBLE(0.2, lots, SPB_TOL, "lots=0.2");
   MKS_ASSERT_FALSE(book.PositionAt(1, id, side, lots), "índice fora do range => false");
}

void Test_SPB_AutoCloseMakesIsOpenFalse()
{
   CMksFakeSymbol sym; sym.SetPoint(1.0);
   CMksCostModel cm; // sem custos: bidProxy = mid
   CMksSimulatedBroker b(GetPointer(sym), GetPointer(cm));
   CMksSimPositionBook book(GetPointer(b));
   b.OnTick(MakeTick(2000.0, 2000.0, 1000, 1));
   MksExecutionResult open = b.Send(MakeReq(MKS_ORDER_BUY, 0.1, 10.0)); // SL 1990
   MKS_ASSERT_TRUE(book.IsOpen(open.positionId), "aberta antes do SL");

   // Tick que cruza o SL (bidProxy=1989 <= 1990) → auto-close no sim.
   b.OnTick(MakeTick(1989.0, 1989.0, 2000, 2));
   MKS_ASSERT_FALSE(book.IsOpen(open.positionId), "auto-close de SL → IsOpen=false");
   MKS_ASSERT_EQ_INT(0, book.OpenCount(), "OpenCount=0 pós auto-close");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksSimPositionBook ===");

   MKS_RUN(Test_FeedClock_ReflectsFedTime);

   MKS_RUN(Test_SPB_ReflectsOpenPosition);
   MKS_RUN(Test_SPB_IsOpenUnknownIsFalse);
   MKS_RUN(Test_SPB_PositionAtEnumerates);
   MKS_RUN(Test_SPB_AutoCloseMakesIsOpenFalse);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
