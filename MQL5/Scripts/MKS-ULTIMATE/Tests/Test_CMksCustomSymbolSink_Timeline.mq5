//+------------------------------------------------------------------+
//| @file           : Test_CMksCustomSymbolSink_Timeline.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes da timeline híbrida do Custom Symbol
//|                   (ADR-023) + teto de drift (ADR-023-A). Valida as
//|                   funções puras CMksCustomSymbolSink::ComputeBrickTime
//|                   (calmo / bump / cap / autocura + regressão do runaway
//|                   que matou o CS em 2026-05-29) e ApplyCloseTimeline
//|                   (E7.2: lastBarTime/nextBarTime só avançam no sucesso
//|                   do CustomRatesUpdate — falha não deriva a timeline).
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
//| Test 10: guarda de time>0 — barra em 1970 (time=0) NÃO é           |
//| renderável (corromperia o container do CS, bug 2026-07-22)         |
//+------------------------------------------------------------------+
void Test_GuardRejectsEpochZeroBarTime()
{
   MKS_ASSERT_FALSE(CMksCustomSymbolSink::IsRenderableBarTime((datetime)0),
                    "time=0 (1970.01.01) NAO é renderável — corromperia o CS");
   MKS_ASSERT_TRUE(CMksCustomSymbolSink::IsRenderableBarTime((datetime)1),
                   "time=1 é > 0 → renderável (guarda mínima em time=0)");
   MKS_ASSERT_TRUE(CMksCustomSymbolSink::IsRenderableBarTime((datetime)BASE),
                   "time válido é renderável");
}

//+------------------------------------------------------------------+
//| Test 11: OnBrickClose com tick REAL nunca produz time=0 — a       |
//| corrupção vem do forming (nextBarTime=0), não do close.           |
//+------------------------------------------------------------------+
void Test_CloseNeverEmitsEpochForValidTick()
{
   // Para QUALQUER closeTimeMsc>0, brickTime>0 — inclusive com nextBarTime=0
   // (1º brick). Prova que a guarda do close é pura defesa (tick real nunca a
   // dispara) e que a corrupção observada só pode vir do OnBrickForming.
   datetime a = CMksCustomSymbolSink::ComputeBrickTime(1000, (datetime)0, DRIFT);        // 1s desde epoch
   datetime b = CMksCustomSymbolSink::ComputeBrickTime(BASE * 1000, (datetime)0, DRIFT); // tick real
   MKS_ASSERT_TRUE(CMksCustomSymbolSink::IsRenderableBarTime(a),
                   "closeTimeMsc=1000 → brickTime>0 (close seguro)");
   MKS_ASSERT_TRUE(CMksCustomSymbolSink::IsRenderableBarTime(b),
                   "closeTimeMsc real → brickTime>0 (close seguro)");
}

//+------------------------------------------------------------------+
//| Test 12: corpo da caixinha (showWicks=false) — high/low = extremos |
//| do corpo (open/close), SEM pavio. Usado por close E forming.       |
//+------------------------------------------------------------------+
void Test_BoxBodyBoundsAreBodyExtremes()
{
   // Bull (open<close): high=close, low=open.
   MKS_ASSERT_NEAR_DOUBLE(4001.0, CMksCustomSymbolSink::BoxBodyHigh(4000.0, 4001.0), 1e-9, "bull: high=close");
   MKS_ASSERT_NEAR_DOUBLE(4000.0, CMksCustomSymbolSink::BoxBodyLow (4000.0, 4001.0), 1e-9, "bull: low=open");
   // Bear (open>close): high=open, low=close.
   MKS_ASSERT_NEAR_DOUBLE(4000.0, CMksCustomSymbolSink::BoxBodyHigh(4000.0, 3999.0), 1e-9, "bear: high=open");
   MKS_ASSERT_NEAR_DOUBLE(3999.0, CMksCustomSymbolSink::BoxBodyLow (4000.0, 3999.0), 1e-9, "bear: low=close");
}

//+------------------------------------------------------------------+
//| Test 13: ApplyCloseTimeline — SUCESSO avança lastBarTime E         |
//| nextBarTime (âncora no slot gravado + próximo slot mínimo).         |
//+------------------------------------------------------------------+
void Test_ApplyCloseTimeline_SuccessAdvancesBoth()
{
   datetime last = (datetime)(BASE - 500);
   datetime next = (datetime)(BASE - 440);
   CMksCustomSymbolSink::ApplyCloseTimeline(true, (datetime)BASE, last, next);
   MKS_ASSERT_EQ_LONG(BASE,      last, "success: lastBarTime = brickTime gravado");
   MKS_ASSERT_EQ_LONG(BASE + 60, next, "success: nextBarTime = brickTime + 60");
}

//+------------------------------------------------------------------+
//| Test 14: ApplyCloseTimeline — FALHA mantém AMBOS os slots (não      |
//| ancora o painter em barra vazia, não deriva a timeline).            |
//| Regressão do finding cs-recovery-advances-timeline-on-fail.         |
//+------------------------------------------------------------------+
void Test_ApplyCloseTimeline_FailureKeepsBoth()
{
   datetime last = (datetime)(BASE - 500);
   datetime next = (datetime)(BASE - 440);
   CMksCustomSymbolSink::ApplyCloseTimeline(false, (datetime)BASE, last, next);
   MKS_ASSERT_EQ_LONG(BASE - 500, last, "fail: lastBarTime NAO avança (âncora do painter)");
   MKS_ASSERT_EQ_LONG(BASE - 440, next, "fail: nextBarTime NAO avança (timeline não deriva)");
}

//+------------------------------------------------------------------+
//| Test 15: sequência sucesso→FALHA→sucesso — a falha NÃO consome o    |
//| slot nem empurra a timeline; o brick seguinte reusa o slot (sem     |
//| buraco). Contraste com o bug antigo (next avançava na falha).       |
//+------------------------------------------------------------------+
void Test_ApplyCloseTimeline_FailDoesNotDriftTimeline()
{
   // Brick 1 sucesso no slot BASE → last=BASE, next=BASE+60.
   datetime last = 0, next = 0;
   CMksCustomSymbolSink::ApplyCloseTimeline(true, (datetime)BASE, last, next);
   MKS_ASSERT_EQ_LONG(BASE,      last, "b1 ok: last=BASE");
   MKS_ASSERT_EQ_LONG(BASE + 60, next, "b1 ok: next=BASE+60");

   // Brick 2 FALHA (mesmo minuto real → brickTime seria o bump BASE+60). Com a
   // falha, NEM last NEM next mexem: o slot BASE+60 não é consumido por uma
   // barra que não foi gravada.
   CMksCustomSymbolSink::ApplyCloseTimeline(false, (datetime)(BASE + 60), last, next);
   MKS_ASSERT_EQ_LONG(BASE,      last, "b2 fail: last continua BASE (última barra REAL)");
   MKS_ASSERT_EQ_LONG(BASE + 60, next, "b2 fail: next continua BASE+60 (sem drift)");

   // Brick 3 sucesso REUSA o slot BASE+60 (a falha não empurrou a timeline).
   // No bug antigo, next teria virado BASE+120 na falha e o brick 3 pularia um
   // slot, abrindo buraco na série.
   CMksCustomSymbolSink::ApplyCloseTimeline(true, (datetime)(BASE + 60), last, next);
   MKS_ASSERT_EQ_LONG(BASE + 60,  last, "b3 ok: last=BASE+60 (slot reusado, sem buraco)");
   MKS_ASSERT_EQ_LONG(BASE + 120, next, "b3 ok: next=BASE+120");
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

   MKS_RUN(Test_GuardRejectsEpochZeroBarTime);
   MKS_RUN(Test_CloseNeverEmitsEpochForValidTick);
   MKS_RUN(Test_BoxBodyBoundsAreBodyExtremes);

   MKS_RUN(Test_ApplyCloseTimeline_SuccessAdvancesBoth);
   MKS_RUN(Test_ApplyCloseTimeline_FailureKeepsBoth);
   MKS_RUN(Test_ApplyCloseTimeline_FailDoesNotDriftTimeline);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
