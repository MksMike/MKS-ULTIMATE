//+------------------------------------------------------------------+
//| @file           : CMksRecordingBroker.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Testing / Mocks
//| @responsibility : Mock de IBroker que registra cada chamada de
//|                   Send/Close/Modify em arrays internos para
//|                   inspeção em testes. Send retorna FILLED por
//|                   default; comportamento configurável via setters.
//|                   Ver ADR-005.
//| @depends_on     : Core/Interfaces/IBroker.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Testing/Mocks/CMksRecordingBroker.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TESTING_MOCKS_RECORDINGBROKER_MQH
#define MKS_ULTIMATE_CORE_TESTING_MOCKS_RECORDINGBROKER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>

// Registro de uma chamada Modify(positionId, slPrice, tpPrice).
struct MksModifyCall
{
   ulong  positionId;
   double slPrice;
   double tpPrice;
};

// Registro de uma chamada Close(positionId, lots).
struct MksCloseCall
{
   ulong  positionId;
   double lots;
};

class CMksRecordingBroker : public IBroker
{
private:
   MksModifyCall m_modifies[];
   MksCloseCall  m_closes[];
   int m_sendCount;

   // Configuração de retorno
   bool m_nextModifyReturns;
   ENUM_MKS_EXEC_STATUS m_nextCloseStatus;

public:
   CMksRecordingBroker()
   {
      m_sendCount = 0;
      m_nextModifyReturns = true;
      m_nextCloseStatus   = MKS_EXEC_FILLED;
   }

   //--- IBroker overrides -------------------------------------------+

   MksExecutionResult Send(const MksOrderRequest &request) override
   {
      m_sendCount++;
      MksExecutionResult r;
      r.status         = MKS_EXEC_FILLED;
      r.positionId     = (ulong)(1000 + m_sendCount);
      r.filledLots     = request.lots;
      r.fillPrice      = (request.side == MKS_ORDER_BUY) ? 1.0 : 0.0;
      r.requestedPrice = 0.0;
      return r;
   }

   MksExecutionResult Close(ulong positionId, double lots) override
   {
      int idx = ArraySize(m_closes);
      ArrayResize(m_closes, idx + 1);
      m_closes[idx].positionId = positionId;
      m_closes[idx].lots       = lots;

      MksExecutionResult r;
      r.status      = m_nextCloseStatus;
      r.positionId  = positionId;
      r.filledLots  = (m_nextCloseStatus == MKS_EXEC_FILLED) ? lots : 0.0;
      return r;
   }

   bool Modify(ulong positionId, double slPrice, double tpPrice) override
   {
      int idx = ArraySize(m_modifies);
      ArrayResize(m_modifies, idx + 1);
      m_modifies[idx].positionId = positionId;
      m_modifies[idx].slPrice    = slPrice;
      m_modifies[idx].tpPrice    = tpPrice;
      return m_nextModifyReturns;
   }

   //--- Inspeção pelos testes ---------------------------------------+

   int           ModifyCount()             const { return ArraySize(m_modifies); }
   int           CloseCount()              const { return ArraySize(m_closes); }
   int           SendCount()               const { return m_sendCount; }

   MksModifyCall ModifyAt(int idx)         const { return m_modifies[idx]; }
   MksCloseCall  CloseAt(int idx)          const { return m_closes[idx]; }

   MksModifyCall LastModify() const
   {
      int n = ArraySize(m_modifies);
      return m_modifies[n - 1];
   }

   MksCloseCall LastClose() const
   {
      int n = ArraySize(m_closes);
      return m_closes[n - 1];
   }

   //--- Configuração ------------------------------------------------+

   void SetNextModifyReturns(bool v) { m_nextModifyReturns = v; }
   void SetNextCloseStatus(ENUM_MKS_EXEC_STATUS s) { m_nextCloseStatus = s; }

   void Reset()
   {
      ArrayResize(m_modifies, 0);
      ArrayResize(m_closes,   0);
      m_sendCount = 0;
   }
};

#endif // MKS_ULTIMATE_CORE_TESTING_MOCKS_RECORDINGBROKER_MQH
