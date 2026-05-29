//+------------------------------------------------------------------+
//| @file           : Test_CMksCustomSymbolSink_Timeline.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes da timeline híbrida do Custom Symbol
//|                   (ADR-023) + teto de drift (ADR-023-A). Valida a
//|                   função pura CMksCustomSymbolSink::ComputeBrickTime
//|                   nos cenários calmo / bump / cap / autocura, e o
//|                   teste de regressão do runaway que matou o CS em
//|                   2026-05-29 (bump sustentado → barra no futuro além
//|                   do limite do MT5).
//| @depends_on     : Core/Output/CMksCustomSymbolSink.mqh,
//|                   Core/Testing/Asserts.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksCustomSymbolSink_Timeline.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Output/CMksCustomSymbolSink.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>

// Tempo real base (epoch s) usado nos cenários. Valor arbitrário em 2026.
#define BASE  ((long)1780000000)
// Teto default da timeline: 6h em segundos.
#define DRIFT ((long)(6 * 3600))

//+------------------------------------------------------------------+
//| Test 1: mercado calmo — realTime vence, sem efeito do teto        |
//+------------------------------------------------------------------+
void Test_CalmMarketUsesRealTime()
{
   // nextBarTime no passado; realTime atual, bem abaixo do teto.
   datetime bt = CMksCustomSymbolSink::ComputeBrickTime(BASE * 1000, (datetime)(BASE - 100), DRIFT);
   MKS_ASSERT_EQ_LONG(BASE, bt, "calm: brickTime = realTime");
}

//+------------------------------------------------------------------+
//| Test 2: primeiro brick (nextBarTime=0) parte do tempo real        |
//+------------------------------------------------------------------+
void Test_FirstBrickFromEpochZero()
{
   datetime bt = CMksCustomSymbolSink::ComputeBrickTime(BASE * 1000, (datetime)0, DRIFT);
   MKS_ASSERT_EQ_LONG(BASE, bt, "first brick: realTime wins over epoch 0");
}

//+------------------------------------------------------------------+
//| Test 3: bump quando >1 brick/min, ainda sob o teto                |
//+------------------------------------------------------------------+
void Test_BumpWhenFasterThanOnePerMinute()
{
   // nextBarTime 60s à frente do real (brick anterior já adiantou um slot),
   // dentro da folga do teto → usa o bump, sem clamp.
   datetime bt = CMksCustomSymbolSink::ComputeBrickTime(BASE * 1000, (datetime)(BASE + 60), DRIFT);
   MKS_ASSERT_EQ_LONG(BASE + 60, bt, "bump: brickTime = nextBarTime");
}

//+------------------------------------------------------------------+
//| Test 4: teto trava o runaway                                      |
//+------------------------------------------------------------------+
void Test_CapClampsRunaway()
{
   // nextBarTime já 6h+10min à frente do real → clamp no teto realTime+6h.
   datetime bt = CMksCustomSymbolSink::ComputeBrickTime(BASE * 1000, (datetime)(BASE + DRIFT + 600), DRIFT);
   MKS_ASSERT_EQ_LONG(BASE + DRIFT, bt, "cap: brickTime clamped to realTime + drift");
}

//+------------------------------------------------------------------+
//| Test 5: na fronteira exata do teto não há clamp (condição é >)    |
//+------------------------------------------------------------------+
void Test_CapBoundaryNotClamped()
{
   datetime bt = CMksCustomSymbolSink::ComputeBrickTime(BASE * 1000, (datetime)(BASE + DRIFT), DRIFT);
   MKS_ASSERT_EQ_LONG(BASE + DRIFT, bt, "boundary: nextBarTime == cap → kept");
}

//+------------------------------------------------------------------+
//| Test 6: autocura — mercado desacelera, realTime ultrapassa o slot |
//+------------------------------------------------------------------+
void Test_SelfHealsWhenMarketSlows()
{
   // Estava grudado no teto (nextBarTime = BASE+DRIFT). Mercado parou; o tick
   // real agora chega bem além do slot grudado → realTime vence, drift ~0.
   long realNow = BASE + DRIFT + 5000;
   datetime bt = CMksCustomSymbolSink::ComputeBrickTime(realNow * 1000, (datetime)(BASE + DRIFT), DRIFT);
   MKS_ASSERT_EQ_LONG(realNow, bt, "self-heal: realTime wins again, drift back to ~0");
}

//+------------------------------------------------------------------+
//| Test 7: REGRESSÃO — runaway de 2026-05-29 fica limitado ao teto   |
//+------------------------------------------------------------------+
void Test_RegressionRunawayBoundedUnderSustainedBurst()
{
   // Reproduz o bug: milhares de bricks fechando NO MESMO minuto real (pior
   // caso, mercado frenético sustentado). Replica o laço do OnBrickClose:
   // brickTime = ComputeBrickTime(...); nextBarTime = brickTime + 60.
   // Sem teto, brickTime chegaria a BASE + 5000*60 (~3.5 dias adiante) e o MT5
   // recusaria CustomRatesUpdate. Com teto, o adianto nunca passa de DRIFT.
   const int N = 5000;
   datetime nextBarTime = 0;
   long maxDriftSeen = 0;
   for(int i = 0; i < N; i++)
   {
      datetime bt = CMksCustomSymbolSink::ComputeBrickTime(BASE * 1000, nextBarTime, DRIFT);
      long drift = (long)bt - BASE;
      if(drift > maxDriftSeen) maxDriftSeen = drift;
      nextBarTime = (datetime)((long)bt + 60);
   }
   MKS_ASSERT_TRUE(maxDriftSeen <= DRIFT, "regression: drift never exceeds the cap");
   MKS_ASSERT_EQ_LONG(DRIFT, maxDriftSeen, "regression: burst pins exactly at the cap");
}

//+------------------------------------------------------------------+
//| Test 8: pina no teto após DRIFT/60 bricks e ali permanece         |
//+------------------------------------------------------------------+
void Test_PinsAtCapAfterExpectedBricks()
{
   // Começando em nextBarTime=BASE (drift 0), cada brick no mesmo minuto soma
   // +60 de adianto. Após DRIFT/60 bumps o adianto atinge o teto e gruda.
   const int bricksToPin = (int)(DRIFT / 60); // 360 com 6h
   datetime nextBarTime = (datetime)BASE;
   datetime bt = 0;
   for(int i = 0; i <= bricksToPin; i++)
   {
      bt = CMksCustomSymbolSink::ComputeBrickTime(BASE * 1000, nextBarTime, DRIFT);
      nextBarTime = (datetime)((long)bt + 60);
   }
   MKS_ASSERT_EQ_LONG(BASE + DRIFT, bt, "pinned at cap after DRIFT/60 bricks");

   // Mais um brick no mesmo minuto continua grudado (sobrescreve o slot).
   datetime bt2 = CMksCustomSymbolSink::ComputeBrickTime(BASE * 1000, nextBarTime, DRIFT);
   MKS_ASSERT_EQ_LONG(BASE + DRIFT, bt2, "stays pinned (overwrite same slot)");
}

//+------------------------------------------------------------------+
//| Test 9: determinismo — mesma sequência → mesmas saídas            |
//+------------------------------------------------------------------+
void Test_Determinism()
{
   const int N = 500;
   datetime nbA = 0, nbB = 0;
   for(int i = 0; i < N; i++)
   {
      datetime a = CMksCustomSymbolSink::ComputeBrickTime(BASE * 1000, nbA, DRIFT);
      datetime b = CMksCustomSymbolSink::ComputeBrickTime(BASE * 1000, nbB, DRIFT);
      MKS_ASSERT_EQ_LONG(a, b, StringFormat("deterministic at step %d", i));
      nbA = (datetime)((long)a + 60);
      nbB = (datetime)((long)b + 60);
   }
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksCustomSymbolSink_Timeline ===");

   MKS_RUN(Test_CalmMarketUsesRealTime);
   MKS_RUN(Test_FirstBrickFromEpochZero);
   MKS_RUN(Test_BumpWhenFasterThanOnePerMinute);
   MKS_RUN(Test_CapClampsRunaway);
   MKS_RUN(Test_CapBoundaryNotClamped);
   MKS_RUN(Test_SelfHealsWhenMarketSlows);
   MKS_RUN(Test_RegressionRunawayBoundedUnderSustainedBurst);
   MKS_RUN(Test_PinsAtCapAfterExpectedBricks);
   MKS_RUN(Test_Determinism);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
