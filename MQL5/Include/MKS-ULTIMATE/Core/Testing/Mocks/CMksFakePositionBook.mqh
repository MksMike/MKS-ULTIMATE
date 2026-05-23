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

public:
   CMksFakePositionBook()
   {
      m_openCount = 0;
      m_totalLots = 0.0;
   }

   int    OpenCount() const override { return m_openCount; }
   double TotalLots() const override { return m_totalLots; }

   void SetOpenCount(int n)   { m_openCount = n; }
   void SetTotalLots(double v){ m_totalLots = v; }
};

#endif // MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKEPOSITIONBOOK_MQH
