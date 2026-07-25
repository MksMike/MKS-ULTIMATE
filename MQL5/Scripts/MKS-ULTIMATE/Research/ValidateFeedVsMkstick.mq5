//+------------------------------------------------------------------+
//| @file           : ValidateFeedVsMkstick.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Research
//| @responsibility : R8 (research-only) — VALIDA o feed da pesquisa. O
//|                   toolkit de research monta bricks sobre CopyTicksRange
//|                   (histórico do broker), mas o projeto inteiro existe
//|                   porque esse feed NÃO é confiável (é o motivo do
//|                   TickRecorder/.mkstick). Este script monta a série de
//|                   bricks das DUAS fontes na MESMA janela — (A) do
//|                   `.mkstick` capturado (feed confiável) e (B) do
//|                   CopyTicksRange — e compara brick-a-brick (dir/trigger/
//|                   close/time). Se batem, o research roda sobre feed fiel;
//|                   se divergem, quantifica o quanto e onde.
//| @depends_on     : Research/CMksBrickSeries.mqh,
//|                   Core/Data/CMksFileTickSource.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Research/ValidateFeedVsMkstick.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Research/CMksBrickSeries.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksFileTickSource.mqh>

input string InpMksTickPath  = "MKS-ULTIMATE\\golden\\XAUUSDm_CR_20260720T233245.mkstick";
input string InpSymbol       = "XAUUSDm";  // DEVE casar com o símbolo do .mkstick (fatal)
input double InpBrickSizePts = 3.0;        // S do golden E2 (classic)
input double InpPriceTol     = 1e-6;       // tolerância de preço p/ divergência

void OnStart()
{
   string broker  = AccountInfoString(ACCOUNT_COMPANY);
   long   account = AccountInfoInteger(ACCOUNT_LOGIN);

   Print("");
   Print("=== ValidateFeedVsMkstick (R8 — feed da pesquisa vs .mkstick) ===");
   PrintFormat("mkstick=%s symbol=%s S=%.3f", InpMksTickPath, InpSymbol, InpBrickSizePts);

   //--- A: bricks do .mkstick capturado (feed confiável) ---
   CMksFileTickSource src(InpMksTickPath, broker, account, InpSymbol);
   MksError err;
   if(!src.Open(err))
   {
      PrintFormat("falha ao abrir .mkstick: %s. Abortando.", err.ToString());
      return;
   }
   if(src.BrokerMismatch())  Print("WARN: " + src.BrokerMismatchMsg());
   if(src.AccountMismatch()) Print("WARN: " + src.AccountMismatchMsg());

   long firstMsc = src.TimeMscFirst();
   long lastMsc  = src.TimeMscLast();
   PrintFormat("mkstick: ticks=%I64d  janela=[%s .. %s]  digits=%d",
               src.TickCount(),
               TimeToString((datetime)(firstMsc / 1000), TIME_DATE|TIME_MINUTES),
               TimeToString((datetime)(lastMsc  / 1000), TIME_DATE|TIME_MINUTES),
               src.Digits());

   MksRenkoGeometry geom = MksGeometryClassic();
   CMksFixedBrickSizer sizerA(InpBrickSizePts);
   MksError szErr;
   if(!sizerA.Validate(szErr)) { PrintFormat("sizer inválido: %s", szErr.ToString()); return; }
   CMksBrickSeriesCollector sinkA;
   CMksRenkoBuilder builderA(geom, GetPointer(sizerA), GetPointer(sinkA));
   MksTick t;
   while(src.Next(t)) { MksError e; builderA.IngestTick(t, e); }
   src.Close();
   PrintFormat("A (.mkstick):   bricks=%d (BULL=%d BEAR=%d)", sinkA.count, sinkA.bull, sinkA.bear);

   //--- B: bricks do CopyTicksRange na MESMA janela ---
   CMksBrickSeriesCollector sinkB;
   datetime from = (datetime)(firstMsc / 1000);
   datetime to   = (datetime)(lastMsc  / 1000) + 1;   // +1s p/ incluir o último tick
   Print("B (CopyTicks): carregando a mesma janela...");
   if(MksLoadBrickSeries(InpSymbol, from, to, InpBrickSizePts, sinkB) < 0) return;

   //--- Comparação brick-a-brick ---
   int nA = sinkA.count, nB = sinkB.count;
   int cmp = (nA < nB) ? nA : nB;
   int dirD = 0, trigD = 0, closeD = 0, timeD = 0, firstDivg = -1;
   for(int i = 0; i < cmp; i++)
   {
      bool d  = (sinkA.dir[i] != sinkB.dir[i]);
      bool tr = (MathAbs(sinkA.trigger[i] - sinkB.trigger[i]) > InpPriceTol);
      bool cl = (MathAbs(sinkA.close[i]   - sinkB.close[i])   > InpPriceTol);
      bool tm = (sinkA.t[i] != sinkB.t[i]);
      if(d)  dirD++;
      if(tr) trigD++;
      if(cl) closeD++;
      if(tm) timeD++;
      if((d || tr || cl || tm) && firstDivg < 0) firstDivg = i;
   }

   Print("");
   Print("=== COMPARACAO A(.mkstick) vs B(CopyTicks) ===");
   PrintFormat("bricks: A=%d  B=%d  %s", nA, nB, (nA == nB) ? "(mesmo total)" : "(TOTAL DIFERE)");
   PrintFormat("divergencias em %d bricks comparados: dir=%d trigger=%d close=%d time=%d",
               cmp, dirD, trigD, closeD, timeD);
   if(firstDivg >= 0)
      PrintFormat("1a divergencia @ brick #%d: A(dir=%d trig=%.3f t=%I64d)  B(dir=%d trig=%.3f t=%I64d)",
                  firstDivg, sinkA.dir[firstDivg], sinkA.trigger[firstDivg], sinkA.t[firstDivg],
                  sinkB.dir[firstDivg], sinkB.trigger[firstDivg], sinkB.t[firstDivg]);

   bool perfect = (nA == nB && dirD == 0 && trigD == 0 && closeD == 0 && timeD == 0);
   Print("");
   Print(perfect
      ? ">>> FEED VALIDADO: CopyTicks == .mkstick brick-a-brick. A pesquisa roda sobre feed FIEL ao capturado."
      : ">>> FEED DIVERGE: CopyTicks != .mkstick. A pesquisa roda sobre feed NAO-identico ao capturado — quantificado acima (backfill/revisao do broker?).");
   Print("=== fim ===");
}
//+------------------------------------------------------------------+
