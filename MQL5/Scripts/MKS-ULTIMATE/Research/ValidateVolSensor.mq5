//+------------------------------------------------------------------+
//| @file           : ValidateVolSensor.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Research
//| @responsibility : Validação NÍVEL 2 (confiabilidade em DADO REAL) do
//|                   CMksVolatilitySensor — etapa 3 do loop do catálogo.
//|                   Endurecido após verificação adversarial (3 lentes):
//|                   V1 MONOTONIA FORWARD por EPISÓDIOS (colapsa cada run de
//|                      rótulo num valor → mata a correlação serial que
//|                      inflava o N; exige >= min EPISÓDIOS por bucket) e
//|                      EXCLUI janelas forward que cruzam gap de sessão/fim-de-
//|                      semana (senão o tempo de mercado fechado vira o sinal);
//|                   V2 CLUSTERING por taxa de FLIP vs distribuição NULA de N
//|                      shuffles (p-valor empírico) — não um ratio numa escala
//|                      limitada por 1.0 nem uma seed única;
//|                   V3 OCUPAÇÃO por janela de CALENDÁRIO (não contagem de
//|                      brick), testando DOMINÂNCIA (<90%) E PRESENÇA (>=piso)
//|                      de cada bucket core; FAIL-CLOSED se nenhuma janela foi
//|                      avaliada. Rótulo usa só passado; realizado é o FUTURO.
//|                   Research-only; NÃO toca paridade/trading.
//| @depends_on     : Core/Sensors/Volatility/CMksVolatilitySensor.mqh,
//|                   Research/CMksBrickSeries.mqh, StressLab/CMksRandom.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Research/ValidateVolSensor.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Sensors/Volatility/CMksVolatilitySensor.mqh>
#include <MKS-ULTIMATE/Research/CMksBrickSeries.mqh>
#include <MKS-ULTIMATE/StressLab/CMksRandom.mqh>

input string   InpSymbol       = "";      // vazio => _Symbol
input datetime InpFrom         = 0;
input datetime InpTo           = 0;
input int      InpDaysBack     = 365;
input double   InpBrickSizePts = 3.0;
input int      InpFwdBricks    = 5;       // K: horizonte forward (bricks)
input int      InpSkipWarmup   = 600;     // pula ate a referencia (500) encher + folga
input int      InpTimeWindows  = 6;       // janelas de CALENDARIO (V3)
input double   InpHalfLife     = 10.0;    // params do sensor
input int      InpRefWindow    = 500;
input double   InpHysteresis   = 1.0;
input double   InpMaxGapHours  = 4.0;     // dt > isto = descontinuidade (sensor + skip)
input double   InpFwdGapSec    = 3600.0;  // forward com dt > isto = exclui (confound de sessao)
input int      InpPostGapSkip  = 30;      // pula N bricks apos gap (EWMA stale ~3xhalfLife)
input int      InpMinEpisodes  = 30;      // min EPISODIOS por bucket core (V1)
input int      InpShuffles     = 30;      // shuffles p/ distribuicao nula (V2)
input double   InpPresenceFloor= 2.0;     // ocupacao minima % de cada core por janela (V3)
input int      InpMinWinLabels = 200;     // min rotulos p/ avaliar uma janela (V3)

double MedianOf(const double &arr[])
{
   int n = ArraySize(arr);
   if(n == 0) return 0.0;
   double s[]; ArrayCopy(s, arr); ArraySort(s);
   return (n % 2 == 1) ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2.0;
}

void AppendD(double &arr[], double v) { int k = ArraySize(arr); ArrayResize(arr, k + 1, 65536); arr[k] = v; }

// Taxa de FLIP dos rótulos (1 - persistencia) de um sensor NOVO sobre ts[]:
// consecutiva por BRICK (nao pula gap — mede a mecanica de clustering do sensor).
double LabelFlipRate(const long &ts[], int n, int skip,
                     double hl, int refW, double hyst, double maxGapMs)
{
   CMksVolatilitySensor s(hl, refW, hyst, maxGapMs);
   int prev = -1, flips = 0, cnt = 0;
   for(int i = 0; i < n; i++)
   {
      s.OnBrick(ts[i]);
      if(i < skip) continue;
      int lab = (int)s.Level();
      if(prev >= 0) { cnt++; if(lab != prev) flips++; }
      prev = lab;
   }
   return (cnt > 0) ? (double)flips / (double)cnt : 0.0;
}

void OnStart()
{
   string symbol = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;
   datetime now  = TimeCurrent();
   datetime from = (InpFrom == 0) ? (datetime)(now - (long)InpDaysBack * 86400) : InpFrom;
   datetime to   = (InpTo   == 0) ? now : InpTo;
   double maxGapMs   = InpMaxGapHours * 3600000.0;
   long   gapCutoffMs = (long)(InpFwdGapSec * 1000.0);

   Print("");
   Print("=== ValidateVolSensor (nivel 2 — dado REAL, endurecido) ===");
   PrintFormat("symbol=%s S=%.3f janela=%s..%s K=%d skip=%d | sensor(hl=%.0f ref=%d hyst=%.1f gap=%.0fh)",
               symbol, InpBrickSizePts, TimeToString(from, TIME_DATE), TimeToString(to, TIME_DATE),
               InpFwdBricks, InpSkipWarmup, InpHalfLife, InpRefWindow, InpHysteresis, InpMaxGapHours);

   CMksBrickSeriesCollector sink;
   if(MksLoadBrickSeries(symbol, from, to, InpBrickSizePts, sink) < 0) return;
   int n = sink.count;
   if(n < InpSkipWarmup + InpFwdBricks + 200) { PrintFormat("bricks insuficientes (%d).", n); return; }

   //--- Passada: rotulo (so passado) -> forward LIMPO (sem gap dentro) ---
   CMksVolatilitySensor sensor(InpHalfLife, InpRefWindow, InpHysteresis, maxGapMs);
   int    obsLab[]; double obsFwd[]; long obsT[]; int nObs = 0;
   int    bricksSinceGap = 999999;
   int    skippedGapFwd = 0, skippedPostGap = 0;

   for(int i = 0; i < n; i++)
   {
      if(i >= 1 && (double)(sink.t[i] - sink.t[i - 1]) > maxGapMs) bricksSinceGap = 0;
      else                                                        bricksSinceGap++;
      sensor.OnBrick(sink.t[i]);
      if(i < InpSkipWarmup)     continue;
      if(i + InpFwdBricks >= n) break;

      // exclui: EWMA ainda recuperando pos-gap
      if(bricksSinceGap < InpPostGapSkip) { skippedPostGap++; continue; }
      // exclui: forward que cruza gap de sessao (o tempo de mercado fechado
      // dominaria o realizado e viraria proxy de calendario, nao de vol)
      bool fwdHasGap = false;
      for(int j = i + 1; j <= i + InpFwdBricks; j++)
         if((long)(sink.t[j] - sink.t[j - 1]) > gapCutoffMs) { fwdHasGap = true; break; }
      if(fwdHasGap) { skippedGapFwd++; continue; }

      int idx = nObs;
      ArrayResize(obsLab, idx + 1, 65536); ArrayResize(obsFwd, idx + 1, 65536); ArrayResize(obsT, idx + 1, 65536);
      obsLab[idx] = (int)sensor.Level();
      obsFwd[idx] = (double)(sink.t[i + InpFwdBricks] - sink.t[i]) / 1000.0;
      obsT[idx]   = sink.t[i];
      nObs++;
   }
   PrintFormat("observacoes: %d (excluidas: %d pos-gap, %d forward-com-gap)", nObs, skippedPostGap, skippedGapFwd);
   if(nObs < 500) { Print("observacoes insuficientes apos exclusao. Abortando."); return; }

   //--- V1: colapsa cada RUN de rotulo num episodio (mediana do run) ---
   double epiLow[], epiMed[], epiHigh[], epiExt[], epiUltra[];
   int    runLab = obsLab[0]; double runVals[]; ArrayResize(runVals, 0);
   AppendD(runVals, obsFwd[0]);
   for(int i = 1; i <= nObs; i++)
   {
      if(i < nObs && obsLab[i] == runLab) { AppendD(runVals, obsFwd[i]); continue; }
      double em = MedianOf(runVals);           // um valor por episodio
      switch(runLab)
      {
         case 0: AppendD(epiLow,  em); break;
         case 1: AppendD(epiMed,  em); break;
         case 2: AppendD(epiHigh, em); break;
         case 3: AppendD(epiExt,  em); break;
         case 4: AppendD(epiUltra, em); break;
      }
      if(i < nObs) { runLab = obsLab[i]; ArrayResize(runVals, 0); AppendD(runVals, obsFwd[i]); }
   }
   double mLow = MedianOf(epiLow), mMed = MedianOf(epiMed), mHigh = MedianOf(epiHigh),
          mExt = MedianOf(epiExt), mUltra = MedianOf(epiUltra);
   int eLow = ArraySize(epiLow), eMed = ArraySize(epiMed), eHigh = ArraySize(epiHigh),
       eExt = ArraySize(epiExt), eUltra = ArraySize(epiUltra);

   Print("");
   PrintFormat("=== V1 MONOTONIA FORWARD por EPISODIO — tempo mediano p/ os proximos %d bricks ===", InpFwdBricks);
   Print("  cada RUN de rotulo = 1 episodio (mata correlacao serial). Espera-se LOW > MED > HIGH.");
   PrintFormat("  LOW    : median=%8.1fs  episodios=%d", mLow,  eLow);
   PrintFormat("  MEDIUM : median=%8.1fs  episodios=%d", mMed,  eMed);
   PrintFormat("  HIGH   : median=%8.1fs  episodios=%d", mHigh, eHigh);
   PrintFormat("  EXTREME: median=%8.1fs  episodios=%d", mExt,  eExt);
   PrintFormat("  ULTRA  : median=%8.1fs  episodios=%d", mUltra, eUltra);
   bool v1 = (eLow >= InpMinEpisodes && eMed >= InpMinEpisodes && eHigh >= InpMinEpisodes &&
              mLow > mMed && mMed > mHigh);
   PrintFormat("  >>> V1 %s (min %d episodios/bucket core)", v1 ? "OK" : "FALHA/INSUF", InpMinEpisodes);

   //--- V2: flip real vs distribuicao NULA de N shuffles (p-valor) ---
   double flipReal = LabelFlipRate(sink.t, n, InpSkipWarmup, InpHalfLife, InpRefWindow, InpHysteresis, maxGapMs);
   int m = n - 1; double dts0[]; ArrayResize(dts0, m);
   for(int i = 1; i < n; i++) dts0[i - 1] = (double)(sink.t[i] - sink.t[i - 1]);
   double flipShuf[]; ArrayResize(flipShuf, InpShuffles);
   int leq = 0;
   for(int sIdx = 0; sIdx < InpShuffles; sIdx++)
   {
      double d[]; ArrayCopy(d, dts0);
      CMksRandom rng((uint)(20260725 + sIdx * 7919));
      for(int i = m - 1; i > 0; i--) { int j = rng.NextInt(0, i); double tmp = d[i]; d[i] = d[j]; d[j] = tmp; }
      long ts[]; ArrayResize(ts, n); ts[0] = sink.t[0];
      for(int i = 1; i < n; i++) ts[i] = ts[i - 1] + (long)d[i - 1];
      flipShuf[sIdx] = LabelFlipRate(ts, n, InpSkipWarmup, InpHalfLife, InpRefWindow, InpHysteresis, maxGapMs);
      if(flipShuf[sIdx] <= flipReal) leq++;
   }
   double sumF = 0.0; for(int i = 0; i < InpShuffles; i++) sumF += flipShuf[i];
   double meanF = sumF / InpShuffles;
   double varF = 0.0; for(int i = 0; i < InpShuffles; i++) varF += (flipShuf[i] - meanF) * (flipShuf[i] - meanF);
   double sdF = MathSqrt(varF / InpShuffles);
   double pval = (double)leq / (double)InpShuffles;   // fracao de shuffles com flip <= real

   Print("");
   Print("=== V2 CLUSTERING — flip REAL vs distribuicao NULA (shuffle) ===");
   PrintFormat("  flip REAL = %.4f | null shuffle: media=%.4f sd=%.4f | p(shuffle<=real) = %.3f (n=%d)",
               flipReal, meanF, sdF, pval, InpShuffles);
   bool v2 = (pval <= 0.05);
   PrintFormat("  >>> V2 %s: %s", v2 ? "OK" : "FALHA",
               v2 ? "real flipa MENOS que o embaralhado (clustering genuino, p<=0.05)"
                  : "flip real dentro da nula — clustering ~= mecanica pura");

   //--- V3: ocupacao por janela de CALENDARIO — dominancia E presenca ---
   Print("");
   PrintFormat("=== V3 ADAPTACAO — ocupacao por %d janelas de CALENDARIO (nao contagem) ===", InpTimeWindows);
   PrintFormat("  janela saudavel: nenhum core >90%% (nao satura) E cada core >=%.0f%% (nao some).", InpPresenceFloor);
   long span = (long)to - (long)from;
   int  evaluated = 0; bool v3ok = true;
   for(int w = 0; w < InpTimeWindows; w++)
   {
      long wa = (long)from + span * w / InpTimeWindows;
      long wb = (long)from + span * (w + 1) / InpTimeWindows;
      int occ[5]; ArrayInitialize(occ, 0); int tot = 0;
      for(int i = 0; i < nObs; i++)
      {
         long ts = obsT[i] / 1000;
         if(ts >= wa && ts < wb) { occ[obsLab[i]]++; tot++; }
      }
      if(tot < InpMinWinLabels)
      {
         PrintFormat("  win%d [%s..%s] N=%d < %d — PULADA",
                     w + 1, TimeToString((datetime)wa, TIME_DATE), TimeToString((datetime)wb, TIME_DATE),
                     tot, InpMinWinLabels);
         continue;
      }
      evaluated++;
      double p0 = 100.0 * occ[0] / tot, p1 = 100.0 * occ[1] / tot, p2 = 100.0 * occ[2] / tot,
             p3 = 100.0 * occ[3] / tot, p4 = 100.0 * occ[4] / tot;
      bool dominates = (p0 > 90.0 || p1 > 90.0 || p2 > 90.0);
      bool absent    = (p0 < InpPresenceFloor || p1 < InpPresenceFloor || p2 < InpPresenceFloor);
      if(dominates || absent) v3ok = false;
      PrintFormat("  win%d [%s..%s] LOW=%4.1f%% MED=%4.1f%% HIGH=%4.1f%% EXT=%4.1f%% ULTRA=%4.1f%%%s",
                  w + 1, TimeToString((datetime)wa, TIME_DATE), TimeToString((datetime)wb, TIME_DATE),
                  p0, p1, p2, p3, p4,
                  dominates ? "  <== SATURA(>90%)" : (absent ? "  <== SOME(<piso)" : ""));
   }
   bool v3 = (evaluated > 0 && v3ok);   // FAIL-CLOSED: 0 janelas avaliadas != OK
   PrintFormat("  >>> V3 %s: %d janela(s) avaliada(s)%s",
               v3 ? "OK" : (evaluated == 0 ? "INCONCLUSIVO" : "FALHA"), evaluated,
               (evaluated == 0) ? " — nenhuma passou o minimo (aumente a janela ou o dado)" : "");

   //--- Veredito ---
   Print("");
   bool pass = (v1 && v2 && v3);
   PrintFormat(">>> NIVEL 2 %s — V1(monotonia/episodios)=%s V2(clustering/p-valor)=%s V3(adaptacao/calendario)=%s",
               pass ? "APROVADO" : "REPROVADO", v1 ? "OK" : "X", v2 ? "OK" : "X", v3 ? "OK" : "X");
   if(pass) Print("    Proximo passo do loop: EA simples de integracao (paridade/comportamento).");

   //--- TSV ---
   FolderCreate("MKS-ULTIMATE\\Research");
   int fh = FileOpen("MKS-ULTIMATE\\Research\\volsensor_" + symbol + ".tsv", FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(fh != INVALID_HANDLE)
   {
      FileWrite(fh, StringFormat("# volsensor symbol=%s S=%.3f from=%s to=%s K=%d obs=%d nObs_excl(postgap=%d fwdgap=%d)",
                symbol, InpBrickSizePts, TimeToString(from), TimeToString(to), InpFwdBricks, nObs, skippedPostGap, skippedGapFwd));
      FileWrite(fh, "bucket\tepisodes\tmedian_fwd_sec");
      FileWrite(fh, StringFormat("LOW\t%d\t%.1f", eLow, mLow));
      FileWrite(fh, StringFormat("MEDIUM\t%d\t%.1f", eMed, mMed));
      FileWrite(fh, StringFormat("HIGH\t%d\t%.1f", eHigh, mHigh));
      FileWrite(fh, StringFormat("EXTREME\t%d\t%.1f", eExt, mExt));
      FileWrite(fh, StringFormat("ULTRA\t%d\t%.1f", eUltra, mUltra));
      FileWrite(fh, StringFormat("v2\tflip_real\t%.4f\tnull_mean\t%.4f\tnull_sd\t%.4f\tpval\t%.3f", flipReal, meanF, sdF, pval));
      FileWrite(fh, StringFormat("verdict\tV1=%s\tV2=%s\tV3=%s\teval_windows=%d\tpass=%s",
                v1 ? "OK" : "X", v2 ? "OK" : "X", v3 ? "OK" : "X", evaluated, pass ? "true" : "false"));
      FileClose(fh);
      PrintFormat("TSV: %s\\MQL5\\Files\\MKS-ULTIMATE\\Research\\volsensor_%s.tsv",
                  TerminalInfoString(TERMINAL_DATA_PATH), symbol);
   }
   Print("=== fim ===");
}
//+------------------------------------------------------------------+
