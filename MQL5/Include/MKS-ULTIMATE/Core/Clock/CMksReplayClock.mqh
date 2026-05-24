//+------------------------------------------------------------------+
//| @file           : CMksReplayClock.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Clock
//| @responsibility : Implementação de IClock para replay. O "agora" é
//|                   o timestamp do tick corrente — função pura do feed,
//|                   determinismo preservado (ADR-024 §5; §Alternativas
//|                   rejeita wall-clock acelerado).
//| @depends_on     : Core/Interfaces/IClock.mqh,
//|                   Core/Interfaces/ITickSource.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Clock/CMksReplayClock.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_CLOCK_CMKSREPLAYCLOCK_MQH
#define MKS_ULTIMATE_CORE_CLOCK_CMKSREPLAYCLOCK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IClock.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ITickSource.mqh>

// O clock consulta `LastTickTimeMsc()` da interface ITickSource — desde
// o slice 24d-parte-2 esse método é puro virtual da interface, então o
// clock aceita qualquer fonte (single-file, multi-file, futuras live)
// sem mudar tipo. Determinismo preservado: tempo é função pura do feed.
class CMksReplayClock : public IClock
{
private:
   ITickSource *m_source;

public:
   CMksReplayClock(ITickSource *source) : m_source(source) {}

   virtual long NowMsc() const override
   {
      if(m_source == NULL) return 0;
      return m_source.LastTickTimeMsc();
   }

   // Antes do primeiro Next() bem-sucedido, LastTickTimeMsc()==0. Código
   // de estratégia que comparasse contra horário decidiria sobre tempo
   // inexistente — composition root checa IsReady() antes da primeira
   // decisão temporal. Pronto quando o source já entregou ≥1 tick
   // (detectado por LastTickTimeMsc() > 0, válido para qualquer source
   // cujo primeiro tick válido tem timeMsc > 0 — todos os reais).
   virtual bool IsReady() const override
   {
      return m_source != NULL && m_source.LastTickTimeMsc() > 0;
   }
};

#endif // MKS_ULTIMATE_CORE_CLOCK_CMKSREPLAYCLOCK_MQH