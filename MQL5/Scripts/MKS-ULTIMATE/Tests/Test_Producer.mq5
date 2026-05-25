//+------------------------------------------------------------------+
//| @file           : Test_Producer.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Valida o output do Producer EA contra reconstrução
//|                   textbook de Renko classico sobre o mesmo stream de
//|                   ticks. Abre o .mksbk, carrega CopyTicksRange na
//|                   janela em que os bricks se formaram, roda algoritmo
//|                   classico minimo (mid-driven, threshold +/-S simetrico,
//|                   guarda K e L), e compara campo-a-campo. ESBOCO inicial.
//| @depends_on     : Core/Data/CMksBrickFileReader.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/Error.mqh, Core/Types/RenkoGeometry.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_Producer.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Data/CMksBrickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>

input string InpMksbkPath        = "";    // vazio => mais recente em MKS-ULTIMATE\Bricks
input int    InpTickWindowDays   = 30;    // dias antes de createdAt para carregar ticks
input int    InpMaxDivergences   = 10;    // para reportar as N primeiras divergencias
input int    InpInvalidLimit     = 10;    // L (ADR-006), espelha Producer default
input int    InpThresholdLimit   = 20;    // K (ADR-011), espelha Producer default
input bool   InpVerbose          = false; // imprime cada brick textbook (debug)

//+------------------------------------------------------------------+
//| Formatadores                                                      |
//+------------------------------------------------------------------+
string FmtTime(long timeMsc)
{
   datetime dt = (datetime)(timeMsc / 1000);
   return TimeToString(dt, TIME_DATE|TIME_SECONDS);
}

string FmtBrick(const MksBrick &b, int digits)
{
   return StringFormat("%s open=%s close=%s M=%d trigger=%s time=%s",
                       b.IsBull() ? "BULL" : "BEAR",
                       DoubleToString(b.open,  digits),
                       DoubleToString(b.close, digits),
                       b.thresholdsCrossed,
                       DoubleToString(b.triggerPrice, digits),
                       FmtTime(b.closeTimeMsc));
}

string FindMostRecentBrickFile()
{
   string pattern = "MKS-ULTIMATE\\Bricks\\*.mksbk";
   string found = "";
   string best  = "";
   long   h = FileFindFirst(pattern, found);
   if(h == INVALID_HANDLE) return "";
   do
   {
      if(StringCompare(found, best) > 0) best = found;
   }
   while(FileFindNext(h, found));
   FileFindClose(h);
   if(StringLen(best) == 0) return "";
   return "MKS-ULTIMATE\\Bricks\\" + best;
}

//+------------------------------------------------------------------+
//| Reconstrucao textbook de Renko classico.                          |
//|                                                                   |
//| Mid-driven (ADR-010 §4). Threshold simetrico +/-S (classic,       |
//| ADR-026). Guarda L de ticks invalidos consecutivos (ADR-006 §5).  |
//| Guarda K de cruzamentos multi-threshold por tick (ADR-011 §4).    |
//|                                                                   |
//| NAO emite forming brick, NAO calcula brick.high/low (so OHLC      |
//| open/close de level — campos suficientes pra checar paridade      |
//| matematica com .mksbk). Volume = 0.                               |
//+------------------------------------------------------------------+
void ReconstructTextbookClassic(const MqlTick &ticks[],
                                 int    nTicks,
                                 double sizeUsd,
                                 int    invalidLimit,
                                 int    thresholdLimit,
                                 MksBrick &outBricks[],
                                 int    &outCount,
                                 int    &outInvalidSeen,
                                 int    &outKExceeded,
                                 bool   &outStreamCorrupt)
{
   ArrayResize(outBricks, 0);
   outCount = 0;
   outInvalidSeen = 0;
   outKExceeded = 0;
   outStreamCorrupt = false;

   bool   initialized = false;
   bool   hasFirst    = false;
   double lastClose   = 0.0;
   int    lastDir     = +1;
   int    consecutiveInvalid = 0;

   for(int i = 0; i < nTicks; i++)
   {
      // Espelha MksTick::IsValid: bid>0, ask>0, ask>=bid.
      bool valid = (ticks[i].bid > 0.0 && ticks[i].ask > 0.0 && ticks[i].ask >= ticks[i].bid);
      if(!valid)
      {
         outInvalidSeen++;
         consecutiveInvalid++;
         if(consecutiveInvalid >= invalidLimit)
         {
            outStreamCorrupt = true;
            return;
         }
         continue;
      }
      consecutiveInvalid = 0;

      double mid = (ticks[i].bid + ticks[i].ask) / 2.0;

      if(!initialized)
      {
         initialized = true;
         lastClose = mid;
         continue;
      }

      // Walk staircase. Para classic, continuation e reversal sao
      // simetricamente +/-sizeUsd a partir de walkClose.
      int    M = 0;
      double walkClose = lastClose;
      int    walkDir;
      bool   kExceeded = false;

      if(!hasFirst)
      {
         if(mid == lastClose) continue;
         walkDir = (mid > lastClose) ? +1 : -1;
      }
      else
      {
         walkDir = lastDir;
      }

      while(true)
      {
         double contThr = walkClose + walkDir * sizeUsd;
         double revThr  = walkClose - walkDir * sizeUsd;
         bool crossedCont = (walkDir == +1) ? (mid >= contThr) : (mid <= contThr);
         bool crossedRev  = false;
         if(hasFirst)
            crossedRev = (walkDir == +1) ? (mid <= revThr) : (mid >= revThr);

         if(crossedCont)
         {
            M++;
            walkClose = contThr;
         }
         else if(crossedRev)
         {
            M++;
            walkClose = revThr;
            walkDir = -walkDir;
         }
         else
         {
            break;
         }

         if(M > thresholdLimit)
         {
            kExceeded = true;
            outKExceeded++;
            break;
         }
      }

      if(kExceeded) continue; // ADR-011 §4: descarta tick, nao emite

      if(M >= 1)
      {
         MksBrick b;
         b.direction         = (walkDir == +1) ? MKS_BRICK_BULL : MKS_BRICK_BEAR;
         b.open              = lastClose;
         b.close             = walkClose;
         b.high              = MathMax(b.open, b.close);
         b.low               = MathMin(b.open, b.close);
         b.thresholdsCrossed = M;
         b.triggerPrice      = mid;
         b.triggerTickId     = 0; // textbook nao numera ticks
         b.closeTimeMsc      = ticks[i].time_msc;
         b.volume            = 0;

         int n = ArraySize(outBricks);
         ArrayResize(outBricks, n + 1);
         outBricks[n] = b;
         outCount++;

         lastClose = walkClose;
         lastDir   = walkDir;
         hasFirst  = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Compara um par de bricks (.mksbk vs textbook).                    |
//| Tolerancia: open/close/trigger a meio-point para nao tropecar em  |
//| arredondamento. closeTimeMsc exato (vem do mesmo tick). M exato.  |
//+------------------------------------------------------------------+
bool BricksMatch(const MksBrick &a, const MksBrick &b, double epsilon, string &diffMsg)
{
   diffMsg = "";
   if(a.direction != b.direction)
   {
      diffMsg = StringFormat("direction A=%s B=%s",
                              a.IsBull() ? "BULL" : "BEAR",
                              b.IsBull() ? "BULL" : "BEAR");
      return false;
   }
   if(MathAbs(a.open - b.open) > epsilon)
   {
      diffMsg = StringFormat("open A=%.5f B=%.5f", a.open, b.open);
      return false;
   }
   if(MathAbs(a.close - b.close) > epsilon)
   {
      diffMsg = StringFormat("close A=%.5f B=%.5f", a.close, b.close);
      return false;
   }
   if(a.thresholdsCrossed != b.thresholdsCrossed)
   {
      diffMsg = StringFormat("M A=%d B=%d", a.thresholdsCrossed, b.thresholdsCrossed);
      return false;
   }
   if(a.closeTimeMsc != b.closeTimeMsc)
   {
      diffMsg = StringFormat("closeTimeMsc A=%I64d B=%I64d",
                              a.closeTimeMsc, b.closeTimeMsc);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
void OnStart()
{
   string path = (StringLen(InpMksbkPath) > 0) ? InpMksbkPath : FindMostRecentBrickFile();
   if(StringLen(path) == 0)
   {
      Print("Nenhum .mksbk encontrado em MKS-ULTIMATE\\Bricks\\.");
      return;
   }

   Print("");
   Print("=== Test_Producer ===");
   PrintFormat("arquivo: %s", path);

   //--- 1. Abre .mksbk, valida header.
   CMksBrickFileReader reader;
   MksError err;
   if(!reader.Open(path, err))
   {
      PrintFormat("FAIL: reader.Open: %s", err.ToString());
      return;
   }

   string symbol = reader.Symbol();
   int    digits = reader.Digits();
   double sizeUsd = reader.BrickSizePoints();
   MksRenkoGeometry geom = reader.Geometry();
   long   timeFirst  = reader.TimeMscFirst();
   long   timeLast   = reader.TimeMscLast();
   long   createdAt  = reader.CreatedAtMsc();
   long   brickCount = reader.BrickCount();

   PrintFormat("symbol=%s digits=%d brickSize=%.4f geom=(po=%.2f pro=%.2f rev=%.2f)",
               symbol, digits, sizeUsd, geom.po, geom.pro, geom.revSizeRatio);
   PrintFormat("brickCount=%I64d timeFirst=%s timeLast=%s",
               brickCount, FmtTime(timeFirst), FmtTime(timeLast));

   //--- 2. Esta versao do test so cobre classic (ADR-026).
   if(MathAbs(geom.po) > 1e-9 || MathAbs(geom.pro) > 1e-9 ||
      MathAbs(geom.revSizeRatio - 1.0) > 1e-9)
   {
      Print("SKIP: este test cobre apenas geometria classic (po=pro=0, rev=1.0).");
      Print("      .mksbk gerado com preset diferente — abortando.");
      reader.Close();
      return;
   }

   if(brickCount == 0)
   {
      Print("Arquivo sem bricks. Nada a validar.");
      reader.Close();
      return;
   }

   //--- 3. Le todos os bricks do .mksbk.
   MksBrick fileBricks[];
   ArrayResize(fileBricks, (int)brickCount);
   for(int i = 0; i < (int)brickCount; i++)
   {
      if(!reader.ReadNext(fileBricks[i], err))
      {
         PrintFormat("FAIL: ReadNext i=%d: %s", i, err.ToString());
         reader.Close();
         return;
      }
   }
   reader.Close();

   //--- 4. Carrega ticks na janela [createdAt - histDays, timeLast + 1s].
   //       O Producer inicializou lastClose a partir do primeiro tick valido
   //       da sua janela de fill historico. Reproduzimos isso usando a mesma
   //       janela (default 30 dias, espelha Producer default).
   long fromMsc = createdAt - (long)InpTickWindowDays * 24L * 3600L * 1000L;
   long toMsc   = timeLast + 1000L; // +1s margem
   PrintFormat("loading ticks: from=%s to=%s (window=%d days)",
               FmtTime(fromMsc), FmtTime(toMsc), InpTickWindowDays);

   MqlTick ticks[];
   int nTicks = CopyTicksRange(symbol, ticks, COPY_TICKS_ALL, fromMsc, toMsc);
   if(nTicks <= 0)
   {
      PrintFormat("FAIL: CopyTicksRange retornou %d. GetLastError=%d.",
                  nTicks, GetLastError());
      return;
   }
   PrintFormat("ticks carregados: %d", nTicks);

   //--- 5. Reconstrucao textbook.
   MksBrick textbookBricks[];
   int  textbookCount = 0;
   int  invalidSeen = 0;
   int  kExceeded   = 0;
   bool streamCorrupt = false;
   ReconstructTextbookClassic(ticks, nTicks, sizeUsd,
                               InpInvalidLimit, InpThresholdLimit,
                               textbookBricks, textbookCount,
                               invalidSeen, kExceeded, streamCorrupt);

   PrintFormat("textbook: bricks=%d invalidTicks=%d kExceeded=%d streamCorrupt=%s",
               textbookCount, invalidSeen, kExceeded,
               (streamCorrupt ? "true" : "false"));

   if(InpVerbose)
   {
      Print("--- bricks textbook (verbose) ---");
      for(int i = 0; i < textbookCount; i++)
         PrintFormat("  [%d] %s", i, FmtBrick(textbookBricks[i], digits));
   }

   //--- 6. Comparacao brick-a-brick.
   //
   // Sem matchar triggerTickId (textbook nao numera ticks). Sem matchar
   // high/low (textbook nao rastreia formingHigh/formingLow, so retorna
   // bounding box trivial). Esses dois precisam de Layer A (replay via
   // CMksRenkoBuilder) — fora do escopo deste primeiro draft.
   double pointVal = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(pointVal <= 0.0) pointVal = MathPow(10.0, -digits);
   double epsilon = pointVal * 0.5;

   int matches      = 0;
   int divergences  = 0;
   int divsReported = 0;
   int minLen = MathMin((int)brickCount, textbookCount);

   Print("");
   Print("--- comparacao ---");
   for(int i = 0; i < minLen; i++)
   {
      string diffMsg;
      if(BricksMatch(fileBricks[i], textbookBricks[i], epsilon, diffMsg))
      {
         matches++;
      }
      else
      {
         divergences++;
         if(divsReported < InpMaxDivergences)
         {
            divsReported++;
            PrintFormat("DIVERG [%d] %s", i, diffMsg);
            PrintFormat("  .mksbk   : %s", FmtBrick(fileBricks[i], digits));
            PrintFormat("  textbook : %s", FmtBrick(textbookBricks[i], digits));
         }
      }
   }

   if((int)brickCount != textbookCount)
   {
      PrintFormat("WARN: contagem divergente — .mksbk=%I64d textbook=%d",
                  brickCount, textbookCount);
   }

   //--- 7. Veredito.
   Print("");
   Print("=== RESUMO ===");
   PrintFormat("comparados: %d", minLen);
   PrintFormat("matches:    %d", matches);
   PrintFormat("divergencias: %d", divergences);
   PrintFormat("contagem total: .mksbk=%I64d textbook=%d (delta=%d)",
               brickCount, textbookCount, (int)brickCount - textbookCount);

   bool pass = (divergences == 0) && ((int)brickCount == textbookCount);
   PrintFormat("VEREDITO: %s", (pass ? "PASS" : "FAIL"));
   Print("=== fim ===");
}
//+------------------------------------------------------------------+