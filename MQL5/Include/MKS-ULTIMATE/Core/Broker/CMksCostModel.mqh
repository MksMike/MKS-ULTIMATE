//+------------------------------------------------------------------+
//| @file           : CMksCostModel.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Broker
//| @responsibility : Modelo de custos de execução (spread, slippage,
//|                   comissão, swap) para o CMksSimulatedBroker.
//|                   Encapsulamento determinístico — mesmas entradas
//|                   produzem mesmos custos. ADR-017 §8.
//| @depends_on     : Core/Types/OrderRequest.mqh (ENUM_MKS_ORDER_SIDE),
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Broker/CMksCostModel.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_BROKER_CMKSCOSTMODEL_MQH
#define MKS_ULTIMATE_CORE_BROKER_CMKSCOSTMODEL_MQH

#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Modelo de custos para o broker simulado (ADR-017 §8).
// Determinístico — não usa RNG. Mesma sequência de ordens, com mesmos
// parâmetros, produz exatamente o mesmo custo. Slippage é constante e
// adverso ao trader; modelagem estocástica fica para evolução futura
// (CostModel + RNG seedable, ou subclasse).
//
// Unidades:
// - spreadPoints, slippagePoints — em pontos do símbolo (chamador converte
//   para preço via symbol.Point()).
// - commissionPerLot — em moeda da conta, magnitude positiva (P&L subtrai).
// - swap*PerDay — em moeda da conta por lote por dia. Positivo = trader
//   recebe; negativo = trader paga (custo overnight).
class CMksCostModel
{
private:
   double m_spreadPoints;
   double m_slippagePoints;
   double m_commissionPerLot;
   double m_swapLongPerDay;
   double m_swapShortPerDay;

public:
   // Defaults zerados — broker sem custos. Configurar via construtor
   // ou setters explícitos (não fornecidos em v1; reinstanciar).
   CMksCostModel(double spreadPoints     = 0.0,
                 double slippagePoints   = 0.0,
                 double commissionPerLot = 0.0,
                 double swapLongPerDay   = 0.0,
                 double swapShortPerDay  = 0.0)
   {
      m_spreadPoints     = spreadPoints;
      m_slippagePoints   = slippagePoints;
      m_commissionPerLot = commissionPerLot;
      m_swapLongPerDay   = swapLongPerDay;
      m_swapShortPerDay  = swapShortPerDay;
   }

   bool Validate(MksError &err) const
   {
      if(m_spreadPoints < 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_CORE_INVALID_ARGUMENT,
                       "spreadPoints não pode ser negativo",
                       StringFormat("spread=%.4f", m_spreadPoints));
         return false;
      }
      if(m_slippagePoints < 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_CORE_INVALID_ARGUMENT,
                       "slippagePoints não pode ser negativo",
                       StringFormat("slip=%.4f", m_slippagePoints));
         return false;
      }
      if(m_commissionPerLot < 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_CORE_INVALID_ARGUMENT,
                       "commissionPerLot não pode ser negativo",
                       StringFormat("comm=%.4f", m_commissionPerLot));
         return false;
      }
      // Swap pode ser negativo (custo) ou positivo (rendimento) — não valida sinal.
      return true;
   }

   // Fill price aplicando spread (metade para cada lado a partir do mid) e
   // slippage adverso ao trader. Caller passa pointValue = symbol.Point().
   // BUY paga acima do mid (ask + slippage); SELL recebe abaixo (bid - slippage).
   double FillPriceFor(ENUM_MKS_ORDER_SIDE side, double mid, double pointValue) const
   {
      double halfSpread = (m_spreadPoints / 2.0) * pointValue;
      double slip       = m_slippagePoints * pointValue;
      if(side == MKS_ORDER_BUY)
         return mid + halfSpread + slip;
      else
         return mid - halfSpread - slip;
   }

   // Comissão total para 'lots' lotes. Magnitude >= 0; P&L subtrai.
   double Commission(double lots) const
   {
      return m_commissionPerLot * lots;
   }

   // Swap acumulado para 'lots' lotes mantidos por 'days' dias.
   // Side determina qual taxa diária aplica.
   double SwapForDays(ENUM_MKS_ORDER_SIDE side, double lots, int days) const
   {
      double perDay = (side == MKS_ORDER_BUY) ? m_swapLongPerDay : m_swapShortPerDay;
      return perDay * lots * (double)days;
   }

   //--- Getters (testes/diagnóstico) ---
   double SpreadPoints()     const { return m_spreadPoints; }
   double SlippagePoints()   const { return m_slippagePoints; }
   double CommissionPerLot() const { return m_commissionPerLot; }
   double SwapLongPerDay()   const { return m_swapLongPerDay; }
   double SwapShortPerDay()  const { return m_swapShortPerDay; }
};

#endif // MKS_ULTIMATE_CORE_BROKER_CMKSCOSTMODEL_MQH
