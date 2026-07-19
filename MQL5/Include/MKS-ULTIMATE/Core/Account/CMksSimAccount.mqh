//+------------------------------------------------------------------+
//| @file           : CMksSimAccount.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Account
//| @responsibility : Implementação de IAccount para o pipeline de
//|                   decisão determinístico (E2). Equity/Balance a
//|                   partir do P&L REALIZADO (closes + auto-closes,
//|                   menos comissão) mais o MTM não-realizado das
//|                   posições sim abertas ao mid corrente. Sem ela o
//|                   breaker de conta (DayPnL/Drawdown — a camada onde
//|                   o V5 quebrou) ficaria inerte no runner (a conta
//|                   fake devolve 10000 fixo). Alimentada por eventos
//|                   (OnOpen/OnClose/SetMid) — determinística, testável
//|                   isoladamente. Swap OFF em v1 (decisão do dono
//|                   2026-07-19: swap-free agora, marcado no journal;
//|                   accrual de swap fica para o E4).
//| @depends_on     : Core/Interfaces/IAccount.mqh,
//|                   Core/Interfaces/ISymbol.mqh,
//|                   Core/Types/OrderRequest.mqh (ENUM_MKS_ORDER_SIDE)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Account/CMksSimAccount.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_ACCOUNT_CMKSSIMACCOUNT_MQH
#define MKS_ULTIMATE_CORE_ACCOUNT_CMKSSIMACCOUNT_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IAccount.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>

// Conta simulada para o CMksDecisionRunner (E2). Get-on-demand como o
// IAccount real: Balance()/Equity() são computados na chamada.
//
//   Balance() = startBalance + realizado
//   Equity()  = Balance()    + Σ MTM não-realizado das posições abertas
//
// P&L em moeda segue a convenção do CMksPercentRiskSizer (moneyPerPoint
// = tickValue·point/tickSize): a P&L de uma diferença de PREÇO é
//   (priceDiff / tickSize) · tickValue · lots · sinal
// (o `point` cancela). Consistência com o sizer é obrigatória — senão a
// conta e o dimensionamento discordariam sobre quanto um movimento vale.
//
// Determinismo: sem RNG, sem wall-clock. A soma acumula na ORDEM dos
// eventos alimentados pelo runner (idêntica em qualquer execução do
// mesmo .mkstick) → Balance/Equity bit-a-bit reproduzíveis.
//
// MARGEM não é modelada em v1: Margin()=0, FreeMargin()=Equity(). O
// breaker de risco (camada Por Conta) só lê Balance/Equity — margin
// fica para quando houver caso de uso.
class CMksSimAccount : public IAccount
{
private:
   ISymbol *m_symbol;
   double   m_startBalance;
   double   m_realized;      // P&L realizado acumulado (já líquido de comissão)
   bool     m_applySwap;     // v1: sempre false (marcador para o journal/E4)

   double   m_mid;
   bool     m_hasMid;

   // Posições sim abertas (arrays paralelos, ordem de abertura preservada).
   ulong               m_openIds[];
   ENUM_MKS_ORDER_SIDE m_openSides[];
   double              m_openPrices[];
   double              m_openLots[];

   // P&L em moeda de uma diferença de preço, na convenção do sizer.
   double PriceDiffToMoney(const double priceDiff, const double lots,
                           const ENUM_MKS_ORDER_SIDE side) const
   {
      double tickSize  = m_symbol.TickSize();
      double tickValue = m_symbol.TickValue();
      if(tickSize <= 0.0) return 0.0;
      double sign = (side == MKS_ORDER_BUY) ? 1.0 : -1.0;
      return (priceDiff / tickSize) * tickValue * lots * sign;
   }

   int FindOpen(const ulong id) const
   {
      int n = ArraySize(m_openIds);
      for(int i = 0; i < n; i++)
         if(m_openIds[i] == id) return i;
      return -1;
   }

   void RemoveOpenAt(const int idx)
   {
      int n = ArraySize(m_openIds);
      for(int i = idx; i < n - 1; i++)
      {
         m_openIds[i]    = m_openIds[i + 1];
         m_openSides[i]  = m_openSides[i + 1];
         m_openPrices[i] = m_openPrices[i + 1];
         m_openLots[i]   = m_openLots[i + 1];
      }
      ArrayResize(m_openIds,    n - 1);
      ArrayResize(m_openSides,  n - 1);
      ArrayResize(m_openPrices, n - 1);
      ArrayResize(m_openLots,   n - 1);
   }

public:
   CMksSimAccount(ISymbol *symbol, const double startBalance,
                  const bool applySwap = false)
   {
      m_symbol       = symbol;
      m_startBalance = startBalance;
      m_realized     = 0.0;
      m_applySwap    = applySwap;
      m_mid          = 0.0;
      m_hasMid       = false;
      ArrayResize(m_openIds,    0);
      ArrayResize(m_openSides,  0);
      ArrayResize(m_openPrices, 0);
      ArrayResize(m_openLots,   0);
   }

   //--- Alimentação pelo runner (determinística) --------------------+

   // Atualiza o mid corrente para o cálculo de MTM. Chamado por tick
   // pelo runner (com o mid do tick admitido).
   void SetMid(const double mid) { m_mid = mid; m_hasMid = true; }

   // Registra abertura: entra na lista de abertas; comissão sai do
   // realizado imediatamente (custo de entrada).
   void OnOpen(const ulong id, const ENUM_MKS_ORDER_SIDE side,
               const double openPrice, const double lots,
               const double commission)
   {
      int n = ArraySize(m_openIds);
      ArrayResize(m_openIds,    n + 1);
      ArrayResize(m_openSides,  n + 1);
      ArrayResize(m_openPrices, n + 1);
      ArrayResize(m_openLots,   n + 1);
      m_openIds[n]    = id;
      m_openSides[n]  = side;
      m_openPrices[n] = openPrice;
      m_openLots[n]   = lots;
      m_realized     -= commission;
   }

   // Registra fechamento (close no flip OU auto-close de SL/TP):
   // realiza a P&L da posição e sai da lista de abertas. Se o id não
   // estiver aberto (fechamento duplicado), é no-op — defensivo.
   void OnClose(const ulong id, const double closePrice,
                const double commission)
   {
      int idx = FindOpen(id);
      if(idx < 0) return;
      double pnl = PriceDiffToMoney(closePrice - m_openPrices[idx],
                                    m_openLots[idx], m_openSides[idx]);
      m_realized += pnl - commission;
      RemoveOpenAt(idx);
   }

   //--- IAccount overrides ------------------------------------------+

   double Balance() const override { return m_startBalance + m_realized; }

   double Equity() const override
   {
      double eq = Balance();
      if(!m_hasMid) return eq; // sem mid, MTM indefinido → só realizado
      int n = ArraySize(m_openIds);
      for(int i = 0; i < n; i++)
         eq += PriceDiffToMoney(m_mid - m_openPrices[i],
                                m_openLots[i], m_openSides[i]);
      return eq;
   }

   // Margem não modelada em v1 (breaker Por Conta só lê Balance/Equity).
   double Margin()     const override { return 0.0; }
   double FreeMargin() const override { return Equity(); }

   long   Login()   const override { return 0; }          // conta sim
   string Company() const override { return "MKS-SIM"; }
   string Currency() const override
   {
      return (m_symbol != NULL) ? m_symbol.ProfitCurrency() : "USD";
   }

   int Leverage() const override { return 100; }          // não usado pelo risco
   ENUM_ACCOUNT_MARGIN_MODE MarginMode() const override
   {
      return ACCOUNT_MARGIN_MODE_RETAIL_HEDGING; // hedging-only (ADR-029)
   }
   ENUM_ACCOUNT_TRADE_MODE TradeMode() const override
   {
      return ACCOUNT_TRADE_MODE_DEMO;
   }

   //--- Observabilidade (testes/journal) ----------------------------+
   double RealizedPnL() const { return m_realized; }
   int    OpenCount()   const { return ArraySize(m_openIds); }
   bool   ApplySwap()   const { return m_applySwap; } // journal header (E4)
};

#endif // MKS_ULTIMATE_CORE_ACCOUNT_CMKSSIMACCOUNT_MQH
