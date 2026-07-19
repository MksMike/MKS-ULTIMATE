//+------------------------------------------------------------------+
//| @file           : CMksFakePositionBook.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Testing / Mocks
//| @responsibility : Mock de IPositionBook — contagem e lots totais
//|                   configuráveis em runtime para testes do
//|                   CMksRiskManager (slice 6.2). Ver ADR-005.
//| @depends_on     : Core/Interfaces/IPositionBook.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Testing/Mocks/CMksFakePositionBook.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKEPOSITIONBOOK_MQH
#define MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKEPOSITIONBOOK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IPositionBook.mqh>

class CMksFakePositionBook : public IPositionBook
{
private:
   int    m_openCount;
   double m_totalLots;

   // Lista de positionIds explicitamente marcados como fechados.
   // IsOpen retorna false se o id estiver aqui — default é "aberto"
   // (preserva semântica simples para testes que não exercitam
   // auto-detach).
   ulong  m_closedIds[];

   // Posições explícitas para PositionAt (testes de reconciliação de
   // órfã, M10). Arrays paralelos; alimentados por AddPosition.
   // PositionAt responde SÓ por este array — testes legados que usam
   // apenas SetOpenCount/SetTotalLots seguem válidos (PositionAt
   // retorna false para eles, como se o snapshot tivesse mudado).
   ulong               m_posIds[];
   ENUM_MKS_ORDER_SIDE m_posSides[];
   double              m_posLots[];

public:
   CMksFakePositionBook()
   {
      m_openCount = 0;
      m_totalLots = 0.0;
      ArrayResize(m_closedIds, 0);
      ArrayResize(m_posIds,   0);
      ArrayResize(m_posSides, 0);
      ArrayResize(m_posLots,  0);
   }

   int    OpenCount() const override { return m_openCount; }
   double TotalLots() const override { return m_totalLots; }

   bool IsOpen(ulong positionId) const override
   {
      int n = ArraySize(m_closedIds);
      for(int i = 0; i < n; i++)
         if(m_closedIds[i] == positionId) return false;
      return true;
   }

   bool PositionAt(const int index, ulong &positionId,
                   ENUM_MKS_ORDER_SIDE &side, double &lots) const override
   {
      if(index < 0 || index >= ArraySize(m_posIds)) return false;
      positionId = m_posIds[index];
      side       = m_posSides[index];
      lots       = m_posLots[index];
      return true;
   }

   void SetOpenCount(int n)   { m_openCount = n; }
   void SetTotalLots(double v){ m_totalLots = v; }

   // Adiciona posição explícita (consultável via PositionAt) e mantém
   // OpenCount/TotalLots consistentes com ela.
   void AddPosition(ulong positionId, ENUM_MKS_ORDER_SIDE side, double lots)
   {
      int n = ArraySize(m_posIds);
      ArrayResize(m_posIds,   n + 1);
      ArrayResize(m_posSides, n + 1);
      ArrayResize(m_posLots,  n + 1);
      m_posIds[n]   = positionId;
      m_posSides[n] = side;
      m_posLots[n]  = lots;
      m_openCount++;
      m_totalLots += lots;
   }

   // Marca positionId como fechado — IsOpen passa a retornar false.
   // Idempotente; chamar duas vezes não duplica.
   void MarkClosed(ulong positionId)
   {
      int n = ArraySize(m_closedIds);
      for(int i = 0; i < n; i++)
         if(m_closedIds[i] == positionId) return;
      ArrayResize(m_closedIds, n + 1);
      m_closedIds[n] = positionId;
   }
};

#endif // MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKEPOSITIONBOOK_MQH
