//+------------------------------------------------------------------+
//| @file           : CMksFakeClock.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Testing / Mocks
//| @responsibility : Mock de IClock — tempo configurável em runtime
//|                   para testes que precisam exercitar rollover de
//|                   dia, peak history e janelas temporais sem
//|                   depender de TimeCurrent. Ver ADR-005.
//| @depends_on     : Core/Interfaces/IClock.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeClock.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKECLOCK_MQH
#define MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKECLOCK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IClock.mqh>

class CMksFakeClock : public IClock
{
private:
   long m_nowMsc;

public:
   CMksFakeClock() { m_nowMsc = 0; }

   long NowMsc() const override { return m_nowMsc; }

   // Mock sempre pronto — testes que precisam exercitar "clock não pronto"
   // injetam um mock alternativo ou usam um flag específico do teste.
   bool IsReady() const override { return true; }

   void   SetNowMsc(long v)   { m_nowMsc = v; }
   void   Advance(long dtMsc) { m_nowMsc += dtMsc; }
};

#endif // MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKECLOCK_MQH
