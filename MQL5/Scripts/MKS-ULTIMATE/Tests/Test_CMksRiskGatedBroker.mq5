//+------------------------------------------------------------------+
//| @file           : Test_CMksRiskGatedBroker.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksRiskGatedBroker — wrapper IBroker
//|                   que passa Send pelo CMksRiskManager. Verifica:
//|                   (a) Send delegado quando risk aprova; (b) Send
//|                   rejeitada quando risk reprova (sem chamar
//|                   underlying); (c) Close/Modify delegam direto.
//|                   ADR-019, lição V5 #7.
//| @depends_on     : Core/Risk/CMksRiskGatedBroker.mqh,
//|                   Core/Risk/CMksRiskManager.mqh,
//|                   Core/Testing/Asserts.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksRiskGatedBroker.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Risk/CMksRiskGatedBroker.mqh>
#include <MKS-ULTIMATE/Core/Risk/CMksRiskManager.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//+------------------------------------------------------------------+
//| Mock broker: conta chamadas e retorna ExecutionResult configurável|
//+------------------------------------------------------------------+
class CMockBroker : public IBroker
{
private:
   int m_sendCalls;
   int m_closeCalls;
   int m_modifyCalls;
   MksExecutionResult m_sendResult;
   MksExecutionResult m_closeResult;
   bool m_modifyReturn;

public:
   CMockBroker()
   {
      m_sendCalls   = 0;
      m_closeCalls  = 0;
      m_modifyCalls = 0;
      m_sendResult.status     = MKS_EXEC_FILLED;
      m_sendResult.positionId = 9999;
      m_sendResult.fillPrice  = 100.0;
      m_sendResult.filledLots = 1.0;
      m_closeResult.status    = MKS_EXEC_FILLED;
      m_modifyReturn = true;
   }

   MksExecutionResult Send(const MksOrderRequest &req) override
   {
      m_sendCalls++;
      return m_sendResult;
   }

   MksExecutionResult Close(ulong positionId, double lots) override
   {
      m_closeCalls++;
      return m_closeResult;
   }

   bool Modify(ulong positionId, double slPrice, double tpPrice) override
   {
      m_modifyCalls++;
      return m_modifyReturn;
   }

   int  SendCalls()   const { return m_sendCalls; }
   int  CloseCalls()  const { return m_closeCalls; }
   int  ModifyCalls() const { return m_modifyCalls; }
   void SetSendResult(const MksExecutionResult &r) { m_sendResult = r; }
};

//+------------------------------------------------------------------+
MksOrderRequest MakeReq(double lots, double slPoints, double tpPoints = 0.0)
{
   MksOrderRequest r;
   r.side     = MKS_ORDER_BUY;
   r.lots     = lots;
   r.slPoints = slPoints;
   r.tpPoints = tpPoints;
   r.comment  = "test";
   return r;
}

//==================================================================
// Send — wiring NULL
//==================================================================

void Test_Gated_Send_NullUnderlying()
{
   CMksRiskTradeParams p;
   CMksRiskManager risk(p);
   CMksRiskGatedBroker gated(NULL, GetPointer(risk));
   MksExecutionResult r = gated.Send(MakeReq(0.1, 100.0));
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_ERROR, (int)r.status, "status=ERROR");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_INVALID_PARAM,
                     r.brokerRetcode, "retcode=INVALID_PARAM");
}

void Test_Gated_Send_NullRisk()
{
   CMockBroker broker;
   CMksRiskGatedBroker gated(GetPointer(broker), NULL);
   MksExecutionResult r = gated.Send(MakeReq(0.1, 100.0));
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_ERROR, (int)r.status, "status=ERROR");
   MKS_ASSERT_EQ_INT(0, broker.SendCalls(),
                     "underlying nunca foi chamado");
}

//==================================================================
// Send — Risk reprova → underlying não é chamado
//==================================================================

void Test_Gated_Send_RiskRejects_SlMissing()
{
   CMockBroker broker;
   CMksRiskTradeParams p; // requireSl=true
   CMksRiskManager risk(p);
   CMksRiskGatedBroker gated(GetPointer(broker), GetPointer(risk));

   MksExecutionResult r = gated.Send(MakeReq(0.1, 0.0));
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_REJECTED, (int)r.status,
                     "status=REJECTED");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_SL_MISSING,
                     r.brokerRetcode, "retcode=SL_MISSING");
   MKS_ASSERT_EQ_INT(0, broker.SendCalls(),
                     "underlying não chamado em rejeição");
}

void Test_Gated_Send_RiskRejects_LotsExceeded()
{
   CMockBroker broker;
   CMksRiskTradeParams p;
   p.maxLotsPerTrade = 0.5;
   CMksRiskManager risk(p);
   CMksRiskGatedBroker gated(GetPointer(broker), GetPointer(risk));

   MksExecutionResult r = gated.Send(MakeReq(2.0, 100.0));
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_REJECTED, (int)r.status, "REJECTED");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_LOTS_EXCEEDED,
                     r.brokerRetcode, "retcode=LOTS_EXCEEDED");
   MKS_ASSERT_EQ_INT(0, broker.SendCalls(), "underlying não chamado");
}

//==================================================================
// Send — Risk aprova → delega e retorna resultado do underlying
//==================================================================

void Test_Gated_Send_RiskApproves_DelegatesAndReturns()
{
   CMockBroker broker;
   CMksRiskTradeParams p;
   CMksRiskManager risk(p);
   CMksRiskGatedBroker gated(GetPointer(broker), GetPointer(risk));

   MksExecutionResult r = gated.Send(MakeReq(0.1, 100.0));
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_FILLED, (int)r.status,
                     "status=FILLED (vindo do mock)");
   MKS_ASSERT_EQ_ULONG(9999, r.positionId,
                       "positionId=9999 do mock");
   MKS_ASSERT_NEAR_DOUBLE(100.0, r.fillPrice, 1e-9,
                          "fillPrice=100.0 do mock");
   MKS_ASSERT_EQ_INT(1, broker.SendCalls(),
                     "underlying chamado uma vez");
}

//==================================================================
// Send — Risk aprova mas underlying retorna ERROR — passa adiante
//==================================================================

void Test_Gated_Send_UnderlyingError_Propagated()
{
   CMockBroker broker;
   MksExecutionResult brokerErr;
   brokerErr.status        = MKS_EXEC_ERROR;
   brokerErr.brokerRetcode = 200; // broker timeout (ADR-017)
   broker.SetSendResult(brokerErr);

   CMksRiskTradeParams p;
   CMksRiskManager risk(p);
   CMksRiskGatedBroker gated(GetPointer(broker), GetPointer(risk));

   MksExecutionResult r = gated.Send(MakeReq(0.1, 100.0));
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_ERROR, (int)r.status,
                     "ERROR do underlying preservado");
   MKS_ASSERT_EQ_INT(200, r.brokerRetcode, "retcode preservado");
   MKS_ASSERT_EQ_INT(1, broker.SendCalls(), "underlying chamado");
}

//==================================================================
// Close / Modify — delegam direto, sem passar por Risk
//==================================================================

void Test_Gated_Close_DelegatesDirectly()
{
   CMockBroker broker;
   CMksRiskTradeParams p;
   CMksRiskManager risk(p);
   CMksRiskGatedBroker gated(GetPointer(broker), GetPointer(risk));

   MksExecutionResult r = gated.Close(1234, 0.1);
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_FILLED, (int)r.status,
                     "Close delega direto, retorna FILLED do mock");
   MKS_ASSERT_EQ_INT(1, broker.CloseCalls(),
                     "underlying.Close chamado");
}

void Test_Gated_Modify_DelegatesDirectly()
{
   CMockBroker broker;
   CMksRiskTradeParams p;
   CMksRiskManager risk(p);
   CMksRiskGatedBroker gated(GetPointer(broker), GetPointer(risk));

   bool ok = gated.Modify(1234, 99.5, 101.0);
   MKS_ASSERT_TRUE(ok, "Modify retorna true do mock");
   MKS_ASSERT_EQ_INT(1, broker.ModifyCalls(),
                     "underlying.Modify chamado");
}

void Test_Gated_Close_NullUnderlying()
{
   CMksRiskTradeParams p;
   CMksRiskManager risk(p);
   CMksRiskGatedBroker gated(NULL, GetPointer(risk));

   MksExecutionResult r = gated.Close(1234, 0.1);
   MKS_ASSERT_EQ_INT((int)MKS_EXEC_ERROR, (int)r.status,
                     "Close com underlying=NULL retorna ERROR");
}

void Test_Gated_Modify_NullUnderlying()
{
   CMksRiskTradeParams p;
   CMksRiskManager risk(p);
   CMksRiskGatedBroker gated(NULL, GetPointer(risk));

   bool ok = gated.Modify(1234, 99.5, 101.0);
   MKS_ASSERT_FALSE(ok, "Modify com underlying=NULL retorna false");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksRiskGatedBroker ===");

   MKS_RUN(Test_Gated_Send_NullUnderlying);
   MKS_RUN(Test_Gated_Send_NullRisk);
   MKS_RUN(Test_Gated_Send_RiskRejects_SlMissing);
   MKS_RUN(Test_Gated_Send_RiskRejects_LotsExceeded);
   MKS_RUN(Test_Gated_Send_RiskApproves_DelegatesAndReturns);
   MKS_RUN(Test_Gated_Send_UnderlyingError_Propagated);
   MKS_RUN(Test_Gated_Close_DelegatesDirectly);
   MKS_RUN(Test_Gated_Modify_DelegatesDirectly);
   MKS_RUN(Test_Gated_Close_NullUnderlying);
   MKS_RUN(Test_Gated_Modify_NullUnderlying);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
