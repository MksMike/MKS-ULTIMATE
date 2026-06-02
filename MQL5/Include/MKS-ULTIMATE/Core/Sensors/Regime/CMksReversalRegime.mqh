//+------------------------------------------------------------------+
//| @file           : CMksReversalRegime.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Sensors / Regime
//| @responsibility : Sub-componente do Caixote — detector de regime
//|                   por contagem de reversões de cor de brick.
//|
//|                   Score = reversals_in_window / (period - 1) ∈ [0..1]
//|                     ≈ 1.0 → bricks alternando a cada brick — lateral
//|                     ≈ 0.0 → bricks da mesma cor — trend pura
//|                     ≈ 0.5 → mix com alguma direção
//|
//|                   Não implementa ISensor — é peça consumida pelo
//|                   CMksCaixote (sensor composto), que sim implementa
//|                   ISensor. Aqui o contrato é minimalista: configurar
//|                   + computar score sobre uma janela.
//| @depends_on     : (autocontido — opera sobre arrays open/close já
//|                    lidos pelo indicador/sensor consumidor)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Sensors/Regime/CMksReversalRegime.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_SENSORS_REGIME_CMKSREVERSALREGIME_MQH
#define MKS_ULTIMATE_CORE_SENSORS_REGIME_CMKSREVERSALREGIME_MQH

class CMksReversalRegime
{
private:
   int    m_period;     // janela em bricks
   double m_threshold;  // score acima do qual classificamos como lateral

public:
   CMksReversalRegime(int period = 20, double threshold = 0.6)
   {
      m_period    = (period >= 2) ? period : 2;
      m_threshold = (threshold >= 0.0 && threshold <= 1.0) ? threshold : 0.6;
   }

   void Configure(int period, double threshold)
   {
      if(period >= 2)                                m_period    = period;
      if(threshold >= 0.0 && threshold <= 1.0)       m_threshold = threshold;
   }

   int    Period()    const { return m_period;    }
   double Threshold() const { return m_threshold; }

   //--- Computa score [0..1] sobre janela [endIdx-period+1 .. endIdx].
   //    Pré-condição (responsabilidade do caller): endIdx >= period - 1.
   //    Brick sem direção (close == open) é ignorado na contagem.
   double Compute(const double &open[], const double &close[], int endIdx) const
   {
      int reversals = 0;
      int prevDir   = 0;            // 0 = não definido, +1 = bull, -1 = bear
      int winStart  = endIdx - m_period + 1;

      for(int i = winStart; i <= endIdx; i++)
      {
         int dir;
         if(close[i] > open[i])      dir = +1;
         else if(close[i] < open[i]) dir = -1;
         else                         continue;  // brick sem direção

         if(prevDir != 0 && dir != prevDir)
            reversals++;

         prevDir = dir;
      }

      return (double)reversals / (double)(m_period - 1);
   }

   //--- Conveniência: aplica o threshold ao score.
   bool IsLateral(double score) const { return score >= m_threshold; }
};

#endif // MKS_ULTIMATE_CORE_SENSORS_REGIME_CMKSREVERSALREGIME_MQH