//+------------------------------------------------------------------+
//| @file           : CMksMt5PositionBook.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Position
//| @responsibility : Implementação real de IPositionBook via API MT5
//|                   (PositionsTotal, PositionGetSymbol, PositionGet
//|                   Double). Symbol-bound: contagem e lots somam só
//|                   posições do símbolo configurado no construtor.
//|                   Opcionalmente filtra por magic. ADR-019 slice 6.2.
//| @depends_on     : Core/Interfaces/IPositionBook.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Position/CMksMt5PositionBook.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_POSITION_CMKSMT5POSITIONBOOK_MQH
#define MKS_ULTIMATE_CORE_POSITION_CMKSMT5POSITIONBOOK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IPositionBook.mqh>

// Filtro de magic: -1 = sem filtro (qualquer magic do símbolo conta).
// magic >= 0 = só posições com aquele magic somam. Útil para coexistir
// múltiplas estratégias na mesma conta sem que o Risk de uma veja as
// posições da outra.
class CMksMt5PositionBook : public IPositionBook
{
private:
   string m_symbol;
   long   m_magic; // -1 = sem filtro

   bool MatchesScope(int positionIndex) const
   {
      if(!PositionGetTicket(positionIndex)) return false;
      if(PositionGetString(POSITION_SYMBOL) != m_symbol) return false;
      if(m_magic >= 0 && PositionGetInteger(POSITION_MAGIC) != m_magic)
         return false;
      return true;
   }

public:
   CMksMt5PositionBook(const string &symbol, long magic = -1)
   {
      m_symbol = symbol;
      m_magic  = magic;
   }

   int OpenCount() const override
   {
      int total = PositionsTotal();
      int hits  = 0;
      for(int i = 0; i < total; i++)
         if(MatchesScope(i)) hits++;
      return hits;
   }

   double TotalLots() const override
   {
      int total = PositionsTotal();
      double sum = 0.0;
      for(int i = 0; i < total; i++)
         if(MatchesScope(i))
            sum += PositionGetDouble(POSITION_VOLUME);
      return sum;
   }

   // Itera posições MT5 procurando ticket == positionId no escopo
   // configurado (símbolo + magic). Em conta hedging do MT5, ticket
   // coincide com positionId. Custo O(N) onde N = total de posições da
   // conta — aceitável (N tipicamente << 10).
   bool IsOpen(ulong positionId) const override
   {
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(ticket != positionId) continue;
         // Aplica escopo (símbolo + magic) — posição existe mas fora do
         // escopo conta como "não nossa" → false (TradeManager não
         // deveria estar attached numa posição fora do escopo).
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) return false;
         if(m_magic >= 0 && PositionGetInteger(POSITION_MAGIC) != m_magic)
            return false;
         return true;
      }
      return false;
   }

   string Symbol() const { return m_symbol; }
   long   Magic()  const { return m_magic; }
};

#endif // MKS_ULTIMATE_CORE_POSITION_CMKSMT5POSITIONBOOK_MQH
