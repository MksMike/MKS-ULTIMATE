//+------------------------------------------------------------------+
//| @file           : CMksMt5Account.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Account
//| @responsibility : Implementação de IAccount que delega para a API
//|                   AccountInfo* nativa do MQL5. ADR-016.
//| @depends_on     : Core/Interfaces/IAccount.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Account/CMksMt5Account.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_ACCOUNT_CMKSMT5ACCOUNT_MQH
#define MKS_ULTIMATE_CORE_ACCOUNT_CMKSMT5ACCOUNT_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IAccount.mqh>

// Implementação concreta de IAccount para o MT5 real. Sem construtor
// especial — a conta corrente é única no contexto de execução do
// terminal. Cada método consulta AccountInfo* da API global. Get-on-
// demand — sem cache (Balance/Equity/Margin mudam continuamente).
class CMksMt5Account : public IAccount
{
public:
   CMksMt5Account() {}

   long   Login()    const override
   {
      return AccountInfoInteger(ACCOUNT_LOGIN);
   }

   string Company()  const override
   {
      return AccountInfoString(ACCOUNT_COMPANY);
   }

   string Currency() const override
   {
      return AccountInfoString(ACCOUNT_CURRENCY);
   }

   double Balance()    const override
   {
      return AccountInfoDouble(ACCOUNT_BALANCE);
   }

   double Equity()     const override
   {
      return AccountInfoDouble(ACCOUNT_EQUITY);
   }

   double Margin()     const override
   {
      return AccountInfoDouble(ACCOUNT_MARGIN);
   }

   double FreeMargin() const override
   {
      return AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   }

   int Leverage() const override
   {
      return (int)AccountInfoInteger(ACCOUNT_LEVERAGE);
   }

   ENUM_ACCOUNT_MARGIN_MODE MarginMode() const override
   {
      return (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   }

   ENUM_ACCOUNT_TRADE_MODE TradeMode() const override
   {
      return (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   }
};

#endif // MKS_ULTIMATE_CORE_ACCOUNT_CMKSMT5ACCOUNT_MQH
