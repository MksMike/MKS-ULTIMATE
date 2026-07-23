//+------------------------------------------------------------------+
//| @file           : Test_CMksRenkoBuilder.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksRenkoBuilder — determinismo,
//|                   formação, reversão, multi-threshold, guarda de
//|                   tick inválido, limiar K, boundary de geometria.
//|                   Migrado para o framework Core/Testing (ADR-005).
//| @depends_on     : Core/RenkoBuilder/CMksRenkoBuilder.mqh,
//|                   Core/RenkoBuilder/CMksFixedBrickSizer.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksCapturingSink.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksRenkoBuilder.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksRenkoBuilder.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksFixedBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Output/CMksMultiSink.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksCapturingSink.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/FormingBrick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//+------------------------------------------------------------------+
//| Helpers de construção de tick                                     |
//+------------------------------------------------------------------+
MksTick MakeTick(double bid, double ask, ulong seq, long timeMsc)
{
   MksTick t;
   t.bid = bid;
   t.ask = ask;
   t.seq = seq;
   t.timeMsc = timeMsc;
   t.last = 0.0;
   t.volume = 0;
   return t;
}

MksTick MakeTickByMid(double mid, ulong seq, long timeMsc)
{
   return MakeTick(mid - 0.05, mid + 0.05, seq, timeMsc);
}

//+------------------------------------------------------------------+
//| 1. Determinismo — mesmo stream, mesma sequência de bricks         |
//+------------------------------------------------------------------+
void Test_Determinism()
{
   // Stream sintético de 60 ticks com mix:
   //   - BULL continuação contínua
   //   - reversão BULL→BEAR e BEAR continuação
   //   - jumps multi-threshold em ambos os sentidos
   //   - oscilações dentro da banda (sem brick)
   //   - 3 ticks inválidos esparsos (testa que estado não vaza entre runs)
   const int N = 60;
   MksTick ticks[60];
   for(int i = 0; i < N; i++)
   {
      // Ticks inválidos em posições esparsas (ask < bid)
      if(i == 17 || i == 31 || i == 42)
      {
         ticks[i] = MakeTick(2000.0 + i * 0.5, 1999.0 + i * 0.5, (ulong)(i + 1), (long)(1000 + i * 100));
         continue;
      }

      double mid;
      if(i < 10)         mid = 2000.0 + i * 5.0;                     // BULL continuação
      else if(i < 20)    mid = 2050.0 - (i - 10) * 3.0;              // reversão + BEAR
      else if(i == 25)   mid = 2070.0;                               // jump multi-threshold BULL
      else if(i < 30)    mid = 2065.0 + (i - 26) * 2.0;              // oscilação
      else if(i < 40)    mid = 2073.0 - (i - 30) * 4.0;              // BEAR
      else if(i == 45)   mid = 2010.0;                               // jump multi-threshold BEAR
      else if(i < 50)    mid = 2015.0 + (i - 46) * 2.5;              // oscilação
      else               mid = 2025.0 + (i - 50) * 4.0;              // BULL final

      ticks[i] = MakeTickByMid(mid, (ulong)(i + 1), (long)(1000 + i * 100));
   }

   CMksCapturingSink s1;
   CMksCapturingSink s2;
   CMksFixedBrickSizer sz1(10.0);
   CMksFixedBrickSizer sz2(10.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b1(geom, GetPointer(sz1), GetPointer(s1));
   CMksRenkoBuilder b2(geom, GetPointer(sz2), GetPointer(s2));

   MksError err;
   for(int i = 0; i < N; i++) b1.IngestTick(ticks[i], err);
   for(int i = 0; i < N; i++) b2.IngestTick(ticks[i], err);

   MKS_ASSERT_TRUE(s1.count > 0, "stream produz bricks");
   MKS_ASSERT_EQ_INT(s1.count, s2.count, "brick count");
   for(int i = 0; i < s1.count && i < s2.count; i++)
   {
      MKS_ASSERT_EQ_DOUBLE(s1.bricks[i].open,              s2.bricks[i].open,              StringFormat("b%d open", i));
      MKS_ASSERT_EQ_DOUBLE(s1.bricks[i].close,             s2.bricks[i].close,             StringFormat("b%d close", i));
      MKS_ASSERT_EQ_DOUBLE(s1.bricks[i].high,              s2.bricks[i].high,              StringFormat("b%d high", i));
      MKS_ASSERT_EQ_DOUBLE(s1.bricks[i].low,               s2.bricks[i].low,               StringFormat("b%d low", i));
      MKS_ASSERT_EQ_INT   ((int)s1.bricks[i].direction,    (int)s2.bricks[i].direction,    StringFormat("b%d direction", i));
      MKS_ASSERT_EQ_INT   (s1.bricks[i].thresholdsCrossed, s2.bricks[i].thresholdsCrossed, StringFormat("b%d M", i));
      MKS_ASSERT_EQ_DOUBLE(s1.bricks[i].triggerPrice,      s2.bricks[i].triggerPrice,      StringFormat("b%d triggerPrice", i));
      MKS_ASSERT_EQ_ULONG (s1.bricks[i].triggerTickId,     s2.bricks[i].triggerTickId,     StringFormat("b%d triggerTickId", i));
   }

   // Estado interno final também deve casar
   MksFormingBrick fb1 = b1.GetFormingBrick();
   MksFormingBrick fb2 = b2.GetFormingBrick();
   MKS_ASSERT_EQ_DOUBLE(fb1.open, fb2.open, "forming open match");
   MKS_ASSERT_EQ_DOUBLE(fb1.high, fb2.high, "forming high match");
   MKS_ASSERT_EQ_DOUBLE(fb1.low,  fb2.low,  "forming low match");
   MKS_ASSERT_EQ_INT((int)fb1.direction, (int)fb2.direction, "forming direction match");
   MKS_ASSERT_EQ_INT(b1.IsStreamCorrupt() ? 1 : 0, b2.IsStreamCorrupt() ? 1 : 0, "stream corrupt flag match");
}

//+------------------------------------------------------------------+
//| 2. Continuação BULL canônica (median S=10 → degrau 5)             |
//+------------------------------------------------------------------+
void Test_SeedCaptured()
{
   // E2.3: a ancora da escada = mid e seq do 1o tick que semeia o builder.
   MksRenkoGeometry geom = MksGeometryClassic();
   CMksFixedBrickSizer sizer(10.0);
   CMksCapturingSink sink;
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));
   MksError err;

   MKS_ASSERT_FALSE(b.HasSeed(), "sem tick: HasSeed=false");

   MksTick t0 = MakeTickByMid(2000.0, 7, 1000);
   b.IngestTick(t0, err);
   MKS_ASSERT_TRUE(b.HasSeed(), "apos 1o tick: HasSeed=true");
   MKS_ASSERT_NEAR_DOUBLE(2000.0, b.SeedMid(), 1e-9, "SeedMid = mid do 1o tick");
   MKS_ASSERT_EQ_ULONG((ulong)7, b.SeedTickSeq(), "SeedTickSeq = seq do 1o tick");

   // Ticks subsequentes (formam bricks) NAO mudam a ancora — a origem da serie
   // e o que valida comparabilidade, nao os reanchors posteriores.
   MksTick t1 = MakeTickByMid(2010.0, 8, 2000);
   MksTick t2 = MakeTickByMid(2020.0, 9, 3000);
   b.IngestTick(t1, err);
   b.IngestTick(t2, err);
   MKS_ASSERT_NEAR_DOUBLE(2000.0, b.SeedMid(), 1e-9, "SeedMid inalterado apos bricks");
   MKS_ASSERT_EQ_ULONG((ulong)7, b.SeedTickSeq(), "SeedTickSeq inalterado apos bricks");
}

void Test_BullContinuation()
{
   MksTick ticks[4];
   ticks[0] = MakeTickByMid(2000.0, 1, 1000);
   ticks[1] = MakeTickByMid(2005.0, 2, 2000);
   ticks[2] = MakeTickByMid(2010.0, 3, 3000);
   ticks[3] = MakeTickByMid(2015.0, 4, 4000);

   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));

   MksError err;
   for(int i = 0; i < 4; i++) b.IngestTick(ticks[i], err);

   MKS_ASSERT_EQ_INT(3, sink.count, "brick count");
   MKS_ASSERT_EQ_DOUBLE(2000.0, sink.bricks[0].open,  "b0 open");
   MKS_ASSERT_EQ_DOUBLE(2005.0, sink.bricks[0].close, "b0 close");
   MKS_ASSERT_EQ_INT(MKS_BRICK_BULL, (int)sink.bricks[0].direction, "b0 BULL");
   MKS_ASSERT_EQ_INT(1, sink.bricks[0].thresholdsCrossed, "b0 M=1");
   MKS_ASSERT_EQ_DOUBLE(2005.0, sink.bricks[1].open,  "b1 open");
   MKS_ASSERT_EQ_DOUBLE(2010.0, sink.bricks[1].close, "b1 close");
   MKS_ASSERT_EQ_DOUBLE(2010.0, sink.bricks[2].open,  "b2 open");
   MKS_ASSERT_EQ_DOUBLE(2015.0, sink.bricks[2].close, "b2 close");
}

//+------------------------------------------------------------------+
//| 3. Continuação BEAR canônica                                      |
//+------------------------------------------------------------------+
void Test_BearContinuation()
{
   MksTick ticks[4];
   ticks[0] = MakeTickByMid(2000.0, 1, 1000);
   ticks[1] = MakeTickByMid(1995.0, 2, 2000);
   ticks[2] = MakeTickByMid(1990.0, 3, 3000);
   ticks[3] = MakeTickByMid(1985.0, 4, 4000);

   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));

   MksError err;
   for(int i = 0; i < 4; i++) b.IngestTick(ticks[i], err);

   MKS_ASSERT_EQ_INT(3, sink.count, "brick count");
   MKS_ASSERT_EQ_INT(MKS_BRICK_BEAR, (int)sink.bricks[0].direction, "b0 BEAR");
   MKS_ASSERT_EQ_DOUBLE(2000.0, sink.bricks[0].open,  "b0 open");
   MKS_ASSERT_EQ_DOUBLE(1995.0, sink.bricks[0].close, "b0 close");
   MKS_ASSERT_EQ_DOUBLE(1990.0, sink.bricks[1].close, "b1 close");
   MKS_ASSERT_EQ_DOUBLE(1985.0, sink.bricks[2].close, "b2 close");
}

//+------------------------------------------------------------------+
//| 4. Reversão simples (M=1, único threshold)                        |
//+------------------------------------------------------------------+
void Test_SimpleReversal()
{
   MksTick ticks[5];
   ticks[0] = MakeTickByMid(2000.0, 1, 1000);
   ticks[1] = MakeTickByMid(2005.0, 2, 2000);
   ticks[2] = MakeTickByMid(2010.0, 3, 3000);
   ticks[3] = MakeTickByMid(2005.0, 4, 4000);
   ticks[4] = MakeTickByMid(2000.0, 5, 5000);

   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));

   MksError err;
   for(int i = 0; i < 5; i++) b.IngestTick(ticks[i], err);

   MKS_ASSERT_EQ_INT(4, sink.count, "brick count");
   MKS_ASSERT_EQ_INT(MKS_BRICK_BULL, (int)sink.bricks[1].direction, "b1 BULL");
   MKS_ASSERT_EQ_INT(MKS_BRICK_BEAR, (int)sink.bricks[2].direction, "b2 BEAR (reversal)");
   MKS_ASSERT_EQ_INT(1, sink.bricks[2].thresholdsCrossed, "b2 M=1");
   MKS_ASSERT_EQ_DOUBLE(2010.0, sink.bricks[2].open,  "b2 open=last close");
   MKS_ASSERT_EQ_DOUBLE(2005.0, sink.bricks[2].close, "b2 close=revThr");
   MKS_ASSERT_EQ_INT(MKS_BRICK_BEAR, (int)sink.bricks[3].direction, "b3 BEAR cont");
   MKS_ASSERT_EQ_DOUBLE(2000.0, sink.bricks[3].close, "b3 close");
}

//+------------------------------------------------------------------+
//| 5. Reversão multi-threshold (1 reversão + 3 continuações no       |
//|    mesmo tick — caso mais sutil; caminho intermediário some       |
//|    no triggerPrice por decisão da ADR-011 §5)                     |
//+------------------------------------------------------------------+
void Test_ReversalMultiThreshold()
{
   MksTick ticks[4];
   ticks[0] = MakeTickByMid(2000.0, 1, 1000);
   ticks[1] = MakeTickByMid(2005.0, 2, 2000);
   ticks[2] = MakeTickByMid(2010.0, 3, 3000);
   ticks[3] = MakeTickByMid(1990.0, 4, 4000); // big drop: rev(2005) + cont(2000) + cont(1995) + cont(1990) = M=4 BEAR

   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));

   MksError err;
   for(int i = 0; i < 4; i++) b.IngestTick(ticks[i], err);

   MKS_ASSERT_EQ_INT(3, sink.count, "brick count (2 BULL + 1 multi BEAR)");
   MKS_ASSERT_EQ_INT(MKS_BRICK_BEAR, (int)sink.bricks[2].direction, "b2 BEAR (multi)");
   MKS_ASSERT_EQ_INT(4, sink.bricks[2].thresholdsCrossed, "b2 M=4");
   MKS_ASSERT_EQ_DOUBLE(2010.0, sink.bricks[2].open,  "b2 open=last bull close");
   MKS_ASSERT_EQ_DOUBLE(1990.0, sink.bricks[2].close, "b2 close=4th threshold");
   MKS_ASSERT_EQ_DOUBLE(1990.0, sink.bricks[2].triggerPrice, "b2 triggerPrice=mid (final, não 2005)");
   MKS_ASSERT_EQ_DOUBLE(0.0, sink.bricks[2].Overshoot(), "b2 overshoot=0 (mid==4th threshold)");
   MKS_ASSERT_EQ_DOUBLE(2010.0, sink.bricks[2].high, "b2 high=open (no wick acima)");
   MKS_ASSERT_EQ_DOUBLE(1990.0, sink.bricks[2].low,  "b2 low=close (no wick abaixo)");
}

//+------------------------------------------------------------------+
//| 6. Multi-threshold BULL puro (1º brick, sem reversão)             |
//+------------------------------------------------------------------+
void Test_BullMultiThreshold()
{
   MksTick ticks[2];
   ticks[0] = MakeTickByMid(2000.0, 1, 1000);
   ticks[1] = MakeTickByMid(2015.0, 2, 2000); // M=3: thresholds 2005, 2010, 2015

   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));

   MksError err;
   for(int i = 0; i < 2; i++) b.IngestTick(ticks[i], err);

   MKS_ASSERT_EQ_INT(1, sink.count, "brick count");
   MKS_ASSERT_EQ_INT(MKS_BRICK_BULL, (int)sink.bricks[0].direction, "BULL");
   MKS_ASSERT_EQ_INT(3, sink.bricks[0].thresholdsCrossed, "M=3");
   MKS_ASSERT_EQ_DOUBLE(2000.0, sink.bricks[0].open,  "open");
   MKS_ASSERT_EQ_DOUBLE(2015.0, sink.bricks[0].close, "close");
   MKS_ASSERT_EQ_DOUBLE(2015.0, sink.bricks[0].triggerPrice, "triggerPrice");
   MKS_ASSERT_EQ_DOUBLE(0.0,    sink.bricks[0].Overshoot(),  "overshoot=0");
}

//+------------------------------------------------------------------+
//| 7. Overshoot — close matemático ≠ mid; triggerPrice carrega mid   |
//+------------------------------------------------------------------+
void Test_Overshoot()
{
   MksTick ticks[2];
   ticks[0] = MakeTickByMid(2000.0, 1, 1000);
   ticks[1] = MakeTickByMid(2007.0, 2, 2000); // contThr=2005, mid=2007 → close=2005, overshoot=2

   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));

   MksError err;
   for(int i = 0; i < 2; i++) b.IngestTick(ticks[i], err);

   MKS_ASSERT_EQ_INT(1, sink.count, "brick count");
   MKS_ASSERT_EQ_DOUBLE(2005.0, sink.bricks[0].close, "close=math threshold");
   MKS_ASSERT_EQ_DOUBLE(2007.0, sink.bricks[0].triggerPrice, "triggerPrice=mid");
   MKS_ASSERT_EQ_DOUBLE(2.0,    sink.bricks[0].Overshoot(),  "overshoot=2");
   MKS_ASSERT_EQ_DOUBLE(2005.0, sink.bricks[0].high, "high=close (no extremo prévio)");
   MKS_ASSERT_EQ_DOUBLE(2000.0, sink.bricks[0].low,  "low=open");
}

//+------------------------------------------------------------------+
//| 8. GetFormingBrick após emissão captura overshoot                 |
//+------------------------------------------------------------------+
void Test_FormingBrickAfterEmission()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));

   MksError err;
   MksTick t1 = MakeTickByMid(2000.0, 1, 1000);
   b.IngestTick(t1, err);

   MksTick t2 = MakeTickByMid(2007.0, 2, 2000); // emite, mid=2007, walkClose=2005
   b.IngestTick(t2, err);

   MksFormingBrick fb = b.GetFormingBrick();
   MKS_ASSERT_TRUE(fb.hasData, "hasData");
   MKS_ASSERT_EQ_DOUBLE(2005.0, fb.open, "forming open = last close");
   MKS_ASSERT_EQ_DOUBLE(2007.0, fb.high, "forming high = MathMax(walkClose, mid)");
   MKS_ASSERT_EQ_DOUBLE(2005.0, fb.low,  "forming low  = MathMin(walkClose, mid)");
   MKS_ASSERT_EQ_INT(MKS_BRICK_BULL, (int)fb.direction, "forming direction");
}

//+------------------------------------------------------------------+
//| 9. Boundary de geometria — PO/PRO próximos do limite              |
//+------------------------------------------------------------------+
void Test_BoundaryGeometry()
{
   // PO/PRO no limite (close to 1.0 strict bound); revSizeRatio=1.0 mantém
   // o degrau de reversão simétrico ao de continuação. O foco do teste é
   // PO/PRO, não o ratio — usa default para reduzir variáveis.
   MksRenkoGeometry g = MksGeometryCustom(0.99, 0.99, 1.0);
   MksError vErr;
   MKS_ASSERT_TRUE(g.Validate(vErr), "geom extrema valida");

   // contThr offset = (1-0.99)*10 = 0.1
   MksTick ticks[2];
   ticks[0] = MakeTickByMid(2000.00, 1, 1000);
   ticks[1] = MakeTickByMid(2000.10, 2, 2000); // exatamente no threshold

   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   CMksRenkoBuilder b(g, GetPointer(sizer), GetPointer(sink));

   MksError err;
   for(int i = 0; i < 2; i++) b.IngestTick(ticks[i], err);

   MKS_ASSERT_EQ_INT(1, sink.count, "brick count");
   MKS_ASSERT_EQ_DOUBLE(2000.10, sink.bricks[0].close, "close no threshold fino");
}

//+------------------------------------------------------------------+
//| 10. Guarda de tick inválido — 103 isolado, 104 stream corrupt     |
//+------------------------------------------------------------------+
void Test_InvalidTickGuard()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink)); // L=10 default

   MksError err;

   MksTick t1 = MakeTickByMid(2000.0, 1, 1000);
   MKS_ASSERT_TRUE(b.IngestTick(t1, err), "valid init returns true");
   MKS_ASSERT_FALSE(b.IsStreamCorrupt(), "not corrupt after init");

   MksTick t2 = MakeTick(2010.0, 2009.0, 2, 2000); // ask < bid
   MKS_ASSERT_FALSE(b.IngestTick(t2, err), "invalid returns false");
   MKS_ASSERT_EQ_INT(MKS_ERR_RENKO_INVALID_TICK, (int)err.code, "err=103");
   MKS_ASSERT_FALSE(b.IsStreamCorrupt(), "not corrupt after 1 invalid");

   MksTick t3 = MakeTickByMid(2005.0, 3, 3000);
   MKS_ASSERT_TRUE(b.IngestTick(t3, err), "valid resets counter, emits brick");
   MKS_ASSERT_EQ_INT(1, sink.count, "1 brick");

   for(int i = 0; i < 10; i++)
   {
      MksTick ti = MakeTick(2000.0 + i, 1999.0 + i, (ulong)(4 + i), (long)(4000 + i * 1000));
      bool ok = b.IngestTick(ti, err);
      MKS_ASSERT_FALSE(ok, StringFormat("invalid #%d returns false", i + 1));
      if(i < 9)
         MKS_ASSERT_EQ_INT(MKS_ERR_RENKO_INVALID_TICK, (int)err.code, StringFormat("invalid #%d err=103", i + 1));
      else
         MKS_ASSERT_EQ_INT(MKS_ERR_RENKO_TICK_STREAM_CORRUPT, (int)err.code, "10th invalid err=104");
   }

   MKS_ASSERT_TRUE(b.IsStreamCorrupt(), "corrupt após 10 invalids");

   MksTick tValid = MakeTickByMid(2010.0, 100, 100000);
   MKS_ASSERT_FALSE(b.IngestTick(tValid, err), "post-corrupt valid returns false");
   MKS_ASSERT_EQ_INT(MKS_ERR_RENKO_TICK_STREAM_CORRUPT, (int)err.code, "post-corrupt err=104");
}

//+------------------------------------------------------------------+
//| 11. Threshold K excedido — não emite, devolve 102                 |
//+------------------------------------------------------------------+
void Test_ThresholdLimitExceeded()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryMedian(); // degrau 5
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink), 10, 20); // K=20

   MksError err;
   MksTick t1 = MakeTickByMid(2000.0, 1, 1000);
   b.IngestTick(t1, err);

   // Salto pra cruzar 21 thresholds (5 cada): 2000 + 21*5 = 2105
   MksTick t2 = MakeTickByMid(2105.0, 2, 2000);
   bool ok = b.IngestTick(t2, err);
   MKS_ASSERT_FALSE(ok, "K exceeded returns false");
   MKS_ASSERT_EQ_INT(MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED, (int)err.code, "err=102");
   MKS_ASSERT_EQ_INT(0, sink.count, "no brick");

   // Tick normal subsequente: estado preservado, deve formar brick
   MksTick t3 = MakeTickByMid(2005.0, 3, 3000);
   MKS_ASSERT_TRUE(b.IngestTick(t3, err), "normal tick após K-exceeded works");
   MKS_ASSERT_EQ_INT(1, sink.count, "1 brick after recovery");
   MKS_ASSERT_EQ_DOUBLE(2005.0, sink.bricks[0].close, "close no threshold esperado");
}

//+------------------------------------------------------------------+
//| 12. Preset classic — body=S (sem overlap)                         |
//+------------------------------------------------------------------+
void Test_ClassicPreset()
{
   MksRenkoGeometry g = MksGeometryClassic(); // PO=0, PRO=0, revSizeRatio=1
   // S=10 → degrau (1-0)*10 = 10. Body = 10.

   MksTick ticks[3];
   ticks[0] = MakeTickByMid(2000.0, 1, 1000);
   ticks[1] = MakeTickByMid(2010.0, 2, 2000);
   ticks[2] = MakeTickByMid(2020.0, 3, 3000);

   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   CMksRenkoBuilder b(g, GetPointer(sizer), GetPointer(sink));

   MksError err;
   for(int i = 0; i < 3; i++) b.IngestTick(ticks[i], err);

   MKS_ASSERT_EQ_INT(2, sink.count, "brick count");
   MKS_ASSERT_EQ_DOUBLE(10.0, MathAbs(sink.bricks[0].close - sink.bricks[0].open), "b0 body = S");
   MKS_ASSERT_EQ_DOUBLE(2000.0, sink.bricks[0].open,  "b0 open");
   MKS_ASSERT_EQ_DOUBLE(2010.0, sink.bricks[0].close, "b0 close");
   MKS_ASSERT_EQ_DOUBLE(2010.0, sink.bricks[1].open,  "b1 open");
   MKS_ASSERT_EQ_DOUBLE(2020.0, sink.bricks[1].close, "b1 close");
}

//+------------------------------------------------------------------+
//| 13. Primeiro brick BEAR — direção definida por sinal do movimento |
//+------------------------------------------------------------------+
void Test_FirstBrickBear()
{
   MksTick ticks[2];
   ticks[0] = MakeTickByMid(2000.0, 1, 1000);
   ticks[1] = MakeTickByMid(1995.0, 2, 2000); // primeiro movimento desce → BEAR

   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));

   MksError err;
   for(int i = 0; i < 2; i++) b.IngestTick(ticks[i], err);

   MKS_ASSERT_EQ_INT(1, sink.count, "brick count");
   MKS_ASSERT_EQ_INT(MKS_BRICK_BEAR, (int)sink.bricks[0].direction, "BEAR");
   MKS_ASSERT_EQ_INT(1, sink.bricks[0].thresholdsCrossed, "M=1");
   MKS_ASSERT_EQ_DOUBLE(2000.0, sink.bricks[0].open,  "open");
   MKS_ASSERT_EQ_DOUBLE(1995.0, sink.bricks[0].close, "close");
}

//+------------------------------------------------------------------+
//| 14. GetFormingBrick antes de qualquer tick — hasData=false        |
//+------------------------------------------------------------------+
void Test_FormingBrickBeforeAnyTick()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));

   MksFormingBrick fb = b.GetFormingBrick();
   MKS_ASSERT_FALSE(fb.hasData, "hasData=false antes de qualquer tick");
}

//==================================================================
// OnBrickForming — ADR-021
//==================================================================

//+------------------------------------------------------------------+
//| Antes de qualquer tick, OnBrickForming não foi chamado            |
//+------------------------------------------------------------------+
void Test_OnBrickForming_NotEmittedBeforeFirstTick()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(5.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));
   MKS_ASSERT_EQ_INT(0, sink.formingCount, "formingCount=0 antes de ticks");
}

//+------------------------------------------------------------------+
//| Cada tick válido emite uma chamada de OnBrickForming              |
//+------------------------------------------------------------------+
void Test_OnBrickForming_EmittedOnEachValidTick()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(5.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));
   MksError err;
   // 5 ticks válidos, mids dentro do band (não fecham brick)
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err);
   b.IngestTick(MakeTickByMid(2000.5, 2, 1100), err);
   b.IngestTick(MakeTickByMid(2001.0, 3, 1200), err);
   b.IngestTick(MakeTickByMid(2000.7, 4, 1300), err);
   b.IngestTick(MakeTickByMid(2001.5, 5, 1400), err);
   MKS_ASSERT_EQ_INT(5, sink.formingCount, "5 ticks = 5 formings");
}

//+------------------------------------------------------------------+
//| Tick inválido (ask < bid) NÃO dispara OnBrickForming              |
//+------------------------------------------------------------------+
void Test_OnBrickForming_NotEmittedOnInvalidTick()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(5.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));
   MksError err;
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err);     // válido
   b.IngestTick(MakeTick(2000.5, 1999.5, 2, 1100), err);  // inválido (ask < bid)
   b.IngestTick(MakeTickByMid(2001.0, 3, 1200), err);     // válido
   MKS_ASSERT_EQ_INT(2, sink.formingCount,
                     "só ticks válidos contam para forming");
}

//+------------------------------------------------------------------+
//| currentMid no fb captura o mid do último tick processado          |
//+------------------------------------------------------------------+
void Test_OnBrickForming_CurrentMidReflectsLastTick()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(5.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));
   MksError err;
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err);
   b.IngestTick(MakeTickByMid(2001.5, 2, 1100), err);
   b.IngestTick(MakeTickByMid(2002.7, 3, 1200), err);
   MKS_ASSERT_EQ_INT(3, sink.formingCount, "3 forming captures");
   MKS_ASSERT_NEAR_DOUBLE(2000.0, sink.formings[0].currentMid, 1e-9, "mid 1");
   MKS_ASSERT_NEAR_DOUBLE(2001.5, sink.formings[1].currentMid, 1e-9, "mid 2");
   MKS_ASSERT_NEAR_DOUBLE(2002.7, sink.formings[2].currentMid, 1e-9, "mid 3");
}

//+------------------------------------------------------------------+
//| SetEmitForming(false) suprime emissão                             |
//+------------------------------------------------------------------+
void Test_OnBrickForming_SuppressedWhenDisabled()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(5.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));
   MKS_ASSERT_TRUE(b.EmitForming(), "default true");
   b.SetEmitForming(false);
   MKS_ASSERT_FALSE(b.EmitForming(), "depois disable");
   MksError err;
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err);
   b.IngestTick(MakeTickByMid(2001.5, 2, 1100), err);
   MKS_ASSERT_EQ_INT(0, sink.formingCount, "0 formings quando desabilitado");
}

//+------------------------------------------------------------------+
//| Re-habilitar via flag volta a emitir                              |
//+------------------------------------------------------------------+
void Test_OnBrickForming_ReEnabledByFlag()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(5.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));
   MksError err;
   b.SetEmitForming(false);
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err);    // suprimido
   b.SetEmitForming(true);
   b.IngestTick(MakeTickByMid(2001.0, 2, 1100), err);    // emite
   b.IngestTick(MakeTickByMid(2002.0, 3, 1200), err);    // emite
   MKS_ASSERT_EQ_INT(2, sink.formingCount,
                     "2 formings após re-habilitar");
}

//+------------------------------------------------------------------+
//| Regressão: builder com MultiSink propaga OnBrickForming para     |
//| TODOS os sinks contidos. Cobre bug encontrado em 2026-05-22 onde |
//| MultiSink herdava o default vazio do IRenkoSink em vez de        |
//| delegar (ADR-021).                                                |
//+------------------------------------------------------------------+
void Test_OnBrickForming_PropagatesThroughMultiSink()
{
   CMksCapturingSink sinkA, sinkB;
   CMksMultiSink multi;
   multi.Add(GetPointer(sinkA));
   multi.Add(GetPointer(sinkB));
   CMksFixedBrickSizer sizer(5.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(multi));
   MksError err;
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err);
   b.IngestTick(MakeTickByMid(2001.0, 2, 1100), err);
   b.IngestTick(MakeTickByMid(2002.0, 3, 1200), err);
   MKS_ASSERT_EQ_INT(3, sinkA.formingCount, "sinkA recebe 3 formings");
   MKS_ASSERT_EQ_INT(3, sinkB.formingCount, "sinkB recebe 3 formings");
   MKS_ASSERT_NEAR_DOUBLE(sinkA.formings[2].currentMid,
                          sinkB.formings[2].currentMid, 1e-9,
                          "ambos os sinks recebem mesmo fb");
}

//+------------------------------------------------------------------+
//| Quando um tick fecha brick, OnBrickClose vem antes; OnBrickForming|
//| vem depois e reflete o NOVO state (open = close do brick fechado).|
//+------------------------------------------------------------------+
void Test_OnBrickForming_EmittedAfterBrickClose()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(5.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink));
   MksError err;
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err);   // init
   b.IngestTick(MakeTickByMid(2003.0, 2, 1100), err);   // forma brick BULL (close=2002.5)
   MKS_ASSERT_EQ_INT(1, sink.count, "1 brick fechado");
   MKS_ASSERT_EQ_INT(2, sink.formingCount, "2 formings (1 por tick)");
   // O 2o forming reflete novo state: open = close do brick fechado (2002.5).
   MKS_ASSERT_NEAR_DOUBLE(sink.bricks[0].close, sink.formings[1].open, 1e-9,
                          "forming.open == bricks[0].close após emissão");
}

//==================================================================
// Soft recovery de gap estrutural (código 105) — E3.1/E3.2/E3.3
// ADR-011 nota 2026-05-26 + ADR-033 (âncora deslizante). Todos usam
// classic (S=10, degrau 10), K=3, kRecoverAfter=3 para streams compactos.
//==================================================================

//+------------------------------------------------------------------+
//| E3.2 — rampa monotônica RECUPERA (não trava). Mids sobem em passos|
//| ≤ S mas se afastam de um lastClose stale. Com âncora FIXA o        |
//| recovery nunca dispararia (deadlock em 102); com deslizante,       |
//| dispara no K-ésimo. Falha no código antigo, passa após o fix.      |
//+------------------------------------------------------------------+
void Test_SoftRecovery_MonotonicRampRecovers()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryClassic();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink), 10, 3, 3);

   MksError err;
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err); // init (lastClose=2000)

   double ramp[] = {2100.0, 2106.0, 2113.0, 2120.0, 2127.0}; // passos ≤ 10
   int recoveryCount = 0;
   for(int i = 0; i < ArraySize(ramp); i++)
   {
      bool ok = b.IngestTick(MakeTickByMid(ramp[i], (ulong)(2 + i), (long)(2000 + i * 100)), err);
      if(!ok && err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP) recoveryCount++;
   }

   MKS_ASSERT_EQ_INT(1, recoveryCount, "exatamente 1 recovery (105) na rampa");
   MKS_ASSERT_FALSE(b.IsStreamCorrupt(), "builder não corrompeu");
   MKS_ASSERT_TRUE(sink.count >= 1, "forma brick após o recovery (não deadlock em 102)");
}

//+------------------------------------------------------------------+
//| E3.1 #1 — gap para platô: N mids agrupados → 1 recovery, reanchor  |
//| correto, e o PRÓXIMO movimento define a direção (sem reversão).    |
//+------------------------------------------------------------------+
void Test_SoftRecovery_LegitimateGapPlateau()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryClassic();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink), 10, 3, 3);

   MksError err;
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err); // init lastClose=2000

   double plateau[] = {2100.0, 2101.0, 2100.5};
   int recoveryCount = 0;
   double recoverMid = 0.0;
   for(int i = 0; i < ArraySize(plateau); i++)
   {
      bool ok = b.IngestTick(MakeTickByMid(plateau[i], (ulong)(2 + i), (long)(2000 + i * 100)), err);
      if(!ok && err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP) { recoveryCount++; recoverMid = plateau[i]; }
   }
   MKS_ASSERT_EQ_INT(1, recoveryCount, "exatamente 1 recovery no platô");
   MKS_ASSERT_EQ_DOUBLE(2100.5, recoverMid, "reanchor no 3º mid (2100.5)");
   MKS_ASSERT_EQ_INT(0, sink.count, "nenhum brick ainda (só reanchor)");

   // Próximo movimento para BAIXO define BEAR via primeiro brick (o reanchor
   // zerou hasFirstBrick — sem reversão).
   b.IngestTick(MakeTickByMid(2090.5, 10, 20000), err); // 2100.5 - 10 = 1 brick BEAR
   MKS_ASSERT_EQ_INT(1, sink.count, "1 brick pós-reanchor");
   MKS_ASSERT_EQ_INT(MKS_BRICK_BEAR, (int)sink.bricks[0].direction, "direção pelo novo movimento (BEAR), não reversão");
   MKS_ASSERT_EQ_DOUBLE(2100.5, sink.bricks[0].open,  "abre no mid reanchorado");
   MKS_ASSERT_EQ_DOUBLE(2090.5, sink.bricks[0].close, "fecha 1 brick abaixo");
}

//+------------------------------------------------------------------+
//| E3.1 #2 — spike isolado: 1 outlier + tick normal perto do          |
//| lastClose. O normal é aceito e zera o run → nenhum recovery.       |
//+------------------------------------------------------------------+
void Test_SoftRecovery_IsolatedSpikeNoRecovery()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryClassic();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink), 10, 3, 3);

   MksError err;
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err);  // init
   b.IngestTick(MakeTickByMid(2010.0, 2, 2000), err);  // brick BULL close 2010
   MKS_ASSERT_EQ_INT(1, sink.count, "1 brick inicial");

   int recoveryCount = 0;
   bool ok;
   ok = b.IngestTick(MakeTickByMid(2200.0, 3, 3000), err); // spike > K
   if(!ok && err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP) recoveryCount++;
   MKS_ASSERT_FALSE(ok, "spike rejeitado");
   MKS_ASSERT_EQ_INT(MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED, (int)err.code, "102, não 105");

   ok = b.IngestTick(MakeTickByMid(2012.0, 4, 4000), err); // volta perto do lastClose → aceito, run reset
   MKS_ASSERT_TRUE(ok, "tick normal após spike é aceito");

   ok = b.IngestTick(MakeTickByMid(2200.0, 5, 5000), err); // spike de novo, mas run já zerou
   if(!ok && err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP) recoveryCount++;
   b.IngestTick(MakeTickByMid(2012.0, 6, 6000), err);      // aceito de novo

   MKS_ASSERT_EQ_INT(0, recoveryCount, "nenhum recovery em spikes isolados");
   MKS_ASSERT_EQ_INT(1, sink.count, "lastClose preservado, nenhum brick do spike");
}

//+------------------------------------------------------------------+
//| E3.1 #3 — tick aceito no meio do run zera o contador: 4 rejeições  |
//| no total, mas nunca 3 CONSECUTIVAS → nenhum recovery.              |
//+------------------------------------------------------------------+
void Test_SoftRecovery_AcceptedTickResetsRun()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryClassic();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink), 10, 3, 3);

   MksError err;
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err); // init lastClose=2000

   int recoveryCount = 0;
   bool ok;
   ok = b.IngestTick(MakeTickByMid(2100.0, 2, 2000), err); // 102 run=1
   if(!ok && err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP) recoveryCount++;
   ok = b.IngestTick(MakeTickByMid(2103.0, 3, 3000), err); // 102 run=2
   if(!ok && err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP) recoveryCount++;
   ok = b.IngestTick(MakeTickByMid(2001.0, 4, 4000), err); // aceito perto do lastClose → run reset
   MKS_ASSERT_TRUE(ok, "tick aceito zera o run");
   ok = b.IngestTick(MakeTickByMid(2100.0, 5, 5000), err); // 102 run=1 de novo
   if(!ok && err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP) recoveryCount++;
   ok = b.IngestTick(MakeTickByMid(2103.0, 6, 6000), err); // 102 run=2
   if(!ok && err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP) recoveryCount++;

   MKS_ASSERT_EQ_INT(0, recoveryCount, "sem recovery: 4 rejeições, máx 2 consecutivas");
}

//+------------------------------------------------------------------+
//| E3.1 #4 — paridade pós-recovery: 2 builders no mesmo stream (com   |
//| um recovery no meio) → bricks idênticos, incl. triggerPrice/Id.    |
//+------------------------------------------------------------------+
void Test_SoftRecovery_Determinism()
{
   const int N = 8;
   MksTick ticks[8];
   double mids[] = {2000.0, 2010.0, 2100.0, 2104.0, 2108.0, 2118.0, 2128.0, 2115.0};
   for(int i = 0; i < N; i++)
      ticks[i] = MakeTickByMid(mids[i], (ulong)(i + 1), (long)(1000 + i * 100));

   CMksCapturingSink s1, s2;
   CMksFixedBrickSizer sz1(10.0), sz2(10.0);
   MksRenkoGeometry geom = MksGeometryClassic();
   CMksRenkoBuilder b1(geom, GetPointer(sz1), GetPointer(s1), 10, 3, 3);
   CMksRenkoBuilder b2(geom, GetPointer(sz2), GetPointer(s2), 10, 3, 3);

   MksError err;
   for(int i = 0; i < N; i++) b1.IngestTick(ticks[i], err);
   for(int i = 0; i < N; i++) b2.IngestTick(ticks[i], err);

   MKS_ASSERT_TRUE(s1.count > 0, "stream com recovery produz bricks");
   MKS_ASSERT_EQ_INT(s1.count, s2.count, "brick count idêntico");
   for(int i = 0; i < s1.count && i < s2.count; i++)
   {
      MKS_ASSERT_EQ_DOUBLE(s1.bricks[i].open,              s2.bricks[i].open,              StringFormat("b%d open", i));
      MKS_ASSERT_EQ_DOUBLE(s1.bricks[i].close,             s2.bricks[i].close,             StringFormat("b%d close", i));
      MKS_ASSERT_EQ_INT   ((int)s1.bricks[i].direction,    (int)s2.bricks[i].direction,    StringFormat("b%d dir", i));
      MKS_ASSERT_EQ_INT   (s1.bricks[i].thresholdsCrossed, s2.bricks[i].thresholdsCrossed, StringFormat("b%d M", i));
      MKS_ASSERT_EQ_DOUBLE(s1.bricks[i].triggerPrice,      s2.bricks[i].triggerPrice,      StringFormat("b%d trigPrice", i));
      MKS_ASSERT_EQ_ULONG (s1.bricks[i].triggerTickId,     s2.bricks[i].triggerTickId,     StringFormat("b%d trigId", i));
   }
   MksFormingBrick fb1 = b1.GetFormingBrick();
   MksFormingBrick fb2 = b2.GetFormingBrick();
   MKS_ASSERT_EQ_DOUBLE(fb1.open, fb2.open, "forming open match");
   MKS_ASSERT_EQ_INT((int)fb1.direction, (int)fb2.direction, "forming direction match");
}

//+------------------------------------------------------------------+
//| E3.3 — pós-reanchor a direção do forming volta ao inerte do        |
//| construtor (BULL), não fica stale na direção pré-gap (BEAR).       |
//+------------------------------------------------------------------+
void Test_SoftRecovery_ReanchorResetsDirection()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryClassic();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink), 10, 3, 3);

   MksError err;
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err); // init
   b.IngestTick(MakeTickByMid(1990.0, 2, 2000), err); // brick BEAR (close 1990)
   MKS_ASSERT_EQ_INT(MKS_BRICK_BEAR, (int)sink.bricks[0].direction, "brick inicial BEAR");
   MKS_ASSERT_EQ_INT(MKS_BRICK_BEAR, (int)b.GetFormingBrick().direction, "forming reflete BEAR pré-gap");

   double plateau[] = {2200.0, 2202.0, 2201.0}; // gap acima + platô → recovery
   int recoveryCount = 0;
   for(int i = 0; i < ArraySize(plateau); i++)
   {
      bool ok = b.IngestTick(MakeTickByMid(plateau[i], (ulong)(3 + i), (long)(3000 + i * 100)), err);
      if(!ok && err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP) recoveryCount++;
   }
   MKS_ASSERT_EQ_INT(1, recoveryCount, "1 recovery no platô");
   MKS_ASSERT_EQ_INT(MKS_BRICK_BULL, (int)b.GetFormingBrick().direction,
                     "direção do forming volta ao inerte (BULL) pós-reanchor, não BEAR stale");
}

//+------------------------------------------------------------------+
//| E3 (blindagem do invariante, achado da revisão adversarial) — um   |
//| tick aceito EXATAMENTE no lastClose (caminho primeiro-brick        |
//| mid==lastClose) também zera o run de rejeições; senão duas janelas |
//| separadas por esse tick emendariam num recovery espúrio.           |
//+------------------------------------------------------------------+
void Test_SoftRecovery_MidEqualsLastCloseResetsRun()
{
   CMksCapturingSink sink;
   CMksFixedBrickSizer sizer(10.0);
   MksRenkoGeometry geom = MksGeometryClassic();
   CMksRenkoBuilder b(geom, GetPointer(sizer), GetPointer(sink), 10, 3, 3);

   MksError err;
   b.IngestTick(MakeTickByMid(2000.0, 1, 1000), err); // init lastClose=2000, hasFirstBrick=false

   int recoveryCount = 0;
   bool ok;
   ok = b.IngestTick(MakeTickByMid(2100.0, 2, 2000), err); // 102 run=1
   if(!ok && err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP) recoveryCount++;
   ok = b.IngestTick(MakeTickByMid(2103.0, 3, 3000), err); // 102 run=2
   if(!ok && err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP) recoveryCount++;
   ok = b.IngestTick(MakeTickByMid(2000.0, 4, 4000), err); // mid == lastClose → aceito, zera o run
   MKS_ASSERT_TRUE(ok, "tick no lastClose é aceito");
   ok = b.IngestTick(MakeTickByMid(2100.0, 5, 5000), err); // 102 run=1 (não 3)
   if(!ok && err.code == MKS_ERR_RENKO_RECOVERED_FROM_GAP) recoveryCount++;

   MKS_ASSERT_EQ_INT(0, recoveryCount, "tick no lastClose zera o run — sem recovery espúrio");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksRenkoBuilder ===");

   MKS_RUN(Test_Determinism);
   MKS_RUN(Test_SeedCaptured);
   MKS_RUN(Test_BullContinuation);
   MKS_RUN(Test_BearContinuation);
   MKS_RUN(Test_SimpleReversal);
   MKS_RUN(Test_ReversalMultiThreshold);
   MKS_RUN(Test_BullMultiThreshold);
   MKS_RUN(Test_Overshoot);
   MKS_RUN(Test_FormingBrickAfterEmission);
   MKS_RUN(Test_BoundaryGeometry);
   MKS_RUN(Test_InvalidTickGuard);
   MKS_RUN(Test_ThresholdLimitExceeded);
   MKS_RUN(Test_ClassicPreset);
   MKS_RUN(Test_FirstBrickBear);
   MKS_RUN(Test_FormingBrickBeforeAnyTick);

   // ADR-021 — OnBrickForming
   MKS_RUN(Test_OnBrickForming_NotEmittedBeforeFirstTick);
   MKS_RUN(Test_OnBrickForming_EmittedOnEachValidTick);
   MKS_RUN(Test_OnBrickForming_NotEmittedOnInvalidTick);
   MKS_RUN(Test_OnBrickForming_CurrentMidReflectsLastTick);
   MKS_RUN(Test_OnBrickForming_SuppressedWhenDisabled);
   MKS_RUN(Test_OnBrickForming_ReEnabledByFlag);
   MKS_RUN(Test_OnBrickForming_PropagatesThroughMultiSink);
   MKS_RUN(Test_OnBrickForming_EmittedAfterBrickClose);

   // Soft recovery de gap estrutural (105) — E3.1/E3.2/E3.3, ADR-033
   MKS_RUN(Test_SoftRecovery_MonotonicRampRecovers);
   MKS_RUN(Test_SoftRecovery_LegitimateGapPlateau);
   MKS_RUN(Test_SoftRecovery_IsolatedSpikeNoRecovery);
   MKS_RUN(Test_SoftRecovery_AcceptedTickResetsRun);
   MKS_RUN(Test_SoftRecovery_Determinism);
   MKS_RUN(Test_SoftRecovery_ReanchorResetsDirection);
   MKS_RUN(Test_SoftRecovery_MidEqualsLastCloseResetsRun);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
