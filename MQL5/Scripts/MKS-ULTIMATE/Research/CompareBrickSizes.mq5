//+------------------------------------------------------------------+
//| @file           : CompareBrickSizes.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Research
//| @responsibility : Compara TAMANHOS DE BRICK (research-only) pra decidir o
//|                   melhor — pelo que importa: EVnet líquido do ride-to-flip
//|                   COM CUSTO AUTO-ESCALADO (spread fixo em pontos ÷ brick, pra
//|                   a comparação ser justa: brick menor = spread come mais) +
//|                   ESTACIONARIDADE (positivo em todo período ou só num
//|                   passado?). Ao lado, o histograma de run-length (frequência
//|                   de sequências de N bricks) como diagnóstico. Uma passada
//|                   sobre o histórico por tamanho; mesma stat pura testada.
//| @depends_on     : Research/CMksBrickStats.mqh, Research/CMksBrickSeries.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Research/CompareBrickSizes.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Research/CMksBrickStats.mqh>
#include <MKS-ULTIMATE/Research/CMksBrickSeries.mqh>

input string   InpSymbol       = "";      // vazio => _Symbol
input datetime InpFrom         = 0;       // 0 => agora - InpDaysBack
input datetime InpTo           = 0;       // 0 => agora
input int      InpDaysBack     = 365;
input string   InpBrickSizes   = "2,3,5,8"; // tamanhos (USD) a comparar
input double   InpSpreadPoints = 240;     // spread baseline medido (Exness XAU); custo ESCALA por brick
input double   InpSlipPoints   = 0;       // slippage adicional em pontos (0 = só spread)
input int      InpUtcOffsetHrs = -3;
input int      InpTimeWindows   = 6;      // janelas p/ estacionaridade
input int      InpMaxRunLen     = 5;      // histograma de run-length até este (dobra acima)

// Quantas das K janelas de tempo têm EVnet>0 (mask=all). Estacionário = K/K.
int CountPosWindows(const int &dir[], const double &cl[], int n, int K, double S, double costB)
{
   int pos = 0;
   for(int w = 0; w < K; w++)
   {
      int a = (int)((long)w * n / K), b = (int)((long)(w + 1) * n / K);
      int wn = b - a; if(wn < 10) continue;
      int wd[]; double wc[]; bool wm[];
      ArrayResize(wd, wn); ArrayResize(wc, wn); ArrayResize(wm, wn);
      ArrayCopy(wd, dir, 0, a, wn); ArrayCopy(wc, cl, 0, a, wn);
      for(int i = 0; i < wn; i++) wm[i] = true;
      MksPayoff p; MksStatRideToFlip(wd, wc, wn, wm, S, p);
      if(p.NetEV(costB) > 0) pos++;
   }
   return pos;
}

void OnStart()
{
   string symbol = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;
   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   datetime now  = TimeCurrent();
   datetime from = (InpFrom == 0) ? (datetime)(now - (long)InpDaysBack * 86400) : InpFrom;
   datetime to   = (InpTo   == 0) ? now : InpTo;

   string parts[];
   int nSizes = StringSplit(InpBrickSizes, ',', parts);
   if(nSizes <= 0) { Print("InpBrickSizes vazio. Ex: \"2,3,5,8\""); return; }

   Print("");
   Print("=== CompareBrickSizes (research — qual brick?) ===");
   PrintFormat("symbol=%s point=%.5f janela=%s..%s  custo=%.0f+%.0f pts (spread+slip), ESCALA por brick",
               symbol, point, TimeToString(from, TIME_DATE), TimeToString(to, TIME_DATE),
               InpSpreadPoints, InpSlipPoints);
   Print("  EVnet>0 = paga apos custo | stat=K/K = positivo em TODAS as janelas (estacionario)");
   Print("  runs Lk = nº de sequencias de EXATAMENTE k bricks (L5+ = >=5). EVnet DECIDE, runs = diagnostico.");
   Print("");

   double bestEvnet = -1e18; double bestSize = 0; int bestStat = 0;

   // TSV
   FolderCreate("MKS-ULTIMATE\\Research");
   int fh = FileOpen("MKS-ULTIMATE\\Research\\compare_sizes_" + symbol + ".tsv",
                     FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(fh != INVALID_HANDLE)
   {
      FileWrite(fh, StringFormat("# compare_sizes symbol=%s from=%s to=%s spread=%.0f slip=%.0f",
                symbol, TimeToString(from), TimeToString(to), InpSpreadPoints, InpSlipPoints));
      FileWrite(fh, "size\tbricks\tbull\tbear\tcost_bricks\tev_gross\tev_net\tt\tstat_pos\tstat_k\tL1\tL2\tL3\tL4\tL5plus");
   }

   for(int si = 0; si < nSizes; si++)
   {
      double S = StringToDouble(parts[si]);
      if(S <= 0.0) continue;

      CMksBrickSeriesCollector sink;
      if(MksLoadBrickSeries(symbol, from, to, S, sink) < 0) continue;
      int n = sink.count;
      if(n < 50) { PrintFormat("S=%.1f: bricks insuficientes (%d) — pulando.", S, n); continue; }

      double brickPoints = (point > 0.0) ? (S / point) : 0.0;
      double costB = (brickPoints > 0.0) ? (InpSpreadPoints + InpSlipPoints) / brickPoints : 0.0;

      bool mAll[]; ArrayResize(mAll, n);
      for(int i = 0; i < n; i++) mAll[i] = true;
      MksPayoff p; MksStatRideToFlip(sink.dir, sink.trigger, n, mAll, S, p);

      int rlC[], rlR[]; MksStatRunLength(sink.dir, n, InpMaxRunLen, rlC, rlR);
      int pos = CountPosWindows(sink.dir, sink.trigger, n, InpTimeWindows, S, costB);

      double evnet = p.NetEV(costB);
      PrintFormat("S=%-4.1f bricks=%-6d grn=%-5d red=%-5d cost=%.3fbrk | EVg=%+.3f EVnet=%+.3f t=%+5.1f | stat=%d/%d | runs L1=%d L2=%d L3=%d L4=%d L5+=%d",
                  S, n, sink.bull, sink.bear, costB,
                  p.EV(), evnet, p.T(), pos, InpTimeWindows,
                  rlR[1], rlR[2], rlR[3], rlR[4], rlR[5]);

      if(fh != INVALID_HANDLE)
         FileWrite(fh, StringFormat("%.1f\t%d\t%d\t%d\t%.4f\t%.4f\t%.4f\t%.2f\t%d\t%d\t%d\t%d\t%d\t%d\t%d",
                   S, n, sink.bull, sink.bear, costB, p.EV(), evnet, p.T(), pos, InpTimeWindows,
                   rlR[1], rlR[2], rlR[3], rlR[4], rlR[5]));

      // Melhor = maior EVnet, com prioridade pra estacionário (stat==K).
      bool betterThanBest = (pos == InpTimeWindows && bestStat < InpTimeWindows)
                            || ((pos == InpTimeWindows) == (bestStat == InpTimeWindows) && evnet > bestEvnet);
      if(betterThanBest) { bestEvnet = evnet; bestSize = S; bestStat = pos; }
   }

   if(fh != INVALID_HANDLE) FileClose(fh);

   Print("");
   if(bestSize > 0.0)
      PrintFormat(">>> melhor: S=%.1f  EVnet=%+.3f brick/trade  estacionaridade=%d/%d%s",
                  bestSize, bestEvnet, bestStat, InpTimeWindows,
                  (bestStat == InpTimeWindows) ? "  (positivo em todo periodo)"
                                               : "  (NAO estacionario — cuidado)");
   else
      Print(">>> nenhum tamanho valido.");
   Print("=== fim ===");
}
//+------------------------------------------------------------------+
