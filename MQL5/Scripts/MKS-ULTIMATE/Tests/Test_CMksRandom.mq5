//+------------------------------------------------------------------+
//| @file           : Test_CMksRandom.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksRandom — RNG deterministico do
//|                   StressLab. Determinismo bit-a-bit, faixas,
//|                   distribuicoes (Bernoulli e Gaussiana com
//|                   tolerancia estatistica). Fase 7 ADR-019.
//| @depends_on     : StressLab/CMksRandom.mqh,
//|                   Core/Testing/Asserts.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksRandom.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/StressLab/CMksRandom.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>

#define RND_TOL 1e-12

//==================================================================
// Determinismo
//==================================================================

void Test_Rnd_SameSeedSameSequence()
{
   CMksRandom a(12345);
   CMksRandom b(12345);
   for(int i = 0; i < 100; i++)
   {
      uint ua = a.NextUInt();
      uint ub = b.NextUInt();
      MKS_ASSERT_TRUE(ua == ub, StringFormat("uint[%d] igual", i));
   }
}

void Test_Rnd_SeedResetRestarts()
{
   CMksRandom r(7777);
   uint first = r.NextUInt();
   for(int i = 0; i < 50; i++) r.NextUInt(); // avanca
   r.Seed(7777);
   uint afterReseed = r.NextUInt();
   MKS_ASSERT_TRUE(first == afterReseed, "Seed reset volta ao 1o valor");
}

void Test_Rnd_DifferentSeedsDifferentSequences()
{
   CMksRandom a(1);
   CMksRandom b(2);
   // Pelo menos 1 dos 10 primeiros precisa diferir
   bool anyDiff = false;
   for(int i = 0; i < 10; i++)
      if(a.NextUInt() != b.NextUInt()) { anyDiff = true; break; }
   MKS_ASSERT_TRUE(anyDiff, "seeds diferentes -> sequencias diferentes");
}

void Test_Rnd_SeedZeroBecomesNonZero()
{
   CMksRandom r(0);
   // Apenas garante que estado nao fica preso em 0 (LCG com state=0
   // produziria sequencia degenerada)
   MKS_ASSERT_TRUE(r.State() != 0, "seed=0 e normalizada");
   uint v = r.NextUInt();
   MKS_ASSERT_TRUE(v != 0, "primeiro NextUInt != 0");
}

//==================================================================
// Faixas
//==================================================================

void Test_Rnd_DoubleRange()
{
   CMksRandom r(42);
   for(int i = 0; i < 1000; i++)
   {
      double d = r.NextDouble();
      MKS_ASSERT_TRUE(d >= 0.0 && d < 1.0,
                      StringFormat("NextDouble[%d] em [0,1): %.6f", i, d));
   }
}

void Test_Rnd_DoubleOpenStrictlyPositive()
{
   CMksRandom r(42);
   for(int i = 0; i < 1000; i++)
   {
      double d = r.NextDoubleOpen();
      MKS_ASSERT_TRUE(d > 0.0 && d < 1.0,
                      StringFormat("NextDoubleOpen[%d] em (0,1): %.12f", i, d));
   }
}

void Test_Rnd_IntRangeInclusive()
{
   CMksRandom r(42);
   int minV = 5, maxV = 10;
   bool sawMin = false, sawMax = false;
   for(int i = 0; i < 5000; i++)
   {
      int v = r.NextInt(minV, maxV);
      MKS_ASSERT_TRUE(v >= minV && v <= maxV,
                      StringFormat("NextInt[%d]=%d fora de [5,10]", i, v));
      if(v == minV) sawMin = true;
      if(v == maxV) sawMax = true;
   }
   MKS_ASSERT_TRUE(sawMin, "min observado em 5000 amostras");
   MKS_ASSERT_TRUE(sawMax, "max observado em 5000 amostras");
}

//==================================================================
// Bernoulli
//==================================================================

void Test_Rnd_BoolZeroAlwaysFalse()
{
   CMksRandom r(42);
   for(int i = 0; i < 100; i++)
      MKS_ASSERT_FALSE(r.NextBool(0.0), "p=0 sempre false");
}

void Test_Rnd_BoolOneAlwaysTrue()
{
   CMksRandom r(42);
   for(int i = 0; i < 100; i++)
      MKS_ASSERT_TRUE(r.NextBool(1.0), "p=1 sempre true");
}

void Test_Rnd_BoolHalfApproximately()
{
   CMksRandom r(42);
   int trues = 0;
   int N = 10000;
   for(int i = 0; i < N; i++)
      if(r.NextBool(0.5)) trues++;
   double prop = (double)trues / N;
   MKS_ASSERT_TRUE(prop > 0.47 && prop < 0.53,
                   StringFormat("Bernoulli(0.5) ~ 0.5 (obs=%.4f)", prop));
}

//==================================================================
// Gaussiana
//==================================================================

void Test_Rnd_GaussianMeanZeroApprox()
{
   CMksRandom r(42);
   double sum = 0.0;
   int N = 10000;
   for(int i = 0; i < N; i++) sum += r.NextGaussian();
   double mean = sum / N;
   // Tolerancia: para N=10k a media deve ficar facilmente em |mean| < 0.05
   MKS_ASSERT_TRUE(MathAbs(mean) < 0.05,
                   StringFormat("Gaussian mean ~ 0 (obs=%.6f)", mean));
}

void Test_Rnd_GaussianStdevApprox()
{
   CMksRandom r(42);
   double samples[];
   int N = 10000;
   ArrayResize(samples, N);
   double sum = 0.0;
   for(int i = 0; i < N; i++) { samples[i] = r.NextGaussian(); sum += samples[i]; }
   double mean = sum / N;
   double sqSum = 0.0;
   for(int i = 0; i < N; i++) sqSum += (samples[i] - mean) * (samples[i] - mean);
   double stdev = MathSqrt(sqSum / (N - 1));
   MKS_ASSERT_TRUE(stdev > 0.96 && stdev < 1.04,
                   StringFormat("Gaussian stdev ~ 1 (obs=%.6f)", stdev));
}

void Test_Rnd_GaussianScaled()
{
   CMksRandom r(42);
   double sum = 0.0;
   int N = 10000;
   for(int i = 0; i < N; i++) sum += r.NextGaussian(100.0, 5.0);
   double mean = sum / N;
   MKS_ASSERT_TRUE(MathAbs(mean - 100.0) < 0.5,
                   StringFormat("Gaussian(100,5) mean ~ 100 (obs=%.4f)", mean));
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksRandom ===");

   MKS_RUN(Test_Rnd_SameSeedSameSequence);
   MKS_RUN(Test_Rnd_SeedResetRestarts);
   MKS_RUN(Test_Rnd_DifferentSeedsDifferentSequences);
   MKS_RUN(Test_Rnd_SeedZeroBecomesNonZero);

   MKS_RUN(Test_Rnd_DoubleRange);
   MKS_RUN(Test_Rnd_DoubleOpenStrictlyPositive);
   MKS_RUN(Test_Rnd_IntRangeInclusive);

   MKS_RUN(Test_Rnd_BoolZeroAlwaysFalse);
   MKS_RUN(Test_Rnd_BoolOneAlwaysTrue);
   MKS_RUN(Test_Rnd_BoolHalfApproximately);

   MKS_RUN(Test_Rnd_GaussianMeanZeroApprox);
   MKS_RUN(Test_Rnd_GaussianStdevApprox);
   MKS_RUN(Test_Rnd_GaussianScaled);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
