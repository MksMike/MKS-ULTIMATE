//+------------------------------------------------------------------+
//| @file           : IAccount.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Interface IAccount — estado e propriedades da
//|                   conta corrente. Substituto canônico da API
//|                   AccountInfo* global em código de lógica
//|                   (Protocolo 9, ADR-016).
//| @depends_on     : Nenhuma (tipos nativos do MQL5)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/IAccount.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_IACCOUNT_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_IACCOUNT_MQH

// Contrato de "estado da conta" — identidade, balanço e modo de margem.
// Get-on-demand: cada chamada consulta o estado atual; Balance/Equity/
// Margin mudam continuamente em live e cachear produz dados defasados.
//
// MarginMode e TradeMode retornam enums nativos do MQL5 — framework é
// MQL5-only por ADR-004, mapear esses enums em tipos próprios seria
// indireção sem ganho.
class IAccount
{
public:
   virtual ~IAccount() {}

   //--- Identidade ---
   virtual long   Login()    const = 0;
   virtual string Company()  const = 0; // nome do broker
   virtual string Currency() const = 0; // moeda da conta

   //--- Estado (dinâmico, get-on-demand) ---
   virtual double Balance()    const = 0;
   virtual double Equity()     const = 0;
   virtual double Margin()     const = 0;
   virtual double FreeMargin() const = 0;

   //--- Tipo / configuração ---
   virtual int    Leverage()                          const = 0;
   virtual ENUM_ACCOUNT_MARGIN_MODE MarginMode()      const = 0; // netting/hedging
   virtual ENUM_ACCOUNT_TRADE_MODE  TradeMode()       const = 0; // real/demo/contest
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_IACCOUNT_MQH
