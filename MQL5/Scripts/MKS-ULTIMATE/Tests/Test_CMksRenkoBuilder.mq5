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

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksRenkoBuilder ===");

   MKS_RUN(Test_Determinism);
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

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
