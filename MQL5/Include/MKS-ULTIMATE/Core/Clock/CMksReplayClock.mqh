//+------------------------------------------------------------------+
//| @file           : CMksReplayClock.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Clock
//| @responsibility : Implementação de IClock para replay. O "agora" é
//|                   o timestamp do tick corrente — função pura do feed,
//|                   determinismo preservado (ADR-024 §5; §Alternativas
//|                   rejeita wall-clock acelerado).
//| @depends_on     : Core/Interfaces/IClock.mqh,
//|                   Core/Data/CMksFileTickSource.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Clock/CMksReplayClock.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_CLOCK_CMKSREPLAYCLOCK_MQH
#define MKS_ULTIMATE_CORE_CLOCK_CMKSREPLAYCLOCK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IClock.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksFileTickSource.mqh>

// O clock recebe o source concreto (não a interface ITickSource) porque
// o método consultado, `LastTickTimeMsc()`, é específico do replay e
// não pertence ao contrato de produção de ticks (ITickSource). Sources
// de replay futuros (multi-arquivo, in-memory) só precisam expor o
// mesmo getter para serem aceitos aqui.
class CMksReplayClock : public IClock
{
private:
   CMksFileTickSource *m_source;

public:
   CMksReplayClock(CMksFileTickSource *source) : m_source(source) {}

   virtual long NowMsc() const override
   {
      if(m_source == NULL) return 0;
      return m_source.LastTickTimeMsc();
   }
};

#endif // MKS_ULTIMATE_CORE_CLOCK_CMKSREPLAYCLOCK_MQH