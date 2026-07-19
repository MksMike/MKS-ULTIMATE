//+------------------------------------------------------------------+
//| @file           : CMksFeedClock.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Clock
//| @responsibility : IClock cujo "agora" é o timeMsc do último tick
//|                   ADMITIDO, setado explicitamente por tick. Análogo
//|                   LIVE do CMksReplayClock: em vez de puxar de um
//|                   ITickSource (replay), é alimentado pelo composition
//|                   root com o timeMsc do tick que a estratégia acabou
//|                   de ver. Assim a fronteira de dia UTC do
//|                   CMksAccountSnapshot deriva do FEED nos dois
//|                   ambientes (E2.4), eliminando o leak de TimeCurrent()
//|                   do CMksMt5Clock que fazia o rollover de meia-noite
//|                   cair em pontos diferentes entre live e replay.
//| @depends_on     : Core/Interfaces/IClock.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Clock/CMksFeedClock.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_CLOCK_CMKSFEEDCLOCK_MQH
#define MKS_ULTIMATE_CORE_CLOCK_CMKSFEEDCLOCK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IClock.mqh>

// Determinismo: NowMsc é função pura do que foi alimentado — zero
// TimeCurrent(), zero wall-clock. IsReady() segue a mesma semântica do
// CMksReplayClock (pronto quando já viu ≥1 tick com timeMsc > 0).
class CMksFeedClock : public IClock
{
private:
   long m_nowMsc;

public:
   CMksFeedClock() { m_nowMsc = 0; }

   // Chamado pelo composition root a cada tick admitido, com o timeMsc
   // do tick. Monotônico por construção (o feed avança), mas a classe
   // não impõe — só reflete o que recebe.
   void SetNow(const long timeMsc) { m_nowMsc = timeMsc; }

   virtual long NowMsc()  const override { return m_nowMsc; }
   virtual bool IsReady() const override { return m_nowMsc > 0; }
};

#endif // MKS_ULTIMATE_CORE_CLOCK_CMKSFEEDCLOCK_MQH
