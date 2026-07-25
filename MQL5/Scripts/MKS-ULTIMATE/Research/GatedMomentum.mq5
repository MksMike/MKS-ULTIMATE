//+------------------------------------------------------------------+
//| @file           : GatedMomentum.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Research
//| @responsibility : Última cartada da DIREÇÃO (research-only): o momentum
//|                   (ride-to-flip) só paga quando o mercado TENDE. Testa se
//|                   GATE-ar por VOLATILIDADE trailing (entra só quando os
//|                   últimos W bricks formaram RÁPIDO = ativo/trending, sinal
//|                   FORWARD-preditível pois usa só bricks passados) torna o
//|                   momentum positivo E ESTÁVEL no tempo — inclusive dormente
//|                   (sem perder) nos períodos quietos onde o momentum amplo
//|                   morre. Se o vol-HI for positivo e estacionário → estratégia
//|                   "momentum quando ativo". Se não → direção esgotada.
//| @depends_on     : Research/CMksBrickStats.mqh, Research/CMksBrickSeries.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Research/GatedMomentum.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Research/CMksBrickStats.mqh>
#include <MKS-ULTIMATE/Research/CMksBrickSeries.mqh>

input string   InpSymbol       = "";      // vazio => _Symbol
input datetime InpFrom         = 0;
input datetime InpTo           = 0;
input int      InpDaysBack     = 365;
input double   InpBrickSizePts = 2.0;     // S (o de melhor EVnet foi 2.0)
input double   InpSpreadPoints = 240;     // custo escala: spread/brick
input double   InpSlipPoints   = 0;
input int      InpVolWindow    = 20;      // janela trailing p/ medir a vol de regime (bricks)
input int      InpTimeWindows  = 6;

// Preenche mHi/mMid/mLo por brick: regime de vol via dt dos últimos W bricks
// (dt pequeno = rápido = alta vol). Terciles sobre a série. i<W → nenhum.
void BuildVolRegime(const long &t[], int n, int W, bool &mHi[], bool &mMid[], bool &mLo[])
{
   ArrayResize(mHi, n); ArrayResize(mMid, n); ArrayResize(mLo, n);
   ArrayInitialize(mHi, false); ArrayInitialize(mMid, false); ArrayInitialize(mLo, false);
   if(n <= W + 3) return;

   long dtt[]; ArrayResize(dtt, n - W);
   for(int i = W; i < n; i++) dtt[i - W] = t[i] - t[i - W];
   long s[]; ArrayCopy(s, dtt); ArraySort(s);
   int m = n - W;
   long loT = s[m / 3];        // dt pequeno (fast)
   long hiT = s[2 * m / 3];

   for(int i = W; i < n; i++)
   {
      long d = t[i] - t[i - W];
      if(d <= loT)      mHi[i]  = true;   // rápido = alta vol
      else if(d >  hiT) mLo[i]  = true;   // lento = baixa vol
      else              mMid[i] = true;
   }
}

double g_costB = 0.0;

void ReportRegime(string label, const int &dir[], const double &cl[], int n,
                  const bool &mask[], double S)
{
   MksPayoff p;
   MksStatRideToFlip(dir, cl, n, mask, S, p);
   PrintFormat("  %-8s EVnet=%+.3f | EVgross=%+.3f t=%+6.1f win=%.3f avgW=%+.2f avgL=%+.2f N=%d",
               label, p.NetEV(g_costB), p.EV(), p.T(), p.WinRate(),
               p.AvgWin(), p.AvgLoss(), p.trades);
}

void OnStart()
{
   string symbol = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;
   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   datetime now  = TimeCurrent();
   datetime from = (InpFrom == 0) ? (datetime)(now - (long)InpDaysBack * 86400) : InpFrom;
   datetime to   = (InpTo   == 0) ? now : InpTo;

   double brickPoints = (point > 0.0) ? (InpBrickSizePts / point) : 0.0;
   g_costB = (brickPoints > 0.0) ? (InpSpreadPoints + InpSlipPoints) / brickPoints : 0.10;

   Print("");
   Print("=== GatedMomentum (momentum gate-ado por volatilidade) ===");
   PrintFormat("symbol=%s S=%.1f custo=%.3f brick janela=%s..%s volWindow=%d",
               symbol, InpBrickSizePts, g_costB,
               TimeToString(from, TIME_DATE), TimeToString(to, TIME_DATE), InpVolWindow);

   CMksBrickSeriesCollector sink;
   if(MksLoadBrickSeries(symbol, from, to, InpBrickSizePts, sink) < 0) return;
   int n = sink.count;
   if(n < 100) { Print("bricks insuficientes."); return; }

   bool mAll[]; ArrayResize(mAll, n); for(int i = 0; i < n; i++) mAll[i] = true;
   bool mHi[], mMid[], mLo[];
   BuildVolRegime(sink.t, n, InpVolWindow, mHi, mMid, mLo);

   Print("");
   Print("=== Momentum por REGIME de volatilidade (vol trailing dos ultimos W bricks) ===");
   Print("  hipotese: vol-HI (mercado ativo/trending) paga; vol-LO (quieto) nao.");
   ReportRegime("all",    sink.dir, sink.trigger, n, mAll, InpBrickSizePts);
   ReportRegime("vol-HI", sink.dir, sink.trigger, n, mHi,  InpBrickSizePts);
   ReportRegime("vol-MID", sink.dir, sink.trigger, n, mMid, InpBrickSizePts);
   ReportRegime("vol-LO", sink.dir, sink.trigger, n, mLo,  InpBrickSizePts);

   Print("");
   PrintFormat("=== ESTACIONARIDADE do vol-HI momentum por %d janelas ===", InpTimeWindows);
   Print("  paga QUANDO ativo (EVnet>0) e fica DORMENTE (N baixo) no quieto recente?");
   int pos = 0, active = 0;
   for(int w = 0; w < InpTimeWindows; w++)
   {
      int a = (int)((long)w * n / InpTimeWindows);
      int b = (int)((long)(w + 1) * n / InpTimeWindows);
      int wn = b - a; if(wn < 10) continue;
      int wdir[]; double wcl[]; bool wmask[];
      ArrayResize(wdir, wn); ArrayResize(wcl, wn); ArrayResize(wmask, wn);
      ArrayCopy(wdir, sink.dir, 0, a, wn);
      ArrayCopy(wcl,  sink.trigger, 0, a, wn);
      for(int i = 0; i < wn; i++) wmask[i] = mHi[a + i];   // vol-HI mask fatiada
      MksPayoff p; MksStatRideToFlip(wdir, wcl, wn, wmask, InpBrickSizePts, p);
      double ev = p.NetEV(g_costB);
      if(p.trades > 0) { active++; if(ev > 0) pos++; }
      PrintFormat("  win%d [%s..%s] EVnet=%+.3f t=%+.1f N_hi=%d%s",
                  w + 1, TimeToString((datetime)(sink.t[a] / 1000), TIME_DATE),
                  TimeToString((datetime)(sink.t[b - 1] / 1000), TIME_DATE),
                  ev, p.T(), p.trades, (p.trades > 0 && ev <= 0) ? "  <== NEG" : "");
   }
   PrintFormat("  >>> %d de %d janelas COM trades positivas.", pos, active);

   //--- TSV ---
   FolderCreate("MKS-ULTIMATE\\Research");
   int fh = FileOpen("MKS-ULTIMATE\\Research\\gated_momentum_" + symbol + ".tsv",
                     FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(fh != INVALID_HANDLE)
   {
      FileWrite(fh, StringFormat("# gated_momentum symbol=%s S=%.1f cost=%.3f volWindow=%d from=%s to=%s",
                symbol, InpBrickSizePts, g_costB, InpVolWindow, TimeToString(from), TimeToString(to)));
      FileWrite(fh, "regime\ttrades\twin\tev_gross\tev_net\tt");
      string lbl[] = {"all", "vol-HI", "vol-MID", "vol-LO"};
      for(int r = 0; r < 4; r++)
      {
         MksPayoff p;
         if(r==0) MksStatRideToFlip(sink.dir, sink.trigger, n, mAll, InpBrickSizePts, p);
         if(r==1) MksStatRideToFlip(sink.dir, sink.trigger, n, mHi,  InpBrickSizePts, p);
         if(r==2) MksStatRideToFlip(sink.dir, sink.trigger, n, mMid, InpBrickSizePts, p);
         if(r==3) MksStatRideToFlip(sink.dir, sink.trigger, n, mLo,  InpBrickSizePts, p);
         FileWrite(fh, StringFormat("%s\t%d\t%.4f\t%.4f\t%.4f\t%.2f",
                   lbl[r], p.trades, p.WinRate(), p.EV(), p.NetEV(g_costB), p.T()));
      }
      FileWrite(fh, "statwin_hi_from\tto\tev_net\tt\tn_hi");
      for(int w = 0; w < InpTimeWindows; w++)
      {
         int a = (int)((long)w * n / InpTimeWindows);
         int b = (int)((long)(w + 1) * n / InpTimeWindows);
         int wn = b - a; if(wn < 10) continue;
         int wdir[]; double wcl[]; bool wmask[];
         ArrayResize(wdir, wn); ArrayResize(wcl, wn); ArrayResize(wmask, wn);
         ArrayCopy(wdir, sink.dir, 0, a, wn); ArrayCopy(wcl, sink.trigger, 0, a, wn);
         for(int i = 0; i < wn; i++) wmask[i] = mHi[a + i];
         MksPayoff p; MksStatRideToFlip(wdir, wcl, wn, wmask, InpBrickSizePts, p);
         FileWrite(fh, StringFormat("%s\t%s\t%.4f\t%.2f\t%d",
                   TimeToString((datetime)(sink.t[a] / 1000)),
                   TimeToString((datetime)(sink.t[b - 1] / 1000)),
                   p.NetEV(g_costB), p.T(), p.trades));
      }
      FileClose(fh);
      PrintFormat("TSV: %s\\MQL5\\Files\\MKS-ULTIMATE\\Research\\gated_momentum_%s.tsv",
                  TerminalInfoString(TERMINAL_DATA_PATH), symbol);
   }
   Print("=== fim ===");
}
//+------------------------------------------------------------------+
