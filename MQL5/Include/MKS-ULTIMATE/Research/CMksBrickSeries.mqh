//+------------------------------------------------------------------+
//| @file           : CMksBrickSeries.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Research
//| @responsibility : Coletor + carregador de uma série grande de bricks do
//|                   HISTÓRICO (CopyTicks dia-a-dia sobre o mesmo builder
//|                   classic da produção), compartilhado pelas passadas de
//|                   research (Characterize/Payoff). Research-only, NÃO toca
//|                   o caminho de paridade/trading. Guarda dir/close/tempo/
//|                   magnitude por brick para as estatísticas puras.
//| @depends_on     : Core/RenkoBuilder/CMksRenkoBuilder.mqh,
//|                   Core/RenkoBuilder/CMksFixedBrickSizer.mqh,
//|                   Core/Types/RenkoGeometry.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/Brick.mqh, Core/Interfaces/IRenkoSink.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Research/CMksBrickSeries.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_RESEARCH_CMKSBRICKSERIES_MQH
#define MKS_ULTIMATE_RESEARCH_CMKSBRICKSERIES_MQH

#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksRenkoBuilder.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksFixedBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>

// Acumula por brick: direção (+1/-1), close matemático, **triggerPrice** (mid
// OBSERVADO no tick que fechou o brick — ADR-010; é o preço de fill realista,
// não o close fictício = eixo-1 do V5), tempo (msc), high/low (excursão real
// p/ stop/alvo intra-brick), M (thresholdsCrossed).
class CMksBrickSeriesCollector : public IRenkoSink
{
public:
   int    dir[];
   double close[];     // close MATEMÁTICO (open±S) — NÃO usar p/ R (fictício)
   double trigger[];   // mid observado no disparo (ADR-010) — preço de fill p/ R
   double high[];      // excursão máxima intra-brick
   double low[];       // excursão mínima intra-brick
   long   t[];
   int    m[];
   int    count;
   int    bull;
   int    bear;
   CMksBrickSeriesCollector() { count = 0; bull = 0; bear = 0; }
   void OnBrickClose(const MksBrick &b) override
   {
      int idx = count;
      ArrayResize(dir,     idx + 1, 8192);
      ArrayResize(close,   idx + 1, 8192);
      ArrayResize(trigger, idx + 1, 8192);
      ArrayResize(high,    idx + 1, 8192);
      ArrayResize(low,     idx + 1, 8192);
      ArrayResize(t,       idx + 1, 8192);
      ArrayResize(m,       idx + 1, 8192);
      dir[idx]     = b.IsBull() ? 1 : -1;
      close[idx]   = b.close;
      trigger[idx] = b.triggerPrice;
      high[idx]    = b.high;
      low[idx]     = b.low;
      t[idx]       = b.closeTimeMsc;
      m[idx]       = b.thresholdsCrossed;
      if(b.IsBull()) bull++; else bear++;
      count++;
   }
};

MksTick MksToMksTick(const MqlTick &mt, ulong seq)
{
   MksTick t;
   t.seq     = seq;
   t.timeMsc = mt.time_msc;
   t.bid     = mt.bid;
   t.ask     = mt.ask;
   t.last    = mt.last;
   t.volume  = (long)mt.volume;
   t.flags   = mt.flags;
   return t;
}

// Carrega a série de bricks do histórico [from,to] via CopyTicks dia-a-dia
// (memória limitada a 1 dia de ticks) alimentando o builder classic S=brickSize.
// Retorna nº de bricks, ou -1 se o sizer for inválido. Imprime progresso.
int MksLoadBrickSeries(const string symbol, datetime from, datetime to,
                       double brickSize, CMksBrickSeriesCollector &sink)
{
   MksRenkoGeometry geom = MksGeometryClassic();
   CMksFixedBrickSizer sizer(brickSize);
   MksError szErr;
   if(!sizer.Validate(szErr))
   {
      PrintFormat("sizer invalido: %s. Abortando.", szErr.ToString());
      return -1;
   }
   CMksRenkoBuilder builder(geom, GetPointer(sizer), GetPointer(sink));

   const long DAY = 86400000L;
   long fromMsc = (long)from * 1000, toMsc = (long)to * 1000;
   ulong seq = 0;
   long  totalTicks = 0;
   int   daysData = 0, daysEmpty = 0, dayIdx = 0;

   for(long dayStart = fromMsc; dayStart < toMsc; dayStart += DAY)
   {
      long dayEnd = (dayStart + DAY < toMsc) ? (dayStart + DAY) : toMsc;
      MqlTick ticks[];
      int nt = CopyTicksRange(symbol, ticks, COPY_TICKS_ALL,
                              (ulong)dayStart, (ulong)dayEnd);
      dayIdx++;
      if(nt <= 0) daysEmpty++;
      else
      {
         daysData++;
         totalTicks += nt;
         for(int i = 0; i < nt; i++)
         {
            seq++;
            MksTick mt = MksToMksTick(ticks[i], seq);
            MksError err;
            builder.IngestTick(mt, err); // erros/recovery internos (E3)
         }
      }
      if((dayIdx % 20) == 0)
         PrintFormat("... %d dias (comData=%d vazios=%d bricks=%d)",
                     dayIdx, daysData, daysEmpty, sink.count);
   }
   PrintFormat("ticks=%I64d  dias comData=%d vazios=%d  bricks=%d (BULL=%d BEAR=%d)",
               totalTicks, daysData, daysEmpty, sink.count, sink.bull, sink.bear);
   return sink.count;
}

#endif // MKS_ULTIMATE_RESEARCH_CMKSBRICKSERIES_MQH
