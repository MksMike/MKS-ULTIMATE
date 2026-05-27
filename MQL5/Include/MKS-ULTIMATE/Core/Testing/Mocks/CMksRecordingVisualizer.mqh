//+------------------------------------------------------------------+
//| @file           : CMksRecordingVisualizer.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Testing / Mocks
//| @responsibility : Mock de ITradeVisualizer — conta MarkEntry/MarkExit
//|                   e guarda os últimos valores, sem tocar a API de
//|                   chart. Usado nos testes da estratégia para verificar
//|                   que eventos de visualização disparam e que injetar
//|                   o visualizer NÃO muda as decisões (paridade ADR-028).
//| @depends_on     : Core/Interfaces/ITradeVisualizer.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Testing/Mocks/CMksRecordingVisualizer.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TESTING_MOCKS_RECORDINGVISUALIZER_MQH
#define MKS_ULTIMATE_CORE_TESTING_MOCKS_RECORDINGVISUALIZER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/ITradeVisualizer.mqh>

class CMksRecordingVisualizer : public ITradeVisualizer
{
private:
   int    m_entryCount;
   int    m_exitCount;
   long   m_lastEntryTimeMsc;
   double m_lastEntryPrice;
   ENUM_MKS_ORDER_SIDE m_lastEntrySide;
   ulong  m_lastEntryId;
   long   m_lastExitTimeMsc;
   double m_lastExitPrice;
   ulong  m_lastExitId;

public:
   CMksRecordingVisualizer()
   {
      m_entryCount       = 0;
      m_exitCount        = 0;
      m_lastEntryTimeMsc = 0;
      m_lastEntryPrice   = 0.0;
      m_lastEntrySide    = MKS_ORDER_BUY;
      m_lastEntryId      = 0;
      m_lastExitTimeMsc  = 0;
      m_lastExitPrice    = 0.0;
      m_lastExitId       = 0;
   }

   virtual void MarkEntry(long timeMsc, ENUM_MKS_ORDER_SIDE side,
                          double price, ulong positionId) override
   {
      m_entryCount++;
      m_lastEntryTimeMsc = timeMsc;
      m_lastEntrySide    = side;
      m_lastEntryPrice   = price;
      m_lastEntryId      = positionId;
   }

   virtual void MarkExit(long timeMsc, double price, ulong positionId) override
   {
      m_exitCount++;
      m_lastExitTimeMsc = timeMsc;
      m_lastExitPrice   = price;
      m_lastExitId      = positionId;
   }

   //--- Inspeção ---
   int    EntryCount()       const { return m_entryCount; }
   int    ExitCount()        const { return m_exitCount; }
   long   LastEntryTimeMsc() const { return m_lastEntryTimeMsc; }
   double LastEntryPrice()   const { return m_lastEntryPrice; }
   ENUM_MKS_ORDER_SIDE LastEntrySide() const { return m_lastEntrySide; }
   ulong  LastEntryId()      const { return m_lastEntryId; }
   long   LastExitTimeMsc()  const { return m_lastExitTimeMsc; }
   double LastExitPrice()    const { return m_lastExitPrice; }
   ulong  LastExitId()       const { return m_lastExitId; }
};

#endif // MKS_ULTIMATE_CORE_TESTING_MOCKS_RECORDINGVISUALIZER_MQH
