//+------------------------------------------------------------------+
//| @file           : Test_CMksStressRunner.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksStressRunner (ADR-038, fatia 2) — o
//|                   orquestrador de um nível de estresse sobre feed
//|                   sintético. Cobre: Init monta o grafo; feed zigue-zague
//|                   gera bricks+flips+trades; duplo-run determinístico
//|                   (mesmo net byte-a-byte); slippage adverso degrada o net
//|                   vs None mantendo o nº de trades (fills piores, mesmas
//|                   decisões); symbol NULL falha o Init.
//| @depends_on     : Strategy/Runner/CMksStressRunner.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh,
//|                   Core/Types/Tick.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksStressRunner.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Strategy/Runner/CMksStressRunner.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>

#define SR_TOL 1e-6

//==================================================================
// Feed sintético: triângulo 2000<->2030 (10 bricks de 3.0 cada sentido),
// 4 ciclos. Cada ápice é uma reversão de cor → flip → trade. Passo de 1.0
// por tick (vários ticks por brick, realista). bid==ask (mid).
//==================================================================
void AppendTick(MksTick &arr[], double mid, ulong seq)
{
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n].seq     = seq;
   arr[n].timeMsc = (long)(seq * 1000);
   arr[n].bid     = mid;
   arr[n].ask     = mid;
   arr[n].last    = mid;
}

void GenZigzag(MksTick &out[])
{
   ArrayResize(out, 0);
   double mid = 2000.0;
   ulong  seq = 0;
   for(int c = 0; c < 4; c++)
   {
      for(int i = 0; i < 30; i++) { mid += 1.0; AppendTick(out, mid, ++seq); }
      for(int i = 0; i < 30; i++) { mid -= 1.0; AppendTick(out, mid, ++seq); }
   }
}

void RunFeed(CMksStressRunner &run, MksTick &ticks[])
{
   int n = ArraySize(ticks);
   for(int i = 0; i < n; i++)
      run.OnTick(ticks[i]);
}

// Config canônico do teste: SL grande (100000 pts) → fecha só por flip, então
// o nº de trades independe do slippage (isola a degradação de preço).
MksStressRunnerConfig MakeCfg()
{
   MksStressRunnerConfig cfg;   // defaults XAU classic
   cfg.slPoints = 100000.0;     // SL longe: sem auto-close por SL neste teste
   return cfg;
}

//==================================================================
// Init + corrida básica
//==================================================================

void Test_SR_InitAndRunNoneProducesTrades()
{
   CMksFakeSymbol sym;
   MksStressRunnerConfig cfg = MakeCfg();
   MksTick ticks[]; GenZigzag(ticks);

   CMksStressParams none;   // defaults = sem stress
   CMksStressRunner run(GetPointer(sym), cfg, none, "None");
   MksError err;
   MKS_ASSERT_TRUE(run.Init(err), "grafo do runner inicializa");

   RunFeed(run, ticks);
   CMksStressLabReport r = run.Report();

   MKS_ASSERT_TRUE(run.BricksSeen()  > 0, "feed gerou bricks");
   MKS_ASSERT_TRUE(run.TradesClosed() > 0, "feed gerou trades fechados (flips)");
   MKS_ASSERT_EQ_INT(run.TradesClosed(), r.tradesClosed, "report casa com o getter");
   MKS_ASSERT_NEAR_DOUBLE(0.0, r.slippageTotalPoints, SR_TOL, "None: zero slippage");
}

//==================================================================
// Determinismo — mesmo feed+config → mesmo report
//==================================================================

void Test_SR_DeterministicDoubleRun()
{
   CMksFakeSymbol sym;
   MksStressRunnerConfig cfg = MakeCfg();
   MksTick ticks[]; GenZigzag(ticks);
   CMksStressParams none;
   MksError err;

   CMksStressRunner a(GetPointer(sym), cfg, none, "None");
   MKS_ASSERT_TRUE(a.Init(err), "runner A init");
   RunFeed(a, ticks);
   CMksStressLabReport ra = a.Report();

   CMksStressRunner b(GetPointer(sym), cfg, none, "None");
   MKS_ASSERT_TRUE(b.Init(err), "runner B init");
   RunFeed(b, ticks);
   CMksStressLabReport rb = b.Report();

   MKS_ASSERT_EQ_INT(ra.tradesClosed, rb.tradesClosed, "duplo-run: mesmo nº de trades");
   MKS_ASSERT_NEAR_DOUBLE(ra.netPnLPoints, rb.netPnLPoints, SR_TOL,
                          "duplo-run: mesmo net (determinístico)");
}

//==================================================================
// Liga/desliga — slippage adverso degrada o net vs None
//==================================================================

void Test_SR_SlippageDegradesVsNone()
{
   CMksFakeSymbol sym;
   MksStressRunnerConfig cfg = MakeCfg();
   MksTick ticks[]; GenZigzag(ticks);
   MksError err;

   CMksStressParams none;
   CMksStressRunner base(GetPointer(sym), cfg, none, "None");
   MKS_ASSERT_TRUE(base.Init(err), "baseline init");
   RunFeed(base, ticks);
   CMksStressLabReport rBase = base.Report();

   CMksStressParams slip;                       // só slippage, determinístico
   slip.slippageDist = MKS_STRESS_DIST_FIXED;
   slip.slippageMean = 2.0;                     // 2 pts adversos por fill
   CMksStressRunner st(GetPointer(sym), cfg, slip, "SlipFixed");
   MKS_ASSERT_TRUE(st.Init(err), "stress init");
   RunFeed(st, ticks);
   CMksStressLabReport rSt = st.Report();

   MKS_ASSERT_TRUE(rBase.tradesClosed > 0, "baseline teve trades");
   MKS_ASSERT_EQ_INT(rBase.tradesClosed, rSt.tradesClosed,
                     "mesmo nº de trades (slippage não muda a decisão)");
   MKS_ASSERT_NEAR_DOUBLE(0.0, rBase.slippageTotalPoints, SR_TOL, "None sem slippage");
   MKS_ASSERT_TRUE(rSt.slippageTotalPoints > 0.0, "stress registrou slippage real");
   MKS_ASSERT_TRUE(rSt.netPnLPoints < rBase.netPnLPoints,
                   "slippage adverso degrada estritamente o net (fills piores)");
}

//==================================================================
// Guarda de wiring
//==================================================================

void Test_SR_NullSymbolInitFails()
{
   MksStressRunnerConfig cfg = MakeCfg();
   CMksStressParams none;
   CMksStressRunner run(NULL, cfg, none, "None");
   MksError err;
   MKS_ASSERT_FALSE(run.Init(err), "symbol NULL → Init falha (sem crash)");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksStressRunner ===");

   MKS_RUN(Test_SR_InitAndRunNoneProducesTrades);
   MKS_RUN(Test_SR_DeterministicDoubleRun);
   MKS_RUN(Test_SR_SlippageDegradesVsNone);
   MKS_RUN(Test_SR_NullSymbolInitFails);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
