//+------------------------------------------------------------------+
//| @file           : CMksRandom.mqh
//| @project        : MKS-ULTIMATE
//| @module         : StressLab
//| @responsibility : Gerador de numeros pseudo-aleatorios deterministico
//|                   (LCG Numerical Recipes), seedavel por instancia.
//|                   Substituto canonico para MathRand() na ADR-024 §6
//|                   (estrategia replay-safe proibe RNG global). Usado
//|                   pelo CMksStressLabBroker (Fase 7) e por mocks de
//|                   teste que exigem sequencia conhecida.
//| @depends_on     : Nenhuma (tipos nativos)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/StressLab/CMksRandom.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_STRESSLAB_CMKSRANDOM_MQH
#define MKS_ULTIMATE_STRESSLAB_CMKSRANDOM_MQH

// LCG (Linear Congruential Generator). Parametros de Numerical Recipes:
//   next = (a * state + c) mod 2^32
//   a = 1664525, c = 1013904223
//
// Periodo: 2^32 (~4.3 bilhoes). Suficiente para qualquer sessao de
// backtest realista. Para crypto-quality fica fora do escopo — este
// gerador serve a simulacao reproduzivel, nao a seguranca.
//
// Determinismo: mesma seed → mesma sequencia, sempre. Duas instancias
// com a mesma seed produzem outputs identicos passo-a-passo. Esse
// invariante e o que permite golden tests do StressLab.
class CMksRandom
{
private:
   uint m_state;

   // Cache para Box-Muller (gera 2 gaussianas por chamada, retorna 1
   // e guarda a outra para a proxima).
   bool   m_hasSpareGaussian;
   double m_spareGaussian;

public:
   CMksRandom(uint seed = 42)
   {
      m_state = (seed == 0) ? 1u : seed; // seed=0 nao tem ordem util no LCG
      m_hasSpareGaussian = false;
      m_spareGaussian    = 0.0;
   }

   void Seed(uint seed)
   {
      m_state = (seed == 0) ? 1u : seed;
      m_hasSpareGaussian = false;
   }

   uint State() const { return m_state; }

   // Proximo uint em [0, 2^32). Avanco interno do LCG.
   uint NextUInt()
   {
      m_state = (uint)(1664525u * m_state + 1013904223u);
      return m_state;
   }

   // Proximo double em [0.0, 1.0). Resolucao 2^32.
   double NextDouble()
   {
      // Divide por 2^32 = 4294967296.0
      return (double)NextUInt() / 4294967296.0;
   }

   // Proximo double em (0.0, 1.0). Evita 0 exato para uso em log/Box-Muller.
   double NextDoubleOpen()
   {
      double v = NextDouble();
      // Se cair em 0 exato, retorna o menor positivo representavel
      // na granularidade do LCG (1 / 2^32).
      return (v <= 0.0) ? (1.0 / 4294967296.0) : v;
   }

   // Inteiro uniforme em [min, max] inclusivo.
   int NextInt(int min, int max)
   {
      if(max < min) { int t = min; min = max; max = t; }
      int range = max - min + 1;
      return min + (int)(NextDouble() * (double)range);
   }

   // Bernoulli: true com probabilidade p (clamped a [0,1]).
   bool NextBool(double p)
   {
      if(p <= 0.0) return false;
      if(p >= 1.0) return true;
      return NextDouble() < p;
   }

   // Normal(0,1) via Box-Muller. Retorna 2 valores por par de uniformes;
   // gerimos o cache internamente para nao desperdicar.
   double NextGaussian()
   {
      if(m_hasSpareGaussian)
      {
         m_hasSpareGaussian = false;
         return m_spareGaussian;
      }
      double u1 = NextDoubleOpen();
      double u2 = NextDoubleOpen();
      double mag = MathSqrt(-2.0 * MathLog(u1));
      double z0 = mag * MathCos(2.0 * M_PI * u2);
      double z1 = mag * MathSin(2.0 * M_PI * u2);
      m_spareGaussian    = z1;
      m_hasSpareGaussian = true;
      return z0;
   }

   // Normal(mean, stdev).
   double NextGaussian(double mean, double stdev)
   {
      return mean + stdev * NextGaussian();
   }
};

#endif // MKS_ULTIMATE_STRESSLAB_CMKSRANDOM_MQH
