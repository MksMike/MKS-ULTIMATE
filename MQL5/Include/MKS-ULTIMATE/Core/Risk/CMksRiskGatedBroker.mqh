//+------------------------------------------------------------------+
//| @file           : CMksRiskGatedBroker.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Risk
//| @responsibility : Wrapper de IBroker que passa toda MksOrderRequest
//|                   pelo CMksRiskManager antes de delegar ao broker
//|                   subjacente. Send rejeitada retorna ExecutionResult
//|                   com status=REJECTED e brokerRetcode = código do
//|                   Risk Manager. Close/Modify delegam direto — Risk
//|                   só protege a abertura (slice 6.1).
//|                   Lição V5 #7: middleware, não lembrete. ADR-019.
//| @depends_on     : Core/Interfaces/IBroker.mqh,
//|                   Core/Risk/CMksRiskManager.mqh,
//|                   Core/Types/OrderRequest.mqh,
//|                   Core/Types/ExecutionResult.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Risk/CMksRiskGatedBroker.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_RISK_CMKSRISKGATEDBROKER_MQH
#define MKS_ULTIMATE_CORE_RISK_CMKSRISKGATEDBROKER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>
#include <MKS-ULTIMATE/Core/Risk/CMksRiskManager.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

class CMksRiskGatedBroker : public IBroker
{
private:
   IBroker         *m_underlying;
   CMksRiskManager *m_risk;

public:
   // Ambos ponteiros são obrigatórios. Caller mantém ownership.
   CMksRiskGatedBroker(IBroker *underlying, CMksRiskManager *risk)
   {
      m_underlying = underlying;
      m_risk       = risk;
   }

   MksExecutionResult Send(const MksOrderRequest &request) override
   {
      // Sem underlying ou sem risk = configuração inválida. Retorna
      // ERROR para que o caller note a falha de wiring imediatamente.
      if(m_underlying == NULL || m_risk == NULL)
      {
         MksExecutionResult r;
         r.status = MKS_EXEC_ERROR;
         r.brokerRetcode = (int)MKS_ERR_RISK_INVALID_PARAM;
         return r;
      }

      MksError err;
      if(!m_risk.CheckOrder(request, err))
      {
         MksExecutionResult r;
         r.status        = MKS_EXEC_REJECTED;
         r.brokerRetcode = (int)err.code;
         r.requestedPrice = 0.0;
         // Sem fill: positionId, fillPrice, filledLots ficam zero.
         return r;
      }

      return m_underlying.Send(request);
   }

   MksExecutionResult Close(ulong positionId, double lots) override
   {
      if(m_underlying == NULL)
      {
         MksExecutionResult r;
         r.status = MKS_EXEC_ERROR;
         r.brokerRetcode = (int)MKS_ERR_RISK_INVALID_PARAM;
         return r;
      }
      return m_underlying.Close(positionId, lots);
   }

   bool Modify(ulong positionId, double slPrice, double tpPrice) override
   {
      if(m_underlying == NULL) return false;
      return m_underlying.Modify(positionId, slPrice, tpPrice);
   }
};

#endif // MKS_ULTIMATE_CORE_RISK_CMKSRISKGATEDBROKER_MQH
