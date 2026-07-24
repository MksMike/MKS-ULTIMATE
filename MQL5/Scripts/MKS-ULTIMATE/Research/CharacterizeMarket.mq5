//+------------------------------------------------------------------+
//| @file           : CharacterizeMarket.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Research
//| @responsibility : Passada de CARACTERIZAÇÃO do mercado para DESCOBERTA
//|                   DE EDGE (research-only, NÃO é o caminho de trading).
//|                   Gera uma série grande de bricks do histórico (CopyTicks
//|                   dia-a-dia → CMksRenkoBuilder classic, mesmo produtor da
//|                   produção) e mede 4 estatísticas (CMksBrickStats): run-
//|                   length→continuação, hora do dia, volatilidade, regime.
//|                   Desvio de P(continua) vs 0.5 = candidato a edge. Cospe
//|                   resumo no Experts + TSV versionável. Os números apontam
//|                   ONDE procurar edge — em vez de adivinhar.
//| @depends_on     : Research/CMksBrickStats.mqh,
//|                   Core/RenkoBuilder/CMksRenkoBuilder.mqh,
//|                   Core/RenkoBuilder/CMksFixedBrickSizer.mqh,
//|                   Core/Types/RenkoGeometry.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/Brick.mqh, Core/Interfaces/IRenkoSink.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Research/CharacterizeMarket.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Research/CMksBrickStats.mqh>
#include <MKS-ULTIMATE/Research/CMksBrickSeries.mqh>

input string   InpSymbol        = "";     // vazio => _Symbol
input datetime InpFrom          = 0;      // 0 => agora - InpDaysBack
input datetime InpTo            = 0;      // 0 => agora
input int      InpDaysBack      = 90;     // janela default se InpFrom=0 (mais dias = melhor stat, mais lento)
input double   InpBrickSizePts  = 3.0;    // S=3 (produção XAU classic — ADR-026)
input int      InpUtcOffsetHrs  = -3;     // servidor→UTC (Exness ~UTC+3 → -3). Ajuste ao seu server.
input int      InpMaxRunLen     = 8;      // maior run-length reportado (dobra acima)
input int      InpRegimePeriod  = 20;     // janela do regime (bricks)
input double   InpRegimeThresh  = 0.6;    // score >= => lateral
input int      InpMinBricks     = 500;    // abaixo disso, avisa "amostra fina"

int g_digits = 2;
string Fmt(double p) { return DoubleToString(p, g_digits); }

// Marcador GATED por significância (z), não por |p-0.5| — evita chamar
// "sinal" o que é só amostra pequena (era a fraqueza da 1a versão).
string DevZ(int cont, int rev)
{
   double z = MksStatZ(cont, rev);
   if(MathAbs(z) < 2.0) return "";
   string s = (z > 0) ? "  >>MOMENTUM" : "  <<REVERSAO";
   if(MathAbs(z) >= 3.0) s += " (forte)";
   return s;
}

// Veredito out-of-sample: o sinal replica ao dividir a série em 2 metades?
// REPLICA = ambas metades significantes (|z|>=1.8, ~5% com metade dos dados) e
// do MESMO lado. INVERTE = ambas signif. mas lados opostos (ruído/regime).
// INSTAVEL = só uma metade. SUMIU = nenhuma metade robusta (sinal frágil).
string OosVerdict(int trC, int trR, int teC, int teR)
{
   double zt = MksStatZ(trC, trR);
   double ze = MksStatZ(teC, teR);
   bool trSig = (MathAbs(zt) >= 1.8);
   bool teSig = (MathAbs(ze) >= 1.8);
   bool same  = ((zt > 0) == (ze > 0));
   if(trSig && teSig &&  same) return "REPLICA";
   if(trSig && teSig && !same) return "INVERTE";
   if(trSig != teSig)          return "INSTAVEL";
   return "SUMIU";
}

// Uma linha da comparação OOS no Experts.
void PrintOosRow(string label, int fc, int fr, int tc, int tr, int ec, int er)
{
   PrintFormat("  %-14s FULL %.4f(z%+.1f)  TRAIN %.4f(z%+.1f)  TEST %.4f(z%+.1f)  %s",
               label,
               MksStatProb(fc, fr), MksStatZ(fc, fr),
               MksStatProb(tc, tr), MksStatZ(tc, tr),
               MksStatProb(ec, er), MksStatZ(ec, er),
               OosVerdict(tc, tr, ec, er));
}

// Uma linha do TSV (full + train + test + veredito).
string TsvRow(string section, string key, int fc, int fr, int tc, int tr, int ec, int er)
{
   return StringFormat("%s\t%s\t%d\t%d\t%d\t%.4f\t%.2f\t%.4f\t%.2f\t%.4f\t%.2f\t%s",
      section, key, fc, fr, fc + fr,
      MksStatProb(fc, fr), MksStatZ(fc, fr),
      MksStatProb(tc, tr), MksStatZ(tc, tr),
      MksStatProb(ec, er), MksStatZ(ec, er),
      OosVerdict(tc, tr, ec, er));
}

void OnStart()
{
   string symbol = (StringLen(InpSymbol) > 0) ? InpSymbol : _Symbol;
   g_digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   datetime now  = TimeCurrent();
   datetime from = (InpFrom == 0) ? (datetime)(now - (long)InpDaysBack * 86400) : InpFrom;
   datetime to   = (InpTo   == 0) ? now : InpTo;

   Print("");
   Print("=== CharacterizeMarket (research — busca de edge) ===");
   PrintFormat("symbol=%s digits=%d  janela=%s .. %s  S=%s  utcOffset=%d",
               symbol, g_digits,
               TimeToString(from, TIME_DATE|TIME_MINUTES),
               TimeToString(to,   TIME_DATE|TIME_MINUTES),
               Fmt(InpBrickSizePts), InpUtcOffsetHrs);

   //--- Série de bricks do histórico (loader compartilhado; classic S) ---
   CMksBrickSeriesCollector sink;
   if(MksLoadBrickSeries(symbol, from, to, InpBrickSizePts, sink) < 0) return;

   if(sink.count < 2)
   {
      Print("bricks insuficientes (histórico não baixado?). Abra o gráfico do "
            "símbolo e role o histórico, ou reduza a janela. Abortando.");
      return;
   }
   if(sink.count < InpMinBricks)
      PrintFormat("AVISO: amostra fina (%d < %d bricks) — trate os números como "
                  "indicativos, não conclusivos. Amplie InpDaysBack.",
                  sink.count, InpMinBricks);

   //--- Estatísticas (puras, testadas) ---
   int n = sink.count;

   // Overall continuação
   int oc = 0, orv = 0;
   for(int i = 1; i < n; i++) { if(sink.dir[i] == sink.dir[i-1]) oc++; else orv++; }
   double pOverall = MksStatProb(oc, orv);

   int rlCont[], rlRev[];
   MksStatRunLength(sink.dir, n, InpMaxRunLen, rlCont, rlRev);

   int hrCont[], hrRev[];
   MksStatHourOfDay(sink.dir, sink.t, n, InpUtcOffsetHrs, hrCont, hrRev);

   int volCont[], volRev[]; long loThr = 0, hiThr = 0;
   MksStatVolatilityTerciles(sink.dir, sink.t, n, volCont, volRev, loThr, hiThr);

   int rgCont[], rgRev[];
   MksStatRegime(sink.dir, n, InpRegimePeriod, InpRegimeThresh, rgCont, rgRev);

   //--- Split train (1a metade) / test (2a metade) para OOS ---
   int half = n / 2;
   int nTr = half, nTe = n - half;
   int  trDir[], teDir[]; long trT[], teT[];
   ArrayResize(trDir, nTr); ArrayResize(trT, nTr);
   ArrayResize(teDir, nTe); ArrayResize(teT, nTe);
   ArrayCopy(trDir, sink.dir, 0, 0,   nTr);
   ArrayCopy(trT,   sink.t,   0, 0,   nTr);
   ArrayCopy(teDir, sink.dir, 0, nTr, nTe);
   ArrayCopy(teT,   sink.t,   0, nTr, nTe);

   int trOc = 0, trOr = 0;
   for(int i = 1; i < nTr; i++) { if(trDir[i] == trDir[i-1]) trOc++; else trOr++; }
   int teOc = 0, teOr = 0;
   for(int i = 1; i < nTe; i++) { if(teDir[i] == teDir[i-1]) teOc++; else teOr++; }

   int trRlC[], trRlR[]; MksStatRunLength(trDir, nTr, InpMaxRunLen, trRlC, trRlR);
   int teRlC[], teRlR[]; MksStatRunLength(teDir, nTe, InpMaxRunLen, teRlC, teRlR);
   int trHrC[], trHrR[]; MksStatHourOfDay(trDir, trT, nTr, InpUtcOffsetHrs, trHrC, trHrR);
   int teHrC[], teHrR[]; MksStatHourOfDay(teDir, teT, nTe, InpUtcOffsetHrs, teHrC, teHrR);
   int trVlC[], trVlR[]; long ta = 0, tb = 0; MksStatVolatilityTerciles(trDir, trT, nTr, trVlC, trVlR, ta, tb);
   int teVlC[], teVlR[]; long ea = 0, eb = 0; MksStatVolatilityTerciles(teDir, teT, nTe, teVlC, teVlR, ea, eb);
   int trRgC[], trRgR[]; MksStatRegime(trDir, nTr, InpRegimePeriod, InpRegimeThresh, trRgC, trRgR);
   int teRgC[], teRgR[]; MksStatRegime(teDir, nTe, InpRegimePeriod, InpRegimeThresh, teRgC, teRgR);

   //--- FULL (marcadores gated por z; N grande) ---
   Print("");
   PrintFormat("=== RESULTADO FULL (N=%d bricks) ===", n);
   PrintFormat("OVERALL P(continua)=%.4f  z=%+.1f%s",
               pOverall, MksStatZ(oc, orv), DevZ(oc, orv));
   Print("");
   Print("[A] RUN-LENGTH -> continuacao (pergunta fundamental do Renko):");
   for(int k = 1; k <= InpMaxRunLen; k++)
   {
      int nn = rlCont[k] + rlRev[k];
      if(nn == 0) continue;
      PrintFormat("  apos run==%d: P=%.4f z=%+.1f N=%d%s",
                  k, MksStatProb(rlCont[k], rlRev[k]), MksStatZ(rlCont[k], rlRev[k]), nn,
                  DevZ(rlCont[k], rlRev[k]));
   }
   Print("");
   Print("[C] VOLATILIDADE (velocidade de formacao):");
   string volLbl[] = {"baixa", "media", "alta "};
   for(int b = 0; b < 3; b++)
      PrintFormat("  vol %s: P=%.4f z=%+.1f N=%d%s",
                  volLbl[b], MksStatProb(volCont[b], volRev[b]), MksStatZ(volCont[b], volRev[b]),
                  volCont[b] + volRev[b], DevZ(volCont[b], volRev[b]));
   Print("");
   Print("[B] REGIME:");
   PrintFormat("  trend  : P=%.4f z=%+.1f N=%d%s",
               MksStatProb(rgCont[0], rgRev[0]), MksStatZ(rgCont[0], rgRev[0]),
               rgCont[0] + rgRev[0], DevZ(rgCont[0], rgRev[0]));
   PrintFormat("  lateral: P=%.4f z=%+.1f N=%d%s",
               MksStatProb(rgCont[1], rgRev[1]), MksStatZ(rgCont[1], rgRev[1]),
               rgCont[1] + rgRev[1], DevZ(rgCont[1], rgRev[1]));
   Print("");
   Print("[D] HORA DO DIA (UTC):");
   for(int h = 0; h < 24; h++)
   {
      int nn = hrCont[h] + hrRev[h];
      if(nn == 0) continue;
      PrintFormat("  %02d:00: P=%.4f z=%+.1f N=%d%s",
                  h, MksStatProb(hrCont[h], hrRev[h]), MksStatZ(hrCont[h], hrRev[h]), nn,
                  DevZ(hrCont[h], hrRev[h]));
   }

   //--- OUT-OF-SAMPLE: o sinal do FULL replica ao dividir em 2 metades? ---
   Print("");
   PrintFormat("=== OUT-OF-SAMPLE (train=%d / test=%d) — o sinal REPLICA? ===", nTr, nTe);
   Print("  mostra so cells com |z_full|>=2. REPLICA=ambas metades signif. mesmo lado;");
   Print("  INVERTE=lados opostos; INSTAVEL=so 1 metade; SUMIU=nenhuma metade robusta.");
   PrintOosRow("overall", oc, orv, trOc, trOr, teOc, teOr);
   for(int k = 1; k <= InpMaxRunLen; k++)
      if(MathAbs(MksStatZ(rlCont[k], rlRev[k])) >= 2.0)
         PrintOosRow("run=="+IntegerToString(k),
                     rlCont[k], rlRev[k], trRlC[k], trRlR[k], teRlC[k], teRlR[k]);
   PrintOosRow("regime trend", rgCont[0], rgRev[0], trRgC[0], trRgR[0], teRgC[0], teRgR[0]);
   PrintOosRow("regime later", rgCont[1], rgRev[1], trRgC[1], trRgR[1], teRgC[1], teRgR[1]);
   for(int b = 0; b < 3; b++)
      PrintOosRow("vol "+volLbl[b], volCont[b], volRev[b], trVlC[b], trVlR[b], teVlC[b], teVlR[b]);
   int hoursShown = 0;
   for(int h = 0; h < 24; h++)
      if(MathAbs(MksStatZ(hrCont[h], hrRev[h])) >= 2.0)
      {
         PrintOosRow("hora "+StringFormat("%02d", h),
                     hrCont[h], hrRev[h], trHrC[h], trHrR[h], teHrC[h], teHrR[h]);
         hoursShown++;
      }
   if(hoursShown == 0) Print("  (nenhuma hora com |z_full|>=2 — sem candidato horario)");

   //--- TSV versionavel (full + train + test + veredito) ---
   FolderCreate("MKS-ULTIMATE\\Research");
   string path = StringFormat("MKS-ULTIMATE\\Research\\characterize_%s.tsv", symbol);
   int fh = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(fh == INVALID_HANDLE)
      PrintFormat("FileOpen falhou (%s) lastErr=%d — resultado so no Experts.",
                  path, GetLastError());
   else
   {
      FileWrite(fh, StringFormat("# characterize symbol=%s from=%s to=%s bricks=%d "
                "bull=%d bear=%d S=%s utcOffset=%d overallP=%.4f trainN=%d testN=%d",
                symbol, TimeToString(from), TimeToString(to), n, sink.bull, sink.bear,
                Fmt(InpBrickSizePts), InpUtcOffsetHrs, pOverall, nTr, nTe));
      FileWrite(fh, "section\tkey\tcont\trev\tn\tp\tz\ttrain_p\ttrain_z\ttest_p\ttest_z\tverdict");
      FileWrite(fh, TsvRow("OVERALL", "all", oc, orv, trOc, trOr, teOc, teOr));
      for(int k = 1; k <= InpMaxRunLen; k++)
         FileWrite(fh, TsvRow("RUNLEN", IntegerToString(k),
                   rlCont[k], rlRev[k], trRlC[k], trRlR[k], teRlC[k], teRlR[k]));
      string volKey[] = {"low", "mid", "high"};
      for(int b = 0; b < 3; b++)
         FileWrite(fh, TsvRow("VOL", volKey[b],
                   volCont[b], volRev[b], trVlC[b], trVlR[b], teVlC[b], teVlR[b]));
      FileWrite(fh, TsvRow("REGIME", "trend", rgCont[0], rgRev[0], trRgC[0], trRgR[0], teRgC[0], teRgR[0]));
      FileWrite(fh, TsvRow("REGIME", "lateral", rgCont[1], rgRev[1], trRgC[1], trRgR[1], teRgC[1], teRgR[1]));
      for(int h = 0; h < 24; h++)
         FileWrite(fh, TsvRow("HOUR", StringFormat("%02d", h),
                   hrCont[h], hrRev[h], trHrC[h], trHrR[h], teHrC[h], teHrR[h]));
      FileClose(fh);
      PrintFormat("TSV: %s\\MQL5\\Files\\%s", TerminalInfoString(TERMINAL_DATA_PATH), path);
   }
   Print("=== fim ===");
}
//+------------------------------------------------------------------+
