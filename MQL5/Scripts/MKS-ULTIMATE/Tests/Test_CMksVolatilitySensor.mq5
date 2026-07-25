//+------------------------------------------------------------------+
//| @file           : Test_CMksVolatilitySensor.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes de CORREÇÃO (nível 1) do CMksVolatilitySensor
//|                   contra o CONTRATO C1-C6 do header, com feeds sintéticos
//|                   determinísticos. Nível 2 (confiabilidade em dado real:
//|                   monotonicidade realizada + clustering) é o script de
//|                   research ValidateVolSensor (separado).
//| @depends_on     : Core/Sensors/Volatility/CMksVolatilitySensor.mqh,
//|                   Core/Testing/Asserts.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksVolatilitySensor.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Sensors/Volatility/CMksVolatilitySensor.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>

#define T0 ((long)1780000000000)   // epoch msc base

// Warmup padrão: 1 brick inicial + 10 ciclos de dts {10s,20s,...,100s} =
// 100 dts na referência, distribuição uniforme conhecida. Retorna o t final.
long FeedCycleWarmup(CMksVolatilitySensor &s)
{
   long t = T0;
   s.OnBrick(t);
   for(int rep = 0; rep < 10; rep++)
      for(int k = 1; k <= 10; k++)
      {
         t += (long)k * 10000;
         s.OnBrick(t);
      }
   return t;
}

//+------------------------------------------------------------------+
//| Warmup incompleto → neutro (score 5, MEDIUM), confiança < 1        |
//+------------------------------------------------------------------+
void Test_WarmupNeutral()
{
   CMksVolatilitySensor s;
   s.OnBrick(T0);
   s.OnTick(T0 + 1000);
   MKS_ASSERT_NEAR_DOUBLE(5.0, s.Score(), 1e-9, "warmup: score neutro 5.0");
   MKS_ASSERT_EQ_INT((int)MKS_VOL_MEDIUM, (int)s.Level(), "warmup: MEDIUM");
   MKS_ASSERT_TRUE(s.Confidence() < 1.0, "warmup: confianca < 1");
}

//+------------------------------------------------------------------+
//| C1a — bricks rápidos (dt << referência) → score alto               |
//+------------------------------------------------------------------+
void Test_C1_FastBricksHighScore()
{
   CMksVolatilitySensor s;
   long t = FeedCycleWarmup(s);
   for(int i = 0; i < 20; i++) { t += 5000; s.OnBrick(t); }   // 5s: mais rápido que tudo
   MKS_ASSERT_TRUE(s.Score() > 6.0,
      StringFormat("C1a: bricks rapidos -> score alto (got %.2f)", s.Score()));
   MKS_ASSERT_TRUE((int)s.Level() >= (int)MKS_VOL_HIGH,
      "C1a: level >= HIGH apos rajada");
}

//+------------------------------------------------------------------+
//| C1b — bricks lentos (dt >> referência) → score baixo; fast > slow  |
//+------------------------------------------------------------------+
void Test_C1_SlowBricksLowScore()
{
   CMksVolatilitySensor s;
   long t = FeedCycleWarmup(s);
   for(int i = 0; i < 20; i++) { t += 5000; s.OnBrick(t); }
   double fastScore = s.Score();
   for(int i = 0; i < 10; i++) { t += 300000; s.OnBrick(t); } // 5min: mais lento que tudo
   double slowScore = s.Score();
   MKS_ASSERT_TRUE(slowScore < 3.0,
      StringFormat("C1b: bricks lentos -> score baixo (got %.2f)", slowScore));
   MKS_ASSERT_TRUE(fastScore > slowScore, "C1b: fast > slow (monotonicidade)");
}

//+------------------------------------------------------------------+
//| C2 — calmaria SEM novo brick derruba o score (gap via OnTick)      |
//+------------------------------------------------------------------+
void Test_C2_GapDropsScoreBeforeNextBrick()
{
   CMksVolatilitySensor s;
   long t = FeedCycleWarmup(s);
   for(int i = 0; i < 20; i++) { t += 5000; s.OnBrick(t); }
   double atBurst = s.Score();
   s.OnTick(t + 600000);   // 10min sem brick — mercado morreu AGORA
   double afterGap = s.Score();
   MKS_ASSERT_TRUE(afterGap < atBurst - 3.0,
      StringFormat("C2: gap derruba o score sem novo brick (%.2f -> %.2f)", atBurst, afterGap));
}

//+------------------------------------------------------------------+
//| C3 — histerese: score na banda nominal MEDIUM não derruba o HIGH   |
//+------------------------------------------------------------------+
void Test_C3_HysteresisHoldsLevel()
{
   CMksVolatilitySensor s;
   long t = FeedCycleWarmup(s);
   for(int i = 0; i < 20; i++) { t += 5000; s.OnBrick(t); }
   MKS_ASSERT_TRUE((int)s.Level() >= (int)MKS_VOL_HIGH, "C3: rajada -> >= HIGH");

   // Gap moderado → score ~4 (banda nominal MEDIUM), mas dentro da zona morta
   // da histerese → level SEGURA (não pisca).
   s.OnTick(t + 55000);
   double midScore = s.Score();
   MKS_ASSERT_TRUE(midScore > 3.0 && midScore < 6.0,
      StringFormat("C3: score na banda intermediaria (got %.2f)", midScore));
   MKS_ASSERT_TRUE((int)s.Level() >= (int)MKS_VOL_HIGH,
      "C3: HISTERESE — level segura HIGH com score nominal MEDIUM");

   // Gap enorme → score despenca de vez → level cede (LOW).
   s.OnTick(t + 2000000);
   MKS_ASSERT_EQ_INT((int)MKS_VOL_LOW, (int)s.Level(),
      "C3: score muito baixo vence a histerese -> LOW");
}

//+------------------------------------------------------------------+
//| C4 — adaptativo: no regime CALMO, dt 60s é "rápido" RELATIVO        |
//+------------------------------------------------------------------+
void Test_C4_AdaptiveToRegime()
{
   CMksVolatilitySensor s;   // refWindow 500
   long t = T0;
   s.OnBrick(t);
   for(int i = 0; i < 100; i++) { t += 10000;  s.OnBrick(t); }  // regime antigo: 10s (frenetico)
   for(int i = 0; i < 500; i++) { t += 100000; s.OnBrick(t); }  // regime novo: 100s (ref inteira vira calma)
   for(int i = 0; i < 5; i++)   { t += 60000;  s.OnBrick(t); }  // 60s: LENTO p/ o regime antigo...
   MKS_ASSERT_TRUE(s.Score() > 7.0,
      StringFormat("C4: 60s no regime calmo = ALTA relativa (got %.2f)", s.Score()));
}

//+------------------------------------------------------------------+
//| C6 — determinismo: mesmo stream → mesma saída                      |
//+------------------------------------------------------------------+
void Test_C6_Deterministic()
{
   CMksVolatilitySensor a, b;
   long ta = FeedCycleWarmup(a);
   long tb = FeedCycleWarmup(b);
   for(int i = 0; i < 30; i++)
   {
      long dt = (long)(5000 + (i % 7) * 20000);
      ta += dt; a.OnBrick(ta);
      tb += dt; b.OnBrick(tb);
      MKS_ASSERT_NEAR_DOUBLE(a.Score(), b.Score(), 1e-12,
         StringFormat("C6: score identico no passo %d", i));
      MKS_ASSERT_EQ_INT((int)a.Level(), (int)b.Level(),
         StringFormat("C6: level identico no passo %d", i));
   }
}

//+------------------------------------------------------------------+
//| C5 — estabilidade a parâmetro: halfLife 8 vs 12 concordam no claro  |
//+------------------------------------------------------------------+
void Test_C5_ParamStability()
{
   CMksVolatilitySensor a(8.0, 500, 1.0), b(12.0, 500, 1.0);
   long ta = FeedCycleWarmup(a);
   long tb = FeedCycleWarmup(b);
   for(int i = 0; i < 20; i++) { ta += 5000; a.OnBrick(ta); tb += 5000; b.OnBrick(tb); }
   MKS_ASSERT_TRUE(a.Score() > 6.0 && b.Score() > 6.0,
      StringFormat("C5: ambos leem rajada como alta (%.2f / %.2f)", a.Score(), b.Score()));
   MKS_ASSERT_TRUE(MathAbs(a.Score() - b.Score()) < 2.0,
      "C5: halfLife 8 vs 12 nao vira o mundo (delta < 2)");
}

//+------------------------------------------------------------------+
//| Metadado absoluto: dt constante 60s → 60 bricks/hora                |
//+------------------------------------------------------------------+
void Test_RawBricksPerHour()
{
   CMksVolatilitySensor s;
   long t = T0;
   s.OnBrick(t);
   for(int i = 0; i < 10; i++) { t += 60000; s.OnBrick(t); }
   MKS_ASSERT_NEAR_DOUBLE(60.0, s.RawBricksPerHour(), 1e-6,
      "raw: dt 60s constante = 60 bricks/hora");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksVolatilitySensor ===");

   MKS_RUN(Test_WarmupNeutral);
   MKS_RUN(Test_C1_FastBricksHighScore);
   MKS_RUN(Test_C1_SlowBricksLowScore);
   MKS_RUN(Test_C2_GapDropsScoreBeforeNextBrick);
   MKS_RUN(Test_C3_HysteresisHoldsLevel);
   MKS_RUN(Test_C4_AdaptiveToRegime);
   MKS_RUN(Test_C6_Deterministic);
   MKS_RUN(Test_C5_ParamStability);
   MKS_RUN(Test_RawBricksPerHour);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
