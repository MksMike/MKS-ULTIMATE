//+------------------------------------------------------------------+
//| @file           : ValidateBuilderOnRealTicks.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE
//| @responsibility : Valida CMksRenkoBuilder contra stream real de ticks
//|                   obtido via CopyTicksRange. Reporta agregados no
//|                   painel Experts. Slice 2 do ROADMAP. ADR-013
//|                   (símbolo via input, proveniência em runtime).
//| @depends_on     : Core/RenkoBuilder/CMksRenkoBuilder.mqh,
//|                   Core/RenkoBuilder/CMksFixedBrickSizer.mqh,
//|                   Core/Types/RenkoGeometry.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/Error.mqh,
//|                   Core/Interfaces/IRenkoSink.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/ValidateBuilderOnRealTicks.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksRenkoBuilder.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksFixedBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>

input string   InpSymbol         = "";    // vazio => _Symbol (ADR-013)
input datetime InpFrom           = 0;     // 0 => agora - 7 dias
input datetime InpTo             = 0;     // 0 => agora
input double   InpBrickSizePts   = 3.0;   // S=3 (produção XAUUSD median)
input int      InpGapThreshMin   = 30;    // dt entre ticks > N min => gap
input bool     InpPrintAllBricks = false; // imprime cada brick (verboso)

int g_digits = 2;

string Fmt(double p) { return DoubleToString(p, g_digits); }

// Buckets de thresholdsCrossed: 1 (normal), 2..5 (salto modesto),
// 6..10 (salto significativo), >10 (perto do limiar K=20).
class CAggregatorSink : public IRenkoSink
{
public:
   int totalBricks;
   int bullCount;
   int bearCount;
   int mEq1, m2to5, m6to10, mGt10;
   bool hasFirst;
   MksBrick first;
   MksBrick last;
   bool printAll;

   CAggregatorSink()
   {
      totalBricks = 0; bullCount = 0; bearCount = 0;
      mEq1 = 0; m2to5 = 0; m6to10 = 0; mGt10 = 0;
      hasFirst = false;
      printAll = false;
   }

   void OnBrickClose(const MksBrick &brick) override
   {
      totalBricks++;
      if(brick.IsBull()) bullCount++;
      else               bearCount++;
      int m = brick.thresholdsCrossed;
      if(m == 1)         mEq1++;
      else if(m <= 5)    m2to5++;
      else if(m <= 10)   m6to10++;
      else               mGt10++;
      if(!hasFirst) { first = brick; hasFirst = true; }
      last = brick;
      if(printAll)
      {
         PrintFormat("BRICK %s open=%s close=%s M=%d trigger=%s tickId=%I64u",
                     brick.IsBull() ? "BULL" : "BEAR",
                     Fmt(brick.open), Fmt(brick.close),
                     brick.thresholdsCrossed,
                     Fmt(brick.triggerPrice), brick.triggerTickId);
      }
   }
};

MksTick ToMksTick(const MqlTick &mt, ulong seq)
{
   MksTick t;
   t.seq     = seq;
   t.timeMsc = mt.time_msc;
   t.bid     = mt.bid;
   t.ask     = mt.ask;
   t.last    = mt.last;
   t.volume  = (long)mt.volume;
   return t;
}

void OnStart()
{
   string symbol = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;
   g_digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   datetime now  = TimeCurrent();
   datetime from = (InpFrom == 0) ? (datetime)(now - 7 * 24 * 3600) : InpFrom;
   datetime to   = (InpTo   == 0) ? now : InpTo;
   long fromMsc = (long)from * 1000;
   long toMsc   = (long)to   * 1000;

   string broker  = AccountInfoString(ACCOUNT_COMPANY);
   long   account = AccountInfoInteger(ACCOUNT_LOGIN);

   Print("");
   Print("=== ValidateBuilderOnRealTicks ===");
   PrintFormat("provenance: broker=\"%s\" account=%I64d symbol=%s digits=%d",
               broker, account, symbol, g_digits);
   PrintFormat("window: from=%s to=%s",
               TimeToString(from, TIME_DATE|TIME_MINUTES),
               TimeToString(to,   TIME_DATE|TIME_MINUTES));
   PrintFormat("config: S=%s preset=median gapThreshMin=%d printAll=%s",
               Fmt(InpBrickSizePts), InpGapThreshMin,
               (InpPrintAllBricks ? "true" : "false"));

   MqlTick ticks[];
   int n = CopyTicksRange(symbol, ticks, COPY_TICKS_ALL, fromMsc, toMsc);
   if(n <= 0)
   {
      PrintFormat("CopyTicksRange retornou %d. GetLastError=%d. Abortando.",
                  n, GetLastError());
      return;
   }
   PrintFormat("ticks carregados: %d", n);

   MksRenkoGeometry geom = MksGeometryMedian();
   CMksFixedBrickSizer sizer(InpBrickSizePts);
   MksError szErr;
   if(!sizer.Validate(szErr))
   {
      PrintFormat("sizer inválido: %s. Abortando.", szErr.ToString());
      return;
   }

   CAggregatorSink sink;
   sink.printAll = InpPrintAllBricks;
   CMksRenkoBuilder builder(geom, GetPointer(sizer), GetPointer(sink));

   // Builder B (diagnóstico, descartável): bid-driven em vez de mid-driven.
   // Viola intencionalmente a ADR-010 dentro deste script — apenas para
   // medir o quanto o spread variável contribui para a contagem mid-driven.
   // NÃO é candidato a alternativa arquitetural.
   CAggregatorSink sinkBid;
   sinkBid.printAll = false;
   CMksRenkoBuilder builderBid(geom, GetPointer(sizer), GetPointer(sinkBid));

   int err102Count = 0;
   int err103Count = 0;
   bool stream104  = false;
   int gapCount    = 0;
   double minMid   = 0.0, maxMid = 0.0;
   bool hasMid     = false;
   long prevTimeMsc = 0;
   bool hadPrev     = false;
   long gapThreshMsc = (long)InpGapThreshMin * 60L * 1000L;

   double spreadSum = 0.0;
   double spreadMin = 1e18;
   double spreadMax = 0.0;
   int spreadBuckets[5];
   ArrayInitialize(spreadBuckets, 0);
   int spreadValidCount = 0;

   for(int i = 0; i < n; i++)
   {
      MksTick mt = ToMksTick(ticks[i], (ulong)(i + 1));

      if(mt.IsValid())
      {
         double mid = (mt.bid + mt.ask) / 2.0;
         if(!hasMid) { minMid = mid; maxMid = mid; hasMid = true; }
         else { if(mid < minMid) minMid = mid; if(mid > maxMid) maxMid = mid; }

         double spread = mt.ask - mt.bid;
         spreadSum += spread;
         if(spread < spreadMin) spreadMin = spread;
         if(spread > spreadMax) spreadMax = spread;
         if(spread <= 0.5)      spreadBuckets[0]++;
         else if(spread <= 1.0) spreadBuckets[1]++;
         else if(spread <= 2.0) spreadBuckets[2]++;
         else if(spread <= 5.0) spreadBuckets[3]++;
         else                   spreadBuckets[4]++;
         spreadValidCount++;
      }

      if(hadPrev && (mt.timeMsc - prevTimeMsc) > gapThreshMsc)
      {
         gapCount++;
         PrintFormat("GAP detectado: dt=%.1fmin tick=%d time=%s",
                     (mt.timeMsc - prevTimeMsc) / 60000.0, i + 1,
                     TimeToString((datetime)(mt.timeMsc / 1000),
                                  TIME_DATE|TIME_MINUTES));
      }
      prevTimeMsc = mt.timeMsc;
      hadPrev = true;

      MksError err;
      bool ok = builder.IngestTick(mt, err);
      if(!ok)
      {
         if(err.code == MKS_ERR_RENKO_INVALID_TICK)
            err103Count++;
         else if(err.code == MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED)
         {
            err102Count++;
            PrintFormat("102 K-exceeded: tick=%d %s", i + 1, err.ToString());
         }
         else if(err.code == MKS_ERR_RENKO_TICK_STREAM_CORRUPT && !stream104)
         {
            stream104 = true;
            PrintFormat("104 stream corrupt: tick=%d %s", i + 1, err.ToString());
         }
      }

      MksTick mtBid = mt;
      mtBid.ask = mt.bid;
      MksError errBid;
      builderBid.IngestTick(mtBid, errBid);
   }

   Print("");
   Print("=== RELATORIO ===");
   PrintFormat("bricks: total=%d BULL=%d BEAR=%d",
               sink.totalBricks, sink.bullCount, sink.bearCount);
   PrintFormat("thresholdsCrossed: M=1: %d  M=2..5: %d  M=6..10: %d  M>10: %d",
               sink.mEq1, sink.m2to5, sink.m6to10, sink.mGt10);
   PrintFormat("erros: 102=%d 103=%d 104=%s",
               err102Count, err103Count, (stream104 ? "yes" : "no"));
   PrintFormat("gaps (dt > %dmin): count=%d", InpGapThreshMin, gapCount);
   PrintFormat("range de preço (mid): min=%s max=%s",
               Fmt(minMid), Fmt(maxMid));
   double spreadMean = (spreadValidCount > 0) ? spreadSum / spreadValidCount : 0.0;
   PrintFormat("spread (USD): min=%s max=%s mean=%s",
               Fmt(spreadMin), Fmt(spreadMax), Fmt(spreadMean));
   PrintFormat("spread buckets: <=0.5: %d  0.5-1.0: %d  1.0-2.0: %d  2.0-5.0: %d  >5.0: %d",
               spreadBuckets[0], spreadBuckets[1], spreadBuckets[2],
               spreadBuckets[3], spreadBuckets[4]);
   double ratio = (sinkBid.totalBricks > 0)
                  ? (double)sink.totalBricks / (double)sinkBid.totalBricks
                  : 0.0;
   PrintFormat("DIAG bricks bid-driven (ask:=bid): total=%d  mid/bid ratio=%.3f",
               sinkBid.totalBricks, ratio);
   if(sink.hasFirst)
   {
      PrintFormat("primeiro brick: %s open=%s close=%s M=%d time=%s",
                  sink.first.IsBull() ? "BULL" : "BEAR",
                  Fmt(sink.first.open), Fmt(sink.first.close),
                  sink.first.thresholdsCrossed,
                  TimeToString((datetime)(sink.first.closeTimeMsc / 1000),
                               TIME_DATE|TIME_MINUTES));
      PrintFormat("ultimo brick:    %s open=%s close=%s M=%d time=%s",
                  sink.last.IsBull() ? "BULL" : "BEAR",
                  Fmt(sink.last.open), Fmt(sink.last.close),
                  sink.last.thresholdsCrossed,
                  TimeToString((datetime)(sink.last.closeTimeMsc / 1000),
                               TIME_DATE|TIME_MINUTES));
   }
   Print("=== fim ===");
}
