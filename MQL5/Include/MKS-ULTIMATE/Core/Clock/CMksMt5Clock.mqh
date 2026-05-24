//+------------------------------------------------------------------+
//| @file           : CMksMt5Clock.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Clock
//| @responsibility : Implementação de IClock para uso live. Retorna o
//|                   tempo do servidor MT5 (`TimeCurrent()`) em ms.
//|                   Consolida a leitura que hoje vive implícita no
//|                   Producer e abre caminho para o composition root
//|                   replay-safe (ADR-024 §5, §6).
//| @depends_on     : Core/Interfaces/IClock.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Clock/CMksMt5Clock.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_CLOCK_CMKSMT5CLOCK_MQH
#define MKS_ULTIMATE_CORE_CLOCK_CMKSMT5CLOCK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IClock.mqh>

// Em live, o Producer/Replayer chama `clock.NowMsc()` em vez de
// `TimeCurrent()` direto. A REGRAS §1.9 (futuro slice 24f) proíbe
// TimeCurrent na lógica da estratégia — esta classe é o ponto de
// borda que centraliza o acesso permitido.
class CMksMt5Clock : public IClock
{
public:
   virtual long NowMsc() const override
   {
      // TimeCurrent retorna em segundos; padronizamos em ms desde epoch.
      return (long)TimeCurrent() * 1000;
   }

   // TimeCurrent está disponível desde o OnInit em qualquer chart bound;
   // não há janela em que o clock real não esteja pronto.
   virtual bool IsReady() const override { return true; }
};

#endif // MKS_ULTIMATE_CORE_CLOCK_CMKSMT5CLOCK_MQH