//+------------------------------------------------------------------+
//| @file           : CMksFixedLotSizer.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Trade
//| @responsibility : Implementação de IPositionSizer com volume fixo.
//|                   Retorna o lots configurado independente da
//|                   distância do SL. Verifica em Validate() que o
//|                   lot é múltiplo do VolumeStep e está dentro
//|                   de [VolumeMin, VolumeMax] do símbolo.
//| @depends_on     : Core/Interfaces/IPositionSizer.mqh,
//|                   Core/Interfaces/ISymbol.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Trade/CMksFixedLotSizer.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TRADE_CMKSFIXEDLOTSIZER_MQH
#define MKS_ULTIMATE_CORE_TRADE_CMKSFIXEDLOTSIZER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IPositionSizer.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Tolerância para "lot é múltiplo de VolumeStep". MQL5 retorna doubles
// para VolumeMin/Max/Step — comparação direta falsifica positivos por
// erro de ponto-flutuante. 1e-9 é folgado para qualquer step real.
#define MKS_SIZER_STEP_TOL 1e-9

class CMksFixedLotSizer : public IPositionSizer
{
private:
   ISymbol *m_symbol;
   double   m_fixedLots;

   bool IsMultipleOfStep(double value, double step) const
   {
      if(step <= 0.0) return false;
      double q = value / step;
      double rounded = MathRound(q);
      return MathAbs(q - rounded) < MKS_SIZER_STEP_TOL;
   }

public:
   // symbol: ponteiro para ISymbol — caller mantém ownership.
   // fixedLots: volume a retornar. Deve ser > 0, múltiplo de
   // symbol.VolumeStep(), e estar em [VolumeMin, VolumeMax].
   CMksFixedLotSizer(ISymbol *symbol, double fixedLots)
   {
      m_symbol    = symbol;
      m_fixedLots = fixedLots;
   }

   bool Validate(MksError &err) const override
   {
      if(m_symbol == NULL)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                       "symbol nulo no construtor", "");
         return false;
      }
      if(m_fixedLots <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                       "fixedLots deve ser > 0",
                       StringFormat("fixedLots=%.8f", m_fixedLots));
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
      if(!IsMultipleOfStep(m_fixedLots, step))
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                       "fixedLots não é múltiplo de VolumeStep",
                       StringFormat("fixedLots=%.8f step=%.8f",
                                    m_fixedLots, step));
         return false;
      }
      if(m_fixedLots < vMin - MKS_SIZER_STEP_TOL ||
         m_fixedLots > vMax + MKS_SIZER_STEP_TOL)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_OUT_OF_RANGE,
                       "fixedLots fora de [VolumeMin, VolumeMax]",
                       StringFormat("fixedLots=%.8f min=%.8f max=%.8f",
                                    m_fixedLots, vMin, vMax));
         return false;
      }
      return true;
   }

   bool ComputeLots(double slDistancePoints,
                    double &lots,
                    MksError &err) override
   {
      if(slDistancePoints <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_SIZER_INVALID_INPUT,
                       "slDistancePoints deve ser > 0",
                       StringFormat("slDistancePoints=%.8f",
                                    slDistancePoints));
         lots = 0.0;
         return false;
      }
      if(!Validate(err))
      {
         lots = 0.0;
         return false;
      }
      lots = m_fixedLots;
      return true;
   }
};

#endif // MKS_ULTIMATE_CORE_TRADE_CMKSFIXEDLOTSIZER_MQH
