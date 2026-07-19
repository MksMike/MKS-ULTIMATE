//+------------------------------------------------------------------+
//| @file           : CMksSimPositionBook.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Position
//| @responsibility : IPositionBook lastreado no CMksSimulatedBroker
//|                   (E2). Espelha o estado de posições do broker
//|                   simulado para que a estratégia enxergue auto-closes
//|                   de SL/TP no runner determinístico exatamente como
//|                   enxergaria o broker real via CMksMt5PositionBook.
//|                   Semântica de IsOpen(id desconhecido)=false idêntica
//|                   ao book REAL — NÃO a inversão do CMksFakePositionBook
//|                   (mock), cujo default true mascararia divergência.
//| @depends_on     : Core/Interfaces/IPositionBook.mqh,
//|                   Core/Broker/CMksSimulatedBroker.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Position/CMksSimPositionBook.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_POSITION_CMKSSIMPOSITIONBOOK_MQH
#define MKS_ULTIMATE_CORE_POSITION_CMKSSIMPOSITIONBOOK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IPositionBook.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksSimulatedBroker.mqh>

// Consulta-somente: reflete o CMksSimulatedBroker. O broker é a fonte da
// verdade das posições; este book só apresenta essa verdade pela
// interface IPositionBook que a estratégia e o RiskManager consomem.
// Determinístico — o estado do sim é função pura da sequência de ticks.
class CMksSimPositionBook : public IPositionBook
{
private:
   CMksSimulatedBroker *m_broker;

public:
   CMksSimPositionBook(CMksSimulatedBroker *broker) { m_broker = broker; }

   int OpenCount() const override
   {
      return (m_broker != NULL) ? m_broker.OpenPositionsCount() : 0;
   }

   double TotalLots() const override
   {
      if(m_broker == NULL) return 0.0;
      double sum = 0.0;
      int n = m_broker.OpenPositionsCount();
      MksSimPosition p;
      for(int i = 0; i < n; i++)
         if(m_broker.OpenPositionByIndex(i, p))
            sum += p.lots;
      return sum;
   }

   // true SÓ se a posição existe E está aberta. Id desconhecido => false
   // (semântica do book REAL — CMksMt5PositionBook; auto-detach da
   // estratégia depende disso). TryGetPosition preenche mesmo posição
   // fechada, então checamos isOpen explicitamente.
   bool IsOpen(ulong positionId) const override
   {
      if(m_broker == NULL) return false;
      MksSimPosition p;
      if(!m_broker.TryGetPosition(positionId, p)) return false;
      return p.isOpen;
   }

   bool PositionAt(const int index, ulong &positionId,
                   ENUM_MKS_ORDER_SIDE &side, double &lots) const override
   {
      if(m_broker == NULL) return false;
      MksSimPosition p;
      if(!m_broker.OpenPositionByIndex(index, p)) return false;
      positionId = p.id;
      side       = p.side;
      lots       = p.lots;
      return true;
   }
};

#endif // MKS_ULTIMATE_CORE_POSITION_CMKSSIMPOSITIONBOOK_MQH
