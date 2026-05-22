//+------------------------------------------------------------------+
//| @file           : CMksFakeAccount.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Testing / Mocks
//| @responsibility : Mock de IAccount — estado da conta com valores
//|                   configuráveis em runtime, defaults para demo
//|                   hedging em USD. Ver ADR-005.
//| @depends_on     : Core/Interfaces/IAccount.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeAccount.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKEACCOUNT_MQH
#define MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKEACCOUNT_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IAccount.mqh>

class CMksFakeAccount : public IAccount
{
private:
   long   m_login;
   string m_company;
   string m_currency;
   double m_balance;
   double m_equity;
   double m_margin;
   double m_freeMargin;
   int    m_leverage;
   ENUM_ACCOUNT_MARGIN_MODE m_marginMode;
   ENUM_ACCOUNT_TRADE_MODE  m_tradeMode;

public:
   //--- Defaults: conta demo hedging USD com 10k de saldo, 100x leverage.
   //--- Hedging porque CMksSimulatedBroker v1 assume hedging.
   CMksFakeAccount()
   {
      m_login      = 12345678;
      m_company    = "FakeBroker";
      m_currency   = "USD";
      m_balance    = 10000.0;
      m_equity     = 10000.0;
      m_margin     = 0.0;
      m_freeMargin = 10000.0;
      m_leverage   = 100;
      m_marginMode = ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
      m_tradeMode  = ACCOUNT_TRADE_MODE_DEMO;
   }

   //--- IAccount overrides ---------------------------------------+
   long   Login()    const override { return m_login; }
   string Company()  const override { return m_company; }
   string Currency() const override { return m_currency; }

   double Balance()    const override { return m_balance; }
   double Equity()     const override { return m_equity; }
   double Margin()     const override { return m_margin; }
   double FreeMargin() const override { return m_freeMargin; }

   int    Leverage()                          const override { return m_leverage; }
   ENUM_ACCOUNT_MARGIN_MODE MarginMode()      const override { return m_marginMode; }
   ENUM_ACCOUNT_TRADE_MODE  TradeMode()       const override { return m_tradeMode; }

   //--- Setters ---------------------------------------------------+
   void SetLogin(long v)                              { m_login = v; }
   void SetCompany(const string v)                    { m_company = v; }
   void SetCurrency(const string v)                   { m_currency = v; }
   void SetBalance(double v)                          { m_balance = v; }
   void SetEquity(double v)                           { m_equity = v; }
   void SetMargin(double v)                           { m_margin = v; }
   void SetFreeMargin(double v)                       { m_freeMargin = v; }
   void SetLeverage(int v)                            { m_leverage = v; }
   void SetMarginMode(ENUM_ACCOUNT_MARGIN_MODE v)     { m_marginMode = v; }
   void SetTradeMode(ENUM_ACCOUNT_TRADE_MODE v)       { m_tradeMode = v; }
};

#endif // MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKEACCOUNT_MQH
