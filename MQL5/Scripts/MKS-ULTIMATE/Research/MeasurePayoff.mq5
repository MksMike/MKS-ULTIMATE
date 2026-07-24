//+------------------------------------------------------------------+
//| @file           : MeasurePayoff.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Research
//| @responsibility : Mede a OUTRA metade da equação do edge (research-only):
//|                   não a taxa de acerto, mas o R-MÚLTIPLO/EV do trade
//|                   "ride-to-flip" (entra no close do brick, corre até
//|                   reverter), condicionado aos filtros que sobreviveram ao
//|                   OOS na caracterização (regime trend / vol média / 21h).
//|                   Responde: o momentum tênue vira EV POSITIVO depois do
//|                   custo, ou o spread come? Trades não-sobrepostos + t-stat
//|                   + split train/test. Um sopro de 52% pode ser edge se os
//|                   acertos correrem mais que as perdas — é isso que mede.
//| @depends_on     : Research/CMksBrickStats.mqh, Research/CMksBrickSeries.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Research/MeasurePayoff.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Research/CMksBrickStats.mqh>
#include <MKS-ULTIMATE/Research/CMksBrickSeries.mqh>

input string   InpSymbol       = "";     // vazio => _Symbol
input datetime InpFrom         = 0;      // 0 => agora - InpDaysBack
input datetime InpTo           = 0;      // 0 => agora
input int      InpDaysBack     = 90;
input double   InpBrickSizePts = 3.0;    // S=3 (produção XAU classic)
input int      InpUtcOffsetHrs = -3;     // servidor→UTC
input int      InpRegimePeriod = 20;
input double   InpRegimeThresh = 0.6;
input double   InpCostBricks   = 0.10;   // custo por trade em bricks (spread+slip; 240pt≈0.08 brick @S=3)

// Constrói os 4 masks de entrada (all / trend / vol média / 21h) sobre a série.
void BuildMasks(const int &dir[], const long &t[], int n, int offset,
                int period, double thresh,
                bool &mAll[], bool &mTrend[], bool &mVolMid[], bool &mH21[])
{
   ArrayResize(mAll, n); ArrayResize(mTrend, n);
   ArrayResize(mVolMid, n); ArrayResize(mH21, n);

   long loThr = 0, hiThr = 0;
   if(n >= 4)
   {
      long dts[]; ArrayResize(dts, n - 1);
      for(int i = 1; i < n; i++) dts[i - 1] = t[i] - t[i - 1];
      long s[]; ArrayCopy(s, dts); ArraySort(s);
      loThr = s[(n - 1) / 3];
      hiThr = s[2 * (n - 1) / 3];
   }

   double op[], cl[]; ArrayResize(op, n); ArrayResize(cl, n);
   for(int i = 0; i < n; i++) { op[i] = 0.0; cl[i] = (double)dir[i]; }
   CMksReversalRegime regime(period, thresh);

   for(int i = 0; i < n; i++)
   {
      mAll[i]    = true;
      mH21[i]    = (MksStatHourOf(t[i], offset) == 21);
      mVolMid[i] = (i >= 1 && (t[i] - t[i-1]) > loThr && (t[i] - t[i-1]) <= hiThr);
      mTrend[i]  = (i >= period - 1 && regime.Compute(op, cl, i) < thresh);
   }
}

string PayoffVerdict(const MksPayoff &tr, const MksPayoff &te)
{
   bool trSig = (MathAbs(tr.T()) >= 1.8);
   bool teSig = (MathAbs(te.T()) >= 1.8);
   bool same  = ((tr.EV() > 0) == (te.EV() > 0));
   if(trSig && teSig &&  same) return "REPLICA";
   if(trSig && teSig && !same) return "INVERTE";
   if(trSig != teSig)          return "INSTAVEL";
   return "SUMIU";
}

// Roda o payoff de um mask sobre full/train/test e imprime a linha.
void ReportMask(string label, const int &dir[], const double &cl[], int n,
                const bool &mask[], int nTr,
                const int &trDir[], const double &trCl[], const bool &trMask[],
                const int &teDir[], const double &teCl[], const bool &teMask[],
                double S, double cost)
{
   MksPayoff f, tr, te;
   MksStatRideToFlip(dir,   cl,   n,   mask,   S, f);
   MksStatRideToFlip(trDir, trCl, nTr, trMask, S, tr);
   MksStatRideToFlip(teDir, teCl, ArraySize(teDir), teMask, S, te);
   PrintFormat("  %-11s EVnet=%+.3f | EVgross=%+.3f t=%+.1f win=%.3f avgW=%+.2f avgL=%+.2f fwd=%.2f N=%d | OOS tr=%+.3f te=%+.3f %s",
               label, f.NetEV(cost), f.EV(), f.T(), f.WinRate(),
               f.AvgWin(), f.AvgLoss(), f.AvgFwd(), f.trades,
               tr.NetEV(cost), te.NetEV(cost), PayoffVerdict(tr, te));
}

void OnStart()
{
   string symbol = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   datetime now  = TimeCurrent();
   datetime from = (InpFrom == 0) ? (datetime)(now - (long)InpDaysBack * 86400) : InpFrom;
   datetime to   = (InpTo   == 0) ? now : InpTo;

   Print("");
   Print("=== MeasurePayoff (ride-to-flip; EV em bricks) ===");
   PrintFormat("symbol=%s digits=%d janela=%s..%s S=%.3f custo=%.3f bricks/trade utcOff=%d",
               symbol, digits, TimeToString(from, TIME_DATE), TimeToString(to, TIME_DATE),
               InpBrickSizePts, InpCostBricks, InpUtcOffsetHrs);

   CMksBrickSeriesCollector sink;
   if(MksLoadBrickSeries(symbol, from, to, InpBrickSizePts, sink) < 0) return;
   int n = sink.count;
   if(n < 10) { Print("bricks insuficientes. Abortando."); return; }

   //--- Masks FULL ---
   bool mAll[], mTrend[], mVolMid[], mH21[];
   BuildMasks(sink.dir, sink.t, n, InpUtcOffsetHrs, InpRegimePeriod, InpRegimeThresh,
              mAll, mTrend, mVolMid, mH21);

   //--- Split train/test + masks por metade (thresholds OOS-limpos) ---
   int half = n / 2, nTr = half, nTe = n - half;
   int trDir[], teDir[]; double trCl[], teCl[]; long trT[], teT[];
   ArrayResize(trDir, nTr); ArrayResize(trCl, nTr); ArrayResize(trT, nTr);
   ArrayResize(teDir, nTe); ArrayResize(teCl, nTe); ArrayResize(teT, nTe);
   ArrayCopy(trDir, sink.dir,   0, 0,   nTr); ArrayCopy(trCl, sink.close, 0, 0,   nTr); ArrayCopy(trT, sink.t, 0, 0,   nTr);
   ArrayCopy(teDir, sink.dir,   0, nTr, nTe); ArrayCopy(teCl, sink.close, 0, nTr, nTe); ArrayCopy(teT, sink.t, 0, nTr, nTe);

   bool trAll[], trTrend[], trVolMid[], trH21[];
   bool teAll[], teTrend[], teVolMid[], teH21[];
   BuildMasks(trDir, trT, nTr, InpUtcOffsetHrs, InpRegimePeriod, InpRegimeThresh, trAll, trTrend, trVolMid, trH21);
   BuildMasks(teDir, teT, nTe, InpUtcOffsetHrs, InpRegimePeriod, InpRegimeThresh, teAll, teTrend, teVolMid, teH21);

   Print("");
   PrintFormat("=== EV do ride-to-flip (N=%d bricks; train=%d test=%d) ===", n, nTr, nTe);
   Print("  EVnet>0 = riding momentum paga apos custo; <0 = o spread come.");
   Print("  win=taxa acerto  avgW/avgL=R medio ganho/perda  fwd=bricks ate reverter  t=signif.");
   ReportMask("all",       sink.dir, sink.close, n, mAll,    nTr, trDir, trCl, trAll,    teDir, teCl, teAll,    InpBrickSizePts, InpCostBricks);
   ReportMask("trend",     sink.dir, sink.close, n, mTrend,  nTr, trDir, trCl, trTrend,  teDir, teCl, teTrend,  InpBrickSizePts, InpCostBricks);
   ReportMask("vol-media",  sink.dir, sink.close, n, mVolMid, nTr, trDir, trCl, trVolMid, teDir, teCl, teVolMid, InpBrickSizePts, InpCostBricks);
   ReportMask("hora-21",    sink.dir, sink.close, n, mH21,    nTr, trDir, trCl, trH21,    teDir, teCl, teH21,    InpBrickSizePts, InpCostBricks);

   //--- TSV ---
   FolderCreate("MKS-ULTIMATE\\Research");
   string path = StringFormat("MKS-ULTIMATE\\Research\\payoff_%s.tsv", symbol);
   int fh = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(fh != INVALID_HANDLE)
   {
      FileWrite(fh, StringFormat("# payoff symbol=%s from=%s to=%s bricks=%d S=%.3f cost=%.3f",
                symbol, TimeToString(from), TimeToString(to), n, InpBrickSizePts, InpCostBricks));
      FileWrite(fh, "filtro\ttrades\twin\tev_gross\tev_net\tt\tavg_win\tavg_loss\tavg_fwd");
      string labels[] = {"all", "trend", "vol-media", "hora-21"};
      for(int mi = 0; mi < 4; mi++)
      {
         MksPayoff p;
         if(mi==0) MksStatRideToFlip(sink.dir, sink.close, n, mAll,    InpBrickSizePts, p);
         if(mi==1) MksStatRideToFlip(sink.dir, sink.close, n, mTrend,  InpBrickSizePts, p);
         if(mi==2) MksStatRideToFlip(sink.dir, sink.close, n, mVolMid, InpBrickSizePts, p);
         if(mi==3) MksStatRideToFlip(sink.dir, sink.close, n, mH21,    InpBrickSizePts, p);
         FileWrite(fh, StringFormat("%s\t%d\t%.4f\t%.4f\t%.4f\t%.2f\t%.4f\t%.4f\t%.4f",
                   labels[mi], p.trades, p.WinRate(), p.EV(), p.NetEV(InpCostBricks),
                   p.T(), p.AvgWin(), p.AvgLoss(), p.AvgFwd()));
      }
      FileClose(fh);
      PrintFormat("TSV: %s\\MQL5\\Files\\%s", TerminalInfoString(TERMINAL_DATA_PATH), path);
   }
   Print("=== fim ===");
}
//+------------------------------------------------------------------+
