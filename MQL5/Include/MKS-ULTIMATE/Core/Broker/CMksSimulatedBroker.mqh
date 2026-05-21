//+------------------------------------------------------------------+
//| @file           : CMksSimulatedBroker.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Broker
//| @responsibility : Implementação de IBroker para backtest. Mantém
//|                   estado interno de posições; aplica custos via
//|                   CMksCostModel; determinístico. ADR-017.
//| @depends_on     : Core/Interfaces/IBroker.mqh, Core/Interfaces/ISymbol.mqh,
//|                   Core/Broker/CMksCostModel.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/OrderRequest.mqh, Core/Types/ExecutionResult.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Broker/CMksSimulatedBroker.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_BROKER_CMKSSIMULATEDBROKER_MQH
#define MKS_ULTIMATE_CORE_BROKER_CMKSSIMULATEDBROKER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksCostModel.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>

// Posição mantida internamente pelo broker simulado.
// SL e TP armazenados em PREÇO ABSOLUTO (não em pontos).
// Auto-close de SL/TP NÃO é responsabilidade deste broker em v1 —
// Trade Manager futuro monitora condições e chama Close quando
// apropriado. SimBroker apenas executa.
struct MksSimPosition
{
   ulong  id;
   ENUM_MKS_ORDER_SIDE side;
   double lots;
   double openPrice;
   double sl;            // 0 = sem SL
   double tp;            // 0 = sem TP
   double commissionOpen;
   long   openTimeMsc;
   ulong  dealOpenId;
   bool   isOpen;

   MksSimPosition()
   {
      id = 0;
      side = MKS_ORDER_BUY;
      lots = 0.0;
      openPrice = 0.0;
      sl = 0.0;
      tp = 0.0;
      commissionOpen = 0.0;
      openTimeMsc = 0;
      dealOpenId = 0;
      isOpen = false;
   }
};

// Broker simulado para backtest. Assume HEDGING — cada Send abre nova
// posição com ticket único. Netting fica para evolução futura.
//
// Uso típico:
//   CMksSimulatedBroker broker(GetPointer(sym), GetPointer(costModel));
//   broker.OnTick(currentTick);      // atualiza mid antes de cada Send/Close
//   MksExecutionResult r = broker.Send(req);
//
// Determinismo: sem RNG. Mesma sequência (OnTick + Send/Close/Modify)
// produz exatamente os mesmos MksExecutionResult — fundamental para
// paridade backtest/live (ADR-017).
class CMksSimulatedBroker : public IBroker
{
private:
   ISymbol            *m_symbol;
   CMksCostModel      *m_costModel;
   MksSimPosition      m_positions[];
   ulong               m_nextPositionId;
   ulong               m_nextDealId;
   double              m_lastMid;
   long                m_lastTickTimeMsc;
   bool                m_hasMid;

   int FindPositionIndex(ulong positionId) const
   {
      int n = ArraySize(m_positions);
      for(int i = 0; i < n; i++)
         if(m_positions[i].id == positionId)
            return i;
      return -1;
   }

   MksExecutionResult MakeError(int retcode, double requestedPrice = 0.0) const
   {
      MksExecutionResult r;
      r.status = MKS_EXEC_ERROR;
      r.brokerRetcode = retcode;
      r.requestedPrice = requestedPrice;
      r.execTimeMsc = m_lastTickTimeMsc;
      r.attempts = 1;
      return r;
   }

   MksExecutionResult MakeRejected(int retcode, double requestedPrice = 0.0) const
   {
      MksExecutionResult r;
      r.status = MKS_EXEC_REJECTED;
      r.brokerRetcode = retcode;
      r.requestedPrice = requestedPrice;
      r.execTimeMsc = m_lastTickTimeMsc;
      r.attempts = 1;
      return r;
   }

public:
   CMksSimulatedBroker(ISymbol *symbol, CMksCostModel *costModel)
   {
      m_symbol           = symbol;
      m_costModel        = costModel;
      m_nextPositionId   = 1;
      m_nextDealId       = 1;
      m_lastMid          = 0.0;
      m_lastTickTimeMsc  = 0;
      m_hasMid           = false;
      ArrayResize(m_positions, 0);
   }

   // Atualiza preço corrente do broker. Caller (EA/script) chama a cada
   // tick antes de Send/Close para garantir que o broker conheça o mid.
   void OnTick(const MksTick &tick)
   {
      if(!tick.IsValid()) return;
      m_lastMid         = (tick.bid + tick.ask) / 2.0;
      m_lastTickTimeMsc = tick.timeMsc;
      m_hasMid          = true;
   }

   MksExecutionResult Send(const MksOrderRequest &request) override
   {
      if(m_symbol == NULL || m_costModel == NULL)
         return MakeError(MKS_ERR_BROKER_NOT_INITIALIZED);
      if(!m_hasMid)
         return MakeError(MKS_ERR_BROKER_NOT_INITIALIZED);
      if(!request.IsValid())
         return MakeRejected(MKS_ERR_CORE_INVALID_ARGUMENT, m_lastMid);

      double point     = m_symbol.Point();
      double fillPrice = m_costModel.FillPriceFor(request.side, m_lastMid, point);
      double commission = m_costModel.Commission(request.lots);

      // SL/TP em preço absoluto (request traz em pontos).
      double slPrice = 0.0;
      double tpPrice = 0.0;
      if(request.slPoints > 0.0)
      {
         if(request.side == MKS_ORDER_BUY)
            slPrice = fillPrice - request.slPoints * point;
         else
            slPrice = fillPrice + request.slPoints * point;
      }
      if(request.tpPoints > 0.0)
      {
         if(request.side == MKS_ORDER_BUY)
            tpPrice = fillPrice + request.tpPoints * point;
         else
            tpPrice = fillPrice - request.tpPoints * point;
      }

      // Cria position.
      MksSimPosition pos;
      pos.id              = m_nextPositionId++;
      pos.side            = request.side;
      pos.lots            = request.lots;
      pos.openPrice       = fillPrice;
      pos.sl              = slPrice;
      pos.tp              = tpPrice;
      pos.commissionOpen  = commission;
      pos.openTimeMsc     = m_lastTickTimeMsc;
      pos.dealOpenId      = m_nextDealId++;
      pos.isOpen          = true;
      int n = ArraySize(m_positions);
      ArrayResize(m_positions, n + 1);
      m_positions[n] = pos;

      // Monta resultado.
      MksExecutionResult r;
      r.status          = MKS_EXEC_FILLED;
      r.positionId      = pos.id;
      r.dealId          = pos.dealOpenId;
      r.fillPrice       = fillPrice;
      r.requestedPrice  = m_lastMid;
      r.filledLots      = request.lots;
      r.commission      = commission;
      r.swap            = 0.0; // sem carry na abertura
      r.execTimeMsc     = m_lastTickTimeMsc;
      r.brokerRetcode   = 0;
      r.attempts        = 1;
      return r;
   }

   MksExecutionResult Close(ulong positionId, double lots) override
   {
      if(m_symbol == NULL || m_costModel == NULL)
         return MakeError(MKS_ERR_BROKER_NOT_INITIALIZED);
      if(!m_hasMid)
         return MakeError(MKS_ERR_BROKER_NOT_INITIALIZED);

      int idx = FindPositionIndex(positionId);
      if(idx < 0 || !m_positions[idx].isOpen)
         return MakeRejected(MKS_ERR_CORE_INVALID_ARGUMENT, m_lastMid);
      if(lots <= 0.0 || lots > m_positions[idx].lots)
         return MakeRejected(MKS_ERR_CORE_INVALID_ARGUMENT, m_lastMid);

      double point = m_symbol.Point();
      // Close fill: lado oposto ao da posição.
      ENUM_MKS_ORDER_SIDE oppositeSide =
         (m_positions[idx].side == MKS_ORDER_BUY) ? MKS_ORDER_SELL : MKS_ORDER_BUY;
      double fillPrice  = m_costModel.FillPriceFor(oppositeSide, m_lastMid, point);
      double commission = m_costModel.Commission(lots);

      // Reduz/zera a posição.
      bool fullClose = (lots >= m_positions[idx].lots);
      if(fullClose)
      {
         m_positions[idx].isOpen = false;
         m_positions[idx].lots   = 0.0;
      }
      else
      {
         m_positions[idx].lots -= lots;
      }

      MksExecutionResult r;
      r.status          = MKS_EXEC_FILLED;
      r.positionId      = positionId;
      r.dealId          = m_nextDealId++;
      r.fillPrice       = fillPrice;
      r.requestedPrice  = m_lastMid;
      r.filledLots      = lots;
      r.commission      = commission;
      r.swap            = 0.0; // swap acumulado não é modelado em v1
      r.execTimeMsc     = m_lastTickTimeMsc;
      r.brokerRetcode   = 0;
      r.attempts        = 1;
      return r;
   }

   bool Modify(ulong positionId, double slPrice, double tpPrice) override
   {
      int idx = FindPositionIndex(positionId);
      if(idx < 0 || !m_positions[idx].isOpen) return false;
      m_positions[idx].sl = slPrice;
      m_positions[idx].tp = tpPrice;
      return true;
   }

   //--- Observabilidade (testes/diagnóstico) ---
   int OpenPositionsCount() const
   {
      int count = 0;
      int n = ArraySize(m_positions);
      for(int i = 0; i < n; i++)
         if(m_positions[i].isOpen) count++;
      return count;
   }

   int TotalPositionsCount() const { return ArraySize(m_positions); }

   bool TryGetPosition(ulong positionId, MksSimPosition &out) const
   {
      int idx = FindPositionIndex(positionId);
      if(idx < 0) return false;
      out = m_positions[idx];
      return true;
   }

   double LastMid() const { return m_lastMid; }
   bool   HasMid()  const { return m_hasMid; }
};

#endif // MKS_ULTIMATE_CORE_BROKER_CMKSSIMULATEDBROKER_MQH
