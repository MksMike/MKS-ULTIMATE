//+------------------------------------------------------------------+
//| @file           : IClock.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Interface IClock — abstração de tempo; substitui
//|                   acesso direto a TimeCurrent() na lógica.
//| @depends_on     : Nenhuma (tipos nativos)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/IClock.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_ICLOCK_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_ICLOCK_MQH

//--- Interface: fonte do "agora" do sistema (ADR-004).
class IClock
{
public:
   virtual ~IClock() {}

   // "Agora" em ms desde epoch. Backtest: tempo do tick corrente.
   // Live: tempo do servidor. Substitui TimeCurrent() direto.
   virtual long NowMsc() const = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_ICLOCK_MQH
