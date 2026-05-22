//+------------------------------------------------------------------+
//| @file           : CMksPercentRiskSizer.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Trade
//| @responsibility : Implementação de IPositionSizer que calcula lots
//|                   para arriscar uma fração percentual fixa do
//|                   balance em cada trade, dada a distância do SL.
//|                   Arredondamento por floor para VolumeStep (viés
//|                   conservador: nunca excede o risk% solicitado).
//| @depends_on     : Core/Interfaces/IPositionSizer.mqh,
//|                   Core/Interfaces/ISymbol.mqh,
//|                   Core/Interfaces/IAccount.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Trade/CMksPercentRiskSizer.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TRADE_CMKSPERCENTRISKSIZER_MQH
#define MKS_ULTIMATE_CORE_TRADE_CMKSPERCENTRISKSIZER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IPositionSizer.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IAccount.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Calcula lots para arriscar uma fração percentual fixa do balance
// em cada trade. Fórmula:
//
//   lotsRaw = (balance * riskPct / 100) /
//             (slDistancePoints * TickValue * Point / TickSize)
//   lots    = floor(lotsRaw / VolumeStep) * VolumeStep
//
// Floor (não round) é viés deliberadamente conservador: garante que
// o risk efetivo nunca excede o configurado, mesmo às custas de risk
// efetivo menor que o solicitado em alguns casos.
//
// "TickValue * Point / TickSize" expressa o valor monetário de 1
// ponto por 1 lot. Em ativos onde Point == TickSize (Forex padrão,
// XAUUSD), reduz-se a TickValue. Em ativos com TickSize > Point, a
// correção é necessária.
//
// Out-of-range é erro, não clamp (ADR-019). Caller que quer
// comportamento clamp deve compor wrappers sobre este sizer.
class CMksPercentRiskSizer : public IPositionSizer
{
private:
   ISymbol *m_symbol;
   IAccount *m_account;
   double   m_riskPercent; // em pontos percentuais — 1.0 significa 1%

public:
   // symbol/account: ponteiros — caller mantém ownership.
   // riskPercent: fração em pontos percentuais (1.0 == 1% do balance
   //              por trade). Deve ser > 0 e <= 100.
   CMksPercentRiskSizer(ISymbol *symbol,
                        IAccount *account,
                        double riskPercent)
   {
      m_symbol      = symbol;
      m_account     = account;
      m_riskPercent = riskPercent;
   }

   bool Validate(MksError &err) const override
   {
      if(m_symbol == NULL || m_account == NULL)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                       "symbol ou account nulo no construtor",
                       StringFormat("symbol=%s account=%s",
                                    m_symbol == NULL ? "null" : "ok",
                                    m_account == NULL ? "null" : "ok"));
         return false;
      }
      if(m_riskPercent <= 0.0 || m_riskPercent > 100.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                       "riskPercent deve estar em (0, 100]",
                       StringFormat("riskPercent=%.8f", m_riskPercent));
         return false;
      }
      double step = m_symbol.VolumeStep();
      double vMin = m_symbol.VolumeMin();
      double vMax = m_symbol.VolumeMax();
      if(step <= 0.0 || vMin <= 0.0 || vMax < vMin)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                       "símbolo com volume inválido",
                       StringFormat("step=%.8f min=%.8f max=%.8f",
                                    step, vMin, vMax));
         return false;
      }
      return true;
   }

   bool ComputeLots(double slDistancePoints,
                    double &lots,
                    MksError &err) override
   {
      lots = 0.0;
      if(slDistancePoints <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_INVALID_INPUT,
                       "slDistancePoints deve ser > 0",
                       StringFormat("slDistancePoints=%.8f",
                                    slDistancePoints));
         return false;
      }
      if(!Validate(err))
         return false;

      double balance   = m_account.Balance();
      double tickValue = m_symbol.TickValue();
      double tickSize  = m_symbol.TickSize();
      double point     = m_symbol.Point();
      double step      = m_symbol.VolumeStep();
      double vMin      = m_symbol.VolumeMin();
      double vMax      = m_symbol.VolumeMax();

      if(balance <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_INVALID_INPUT,
                       "balance da conta <= 0",
                       StringFormat("balance=%.8f", balance));
         return false;
      }
      if(tickValue <= 0.0 || tickSize <= 0.0 || point <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_INVALID_INPUT,
                       "TickValue/TickSize/Point inválidos no símbolo",
                       StringFormat("tickValue=%.8f tickSize=%.8f point=%.8f",
                                    tickValue, tickSize, point));
         return false;
      }

      // Valor monetário de 1 ponto por 1 lot, na moeda da conta.
      double moneyPerPointPerLot = tickValue * point / tickSize;
      if(moneyPerPointPerLot <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_INVALID_INPUT,
                       "moneyPerPointPerLot calculado <= 0",
                       StringFormat("tickValue=%.8f point=%.8f tickSize=%.8f",
                                    tickValue, point, tickSize));
         return false;
      }

      double riskAmount = balance * (m_riskPercent / 100.0);
      double lotsRaw    = riskAmount /
                          (slDistancePoints * moneyPerPointPerLot);

      // Floor para múltiplo de step. Conservador: nunca excede o
      // risk% solicitado, ainda que possa ficar abaixo.
      double lotsRounded = MathFloor(lotsRaw / step) * step;

      if(lotsRounded < vMin - 1e-12 || lotsRounded > vMax + 1e-12)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_OUT_OF_RANGE,
                       "lots calculado fora de [VolumeMin, VolumeMax]",
                       StringFormat("lotsRaw=%.8f lotsRounded=%.8f "
                                    "min=%.8f max=%.8f balance=%.2f "
                                    "riskPct=%.4f slPts=%.4f",
                                    lotsRaw, lotsRounded, vMin, vMax,
                                    balance, m_riskPercent,
                                    slDistancePoints));
         return false;
      }

      lots = lotsRounded;
      return true;
   }
};

#endif // MKS_ULTIMATE_CORE_TRADE_CMKSPERCENTRISKSIZER_MQH
