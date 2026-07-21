//+------------------------------------------------------------------+
//| @file           : Test_CMksTradeJournalingBroker.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksTradeJournalingBroker (ADR-038, fatia 1)
//|                   — decorator IBroker que alimenta o CMksTradeJournal +
//|                   CMksSimAccount só no fill. Cobre: Send FILLED grava
//|                   open; Send REJECTED não grava (mas delega); Close FILLED
//|                   grava closed com PnL correto e delega id/lots; Close
//|                   não-FILLED não grava; conta alimentada no fill; Modify
//|                   delega; inner NULL = erro de wiring sem crash.
//| @depends_on     : Core/Trade/CMksTradeJournalingBroker.mqh,
//|                   Core/Account/CMksSimAccount.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh,
//|                   Core/Types/OrderRequest.mqh,
//|                   Core/Types/ExecutionResult.mqh,
//|                   Core/Interfaces/IBroker.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksTradeJournalingBroker.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Trade/CMksTradeJournalingBroker.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksSimAccount.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>

#define TJB_TOL 1e-6
#define POINT   0.01

//==================================================================
// Stub de IBroker — retorna resultados configuráveis e conta chamadas,
// para exercitar SÓ o decorator (sem acoplar à mecânica de tick do sim).
//==================================================================
class CStubBroker : public IBroker
{
public:
   MksExecutionResult nextSend;    // resultado que Send devolve
   MksExecutionResult nextClose;   // resultado que Close devolve
   bool               modifyRet;
   int                sendCalls;
   int                closeCalls;
   int                modifyCalls;
   MksOrderRequest    lastReq;
   ulong              lastCloseId;
   double             lastCloseLots;

   CStubBroker()
   {
      modifyRet     = true;
      sendCalls     = 0;
      closeCalls    = 0;
      modifyCalls   = 0;
      lastCloseId   = 0;
      lastCloseLots = 0.0;
   }

   MksExecutionResult Send(const MksOrderRequest &request) override
   {
      sendCalls++;
      lastReq = request;
      return nextSend;
   }

   MksExecutionResult Close(ulong positionId, double lots) override
   {
      closeCalls++;
      lastCloseId   = positionId;
      lastCloseLots = lots;
      return nextClose;
   }

   bool Modify(ulong positionId, double slPrice, double tpPrice) override
   {
      modifyCalls++;
      return modifyRet;
   }
};

// Helpers de fixture ------------------------------------------------

MksExecutionResult MakeFilled(ulong id, double lots, double price,
                              long timeMsc, double commission)
{
   MksExecutionResult r;
   r.status      = MKS_EXEC_FILLED;
   r.positionId  = id;
   r.filledLots  = lots;
   r.fillPrice   = price;
   r.execTimeMsc = timeMsc;
   r.commission  = commission;
   return r;
}

MksOrderRequest MakeBuy(double lots)
{
   MksOrderRequest req;
   req.side     = MKS_ORDER_BUY;
   req.lots     = lots;
   req.slPoints = 100.0;
   req.tpPoints = 0.0;
   return req;
}

//==================================================================
// Send
//==================================================================

void Test_TJB_SendFilledRecordsOpen()
{
   CStubBroker stub;
   stub.nextSend = MakeFilled(5, 0.10, 2000.00, 1000, 0.0);
   CMksTradeJournal j(POINT);
   CMksTradeJournalingBroker tjb(GetPointer(stub), GetPointer(j));

   MksOrderRequest buy = MakeBuy(0.10);
   MksExecutionResult r = tjb.Send(buy);

   MKS_ASSERT_TRUE(r.status == MKS_EXEC_FILLED, "repassa o status FILLED do inner");
   MKS_ASSERT_EQ_INT(1, stub.sendCalls,  "delegou ao inner uma vez");
   MKS_ASSERT_EQ_INT(1, j.OpenCount(),   "gravou 1 open no journal");
   MKS_ASSERT_EQ_INT(0, j.ClosedCount(), "nada fechado ainda");
}

void Test_TJB_SendRejectedNotRecorded()
{
   CStubBroker stub;
   stub.nextSend.status = MKS_EXEC_REJECTED;   // gate/broker recusou
   CMksTradeJournal j(POINT);
   CMksTradeJournalingBroker tjb(GetPointer(stub), GetPointer(j));

   MksOrderRequest buy = MakeBuy(0.10);
   MksExecutionResult r = tjb.Send(buy);

   MKS_ASSERT_TRUE(r.status == MKS_EXEC_REJECTED, "repassa o REJECTED");
   MKS_ASSERT_EQ_INT(1, stub.sendCalls, "delegou mesmo em rejeição");
   MKS_ASSERT_EQ_INT(0, j.OpenCount(),  "REJECTED não é trade → nada no journal");
}

//==================================================================
// Close
//==================================================================

void Test_TJB_CloseFilledRecordsClosedWithPnL()
{
   CStubBroker stub;
   stub.nextSend  = MakeFilled(5, 0.10, 2000.00, 1000, 0.0);
   stub.nextClose = MakeFilled(5, 0.10, 2003.00, 2000, 0.0);
   CMksTradeJournal j(POINT);
   CMksTradeJournalingBroker tjb(GetPointer(stub), GetPointer(j));

   MksOrderRequest buy = MakeBuy(0.10);
   tjb.Send(buy);
   MksExecutionResult c = tjb.Close(5, 0.10);

   MKS_ASSERT_TRUE(c.status == MKS_EXEC_FILLED, "repassa o Close FILLED");
   MKS_ASSERT_EQ_INT(1, stub.closeCalls,        "delegou o Close");
   MKS_ASSERT_EQ_LONG(5, (long)stub.lastCloseId,       "id repassado ao inner");
   MKS_ASSERT_NEAR_DOUBLE(0.10, stub.lastCloseLots, TJB_TOL, "lots repassados ao inner");
   MKS_ASSERT_EQ_INT(0, j.OpenCount(),          "open moveu p/ closed");
   MKS_ASSERT_EQ_INT(1, j.ClosedCount(),        "1 trade fechado");
   // BUY 2000 -> 2003, point 0.01 => +300 pontos
   MKS_ASSERT_NEAR_DOUBLE(300.0, j.ClosedAt(0).pnlPoints, TJB_TOL, "PnL BUY +300pts");
}

void Test_TJB_CloseNonFilledNotRecorded()
{
   CStubBroker stub;
   stub.nextSend        = MakeFilled(5, 0.10, 2000.00, 1000, 0.0);
   stub.nextClose.status = MKS_EXEC_ERROR;     // falha de comunicação no close
   CMksTradeJournal j(POINT);
   CMksTradeJournalingBroker tjb(GetPointer(stub), GetPointer(j));

   MksOrderRequest buy = MakeBuy(0.10);
   tjb.Send(buy);
   tjb.Close(5, 0.10);

   MKS_ASSERT_EQ_INT(1, stub.closeCalls, "delegou o Close (mesmo falho)");
   MKS_ASSERT_EQ_INT(1, j.OpenCount(),   "close falho NÃO fecha o trade");
   MKS_ASSERT_EQ_INT(0, j.ClosedCount(), "nada movido p/ closed");
}

//==================================================================
// Conta alimentada no fill
//==================================================================

void Test_TJB_AccountFedOnFill()
{
   CStubBroker stub;
   stub.nextSend  = MakeFilled(5, 0.10, 2000.00, 1000, 0.0);
   stub.nextClose = MakeFilled(5, 0.10, 2003.00, 2000, 0.0);
   CMksFakeSymbol sym;                          // tickSize=0.01, tickValue=1.0
   CMksSimAccount acc(GetPointer(sym), 10000.0);
   CMksTradeJournal j(POINT);
   CMksTradeJournalingBroker tjb(GetPointer(stub), GetPointer(j), GetPointer(acc));

   MksOrderRequest buy = MakeBuy(0.10);
   tjb.Send(buy);
   MKS_ASSERT_NEAR_DOUBLE(10000.0, acc.Balance(), TJB_TOL, "abrir não mexe no balance");
   MKS_ASSERT_EQ_INT(1, acc.OpenCount(), "conta viu a abertura (OnOpen)");

   tjb.Close(5, 0.10);
   // BUY 2000->2003, 0.1 lot => +3*100*0.1 = +30 realizado
   MKS_ASSERT_NEAR_DOUBLE(10030.0, acc.Balance(), TJB_TOL, "close realiza +30 (OnClose)");
   MKS_ASSERT_EQ_INT(0, acc.OpenCount(), "posição fechada na conta");
}

void Test_TJB_NoAccountIsFineNull()
{
   CStubBroker stub;
   stub.nextSend  = MakeFilled(5, 0.10, 2000.00, 1000, 0.0);
   CMksTradeJournal j(POINT);
   CMksTradeJournalingBroker tjb(GetPointer(stub), GetPointer(j)); // account=NULL

   MksOrderRequest buy = MakeBuy(0.10);
   MksExecutionResult r = tjb.Send(buy);
   MKS_ASSERT_TRUE(r.status == MKS_EXEC_FILLED, "sem conta o fill segue normal");
   MKS_ASSERT_EQ_INT(1, j.OpenCount(),          "journal alimentado mesmo sem conta");
}

//==================================================================
// Modify e wiring
//==================================================================

void Test_TJB_ModifyDelegates()
{
   CStubBroker stub;
   stub.modifyRet = true;
   CMksTradeJournal j(POINT);
   CMksTradeJournalingBroker tjb(GetPointer(stub), GetPointer(j));

   bool ok = tjb.Modify(5, 1990.0, 0.0);
   MKS_ASSERT_TRUE(ok,                   "Modify repassa o retorno do inner");
   MKS_ASSERT_EQ_INT(1, stub.modifyCalls, "Modify delegou ao inner");
}

void Test_TJB_NullInnerWiringError()
{
   CMksTradeJournal j(POINT);
   CMksTradeJournalingBroker tjb(NULL, GetPointer(j)); // inner ausente

   MksOrderRequest buy = MakeBuy(0.10);
   MksExecutionResult r = tjb.Send(buy);
   MKS_ASSERT_TRUE(r.status == MKS_EXEC_ERROR, "inner NULL → erro de wiring, sem crash");
   MKS_ASSERT_EQ_INT(0, j.OpenCount(),         "nada gravado sob wiring inválido");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksTradeJournalingBroker ===");

   MKS_RUN(Test_TJB_SendFilledRecordsOpen);
   MKS_RUN(Test_TJB_SendRejectedNotRecorded);

   MKS_RUN(Test_TJB_CloseFilledRecordsClosedWithPnL);
   MKS_RUN(Test_TJB_CloseNonFilledNotRecorded);

   MKS_RUN(Test_TJB_AccountFedOnFill);
   MKS_RUN(Test_TJB_NoAccountIsFineNull);

   MKS_RUN(Test_TJB_ModifyDelegates);
   MKS_RUN(Test_TJB_NullInnerWiringError);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
