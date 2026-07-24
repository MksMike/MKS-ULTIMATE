//+------------------------------------------------------------------+
//| @file           : Test_CMksBrickStats.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testa as medições PURAS de CMksBrickStats com
//|                   sequências sintéticas de resposta conhecida (trend
//|                   puro, alternância pura, casos mistos pré-computados
//|                   à mão). Um bug na estatística = edge falso; este
//|                   teste é a rede contra isso.
//| @depends_on     : Research/CMksBrickStats.mqh, Core/Testing/Asserts.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksBrickStats.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Research/CMksBrickStats.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>

//+------------------------------------------------------------------+
//| A. Run-length — trend puro: nunca reverte, P(continua)=1 em todo k |
//+------------------------------------------------------------------+
void Test_RunLength_PureTrend()
{
   int dir[] = {1, 1, 1, 1, 1};
   int cont[], rev[];
   MksStatRunLength(dir, 5, 4, cont, rev);
   MKS_ASSERT_EQ_INT(1, cont[1], "trend: cont[1]=1");
   MKS_ASSERT_EQ_INT(1, cont[4], "trend: cont[4]=1 (run cresce até 4)");
   MKS_ASSERT_EQ_INT(0, rev[1],  "trend: rev[1]=0");
   MKS_ASSERT_NEAR_DOUBLE(1.0, MksStatProb(cont[1], rev[1]), 1e-9, "trend: P(continua|1)=1");
}

//+------------------------------------------------------------------+
//| A. Run-length — alternância pura: sempre reverte em run==1         |
//+------------------------------------------------------------------+
void Test_RunLength_PureAlternation()
{
   int dir[] = {1, -1, 1, -1, 1};
   int cont[], rev[];
   MksStatRunLength(dir, 5, 4, cont, rev);
   MKS_ASSERT_EQ_INT(4, rev[1],  "alt: rev[1]=4");
   MKS_ASSERT_EQ_INT(0, cont[1], "alt: cont[1]=0");
   MKS_ASSERT_NEAR_DOUBLE(0.0, MksStatProb(cont[1], rev[1]), 1e-9, "alt: P(continua|1)=0");
}

//+------------------------------------------------------------------+
//| A. Run-length — misto: [1,1,-1,-1,1] → cont[1]=2, rev[2]=2         |
//+------------------------------------------------------------------+
void Test_RunLength_Mixed()
{
   int dir[] = {1, 1, -1, -1, 1};
   int cont[], rev[];
   MksStatRunLength(dir, 5, 4, cont, rev);
   MKS_ASSERT_EQ_INT(2, cont[1], "mix: cont[1]=2 (dois runs de 1 continuam)");
   MKS_ASSERT_EQ_INT(2, rev[2],  "mix: rev[2]=2 (dois runs de 2 revertem)");
   MKS_ASSERT_EQ_INT(0, rev[1],  "mix: rev[1]=0");
   MKS_ASSERT_EQ_INT(0, cont[2], "mix: cont[2]=0");
   MKS_ASSERT_NEAR_DOUBLE(1.0, MksStatProb(cont[1], rev[1]), 1e-9, "mix: P(|1)=1");
   MKS_ASSERT_NEAR_DOUBLE(0.0, MksStatProb(cont[2], rev[2]), 1e-9, "mix: P(|2)=0");
}

//+------------------------------------------------------------------+
//| A. Run-length — degenerado: n<2 não crasha, tudo zero              |
//+------------------------------------------------------------------+
void Test_RunLength_Degenerate()
{
   int dir[] = {1};
   int cont[], rev[];
   MksStatRunLength(dir, 1, 4, cont, rev);
   MKS_ASSERT_EQ_INT(0, cont[1], "n<2: cont[1]=0");
   MKS_ASSERT_EQ_INT(0, rev[1],  "n<2: rev[1]=0");
}

//+------------------------------------------------------------------+
//| MksStatHourOf — hora do dia com offset                            |
//+------------------------------------------------------------------+
void Test_HourOf()
{
   long t1h = 1L * 3600L * 1000L;   // 01:00
   MKS_ASSERT_EQ_INT(1, MksStatHourOf(t1h, 0),  "01:00 offset 0 → 1");
   MKS_ASSERT_EQ_INT(3, MksStatHourOf(t1h, 2),  "01:00 offset +2 → 3");
   MKS_ASSERT_EQ_INT(23, MksStatHourOf(t1h, -2), "01:00 offset -2 → 23 (wrap)");
}

//+------------------------------------------------------------------+
//| D. Hora do dia → continuação, buckets por hora do brick i-1        |
//+------------------------------------------------------------------+
void Test_HourOfDay_Buckets()
{
   long H1 = 1L * 3600L * 1000L;
   long H2 = 2L * 3600L * 1000L;
   long t[]   = {H1, H1, H2, H2};   // horas dos bricks: 1,1,2,2
   int  dir[] = {1, 1, -1, 1};      // trans: cont@h1, rev@h1, rev@h2
   int  cont[], rev[];
   MksStatHourOfDay(dir, t, 4, 0, cont, rev);
   MKS_ASSERT_EQ_INT(1, cont[1], "h1: cont=1");
   MKS_ASSERT_EQ_INT(1, rev[1],  "h1: rev=1");
   MKS_ASSERT_EQ_INT(1, rev[2],  "h2: rev=1");
   MKS_ASSERT_EQ_INT(0, cont[2], "h2: cont=0");
}

//+------------------------------------------------------------------+
//| C. Volatilidade (terciles) → continuação, 3 buckets pré-computados |
//+------------------------------------------------------------------+
void Test_VolatilityTerciles()
{
   // dt (i=1..6) = [100,10,60,20,80,40] → sorted [10,20,40,60,80,100]
   //   loThr=sorted[2]=40, hiThr=sorted[4]=80.
   // conditioning v=t[i-1]-t[i-2], i=2..6 usa dt[0..4]=[100,10,60,20,80]:
   //   i2 v100→bucket0, i3 v10→bucket2, i4 v60→bucket1, i5 v20→bucket2, i6 v80→bucket1.
   long t[]   = {0, 100, 110, 170, 190, 270, 310};
   int  dir[] = {1, 1, 1, 1, -1, -1, 1};
   //   i2 cont(bucket0), i3 cont(bucket2), i4 rev(bucket1), i5 cont(bucket2), i6 rev(bucket1)
   int  cont[], rev[];
   long loThr = 0, hiThr = 0;
   MksStatVolatilityTerciles(dir, t, 7, cont, rev, loThr, hiThr);
   MKS_ASSERT_EQ_LONG(40, loThr, "vol: loThr=40 (33 pct)");
   MKS_ASSERT_EQ_LONG(80, hiThr, "vol: hiThr=80 (66 pct)");
   MKS_ASSERT_EQ_INT(1, cont[0], "vol: bucket0 (baixa vol) cont=1");
   MKS_ASSERT_EQ_INT(2, cont[2], "vol: bucket2 (alta vol) cont=2");
   MKS_ASSERT_EQ_INT(2, rev[1],  "vol: bucket1 (media vol) rev=2");
}

//+------------------------------------------------------------------+
//| B. Regime — trend puro → bucket trend, sempre continua             |
//+------------------------------------------------------------------+
void Test_Regime_PureTrend()
{
   int dir[] = {1, 1, 1, 1, 1, 1, 1, 1, 1, 1};
   int cont[], rev[];
   MksStatRegime(dir, 10, 4, 0.6, cont, rev);
   MKS_ASSERT_TRUE(cont[0] > 0, "regime trend: cont[0]>0 (bucket trend)");
   MKS_ASSERT_EQ_INT(0, cont[1], "regime trend: bucket lateral vazio");
   MKS_ASSERT_EQ_INT(0, rev[0],  "regime trend: nunca reverte");
}

//+------------------------------------------------------------------+
//| B. Regime — alternância pura → bucket lateral, sempre reverte      |
//+------------------------------------------------------------------+
void Test_Regime_PureAlternation()
{
   int dir[] = {1, -1, 1, -1, 1, -1, 1, -1, 1, -1};
   int cont[], rev[];
   MksStatRegime(dir, 10, 4, 0.6, cont, rev);
   MKS_ASSERT_TRUE(rev[1] > 0, "regime alt: rev[1]>0 (bucket lateral)");
   MKS_ASSERT_EQ_INT(0, cont[1], "regime alt: lateral nunca continua");
   MKS_ASSERT_EQ_INT(0, rev[0],  "regime alt: bucket trend vazio");
}

//+------------------------------------------------------------------+
//| MksStatZ — z-score vs 0.5 (gate de significância)                 |
//+------------------------------------------------------------------+
void Test_StatZ()
{
   MKS_ASSERT_NEAR_DOUBLE(0.0,  MksStatZ(50, 50), 1e-9, "z: p=0.5 → 0");
   MKS_ASSERT_NEAR_DOUBLE(10.0, MksStatZ(100, 0), 1e-9, "z: p=1 N=100 → 10");
   MKS_ASSERT_NEAR_DOUBLE(5.0,  MksStatZ(75, 25), 1e-9, "z: p=.75 N=100 → 5");
   MKS_ASSERT_NEAR_DOUBLE(-5.0, MksStatZ(25, 75), 1e-9, "z: p=.25 N=100 → -5");
   MKS_ASSERT_NEAR_DOUBLE(0.0,  MksStatZ(0, 0),   1e-9, "z: sem amostra → 0");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksBrickStats ===");

   MKS_RUN(Test_StatZ);
   MKS_RUN(Test_RunLength_PureTrend);
   MKS_RUN(Test_RunLength_PureAlternation);
   MKS_RUN(Test_RunLength_Mixed);
   MKS_RUN(Test_RunLength_Degenerate);
   MKS_RUN(Test_HourOf);
   MKS_RUN(Test_HourOfDay_Buckets);
   MKS_RUN(Test_VolatilityTerciles);
   MKS_RUN(Test_Regime_PureTrend);
   MKS_RUN(Test_Regime_PureAlternation);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
