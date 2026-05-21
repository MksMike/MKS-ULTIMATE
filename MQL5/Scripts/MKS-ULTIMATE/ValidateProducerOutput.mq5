//+------------------------------------------------------------------+
//| @file           : ValidateProducerOutput.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE
//| @responsibility : Abre um arquivo .mksbk gerado pelo Producer EA,
//|                   valida header + integridade e imprime resumo
//|                   (proveniência, geometria, agregados de bricks).
//|                   Apoio de validação do Slice 3b.
//| @depends_on     : Core/Data/CMksBrickFileReader.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/Error.mqh,
//|                   Core/Types/RenkoGeometry.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/ValidateProducerOutput.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Data/CMksBrickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>

input string InpFilePath      = ""; // vazio => último .mksbk em MKS-ULTIMATE\Bricks\
input int    InpPrintFirstN   = 3;  // imprime os N primeiros bricks
input int    InpPrintLastN    = 3;  // imprime os N últimos bricks
input bool   InpPrintAll      = false; // sobrescreve First/Last e imprime todos

string FormatTimeMsc(long timeMsc)
{
   datetime dt = (datetime)(timeMsc / 1000);
   return TimeToString(dt, TIME_DATE|TIME_SECONDS);
}

string FormatBrick(const MksBrick &b, int digits)
{
   return StringFormat("%s open=%s close=%s high=%s low=%s M=%d trigger=%s tickId=%I64u time=%s",
                       b.IsBull() ? "BULL" : "BEAR",
                       DoubleToString(b.open,  digits),
                       DoubleToString(b.close, digits),
                       DoubleToString(b.high,  digits),
                       DoubleToString(b.low,   digits),
                       b.thresholdsCrossed,
                       DoubleToString(b.triggerPrice, digits),
                       b.triggerTickId,
                       FormatTimeMsc(b.closeTimeMsc));
}

// Procura o arquivo .mksbk com timestamp lexicograficamente maior.
// Funciona porque o nome é "<symbol>_YYYYMMDDTHHMMSS.mksbk" (width fixa).
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

void OnStart()
{
   string path = InpFilePath;
   if(StringLen(path) == 0)
   {
      path = FindMostRecentBrickFile();
      if(StringLen(path) == 0)
      {
         Print("Nenhum .mksbk encontrado em MKS-ULTIMATE\\Bricks\\.");
         return;
      }
   }

   Print("");
   Print("=== ValidateProducerOutput ===");
   PrintFormat("arquivo: %s", path);

   CMksBrickFileReader reader;
   MksError err;
   if(!reader.Open(path, err))
   {
      PrintFormat("Open falhou: %s", err.ToString());
      return;
   }

   // Header / proveniência.
   PrintFormat("provenance: broker=\"%s\" account=%I64d symbol=%s digits=%d",
               reader.Broker(), reader.AccountLogin(),
               reader.Symbol(), reader.Digits());
   MksRenkoGeometry geom = reader.Geometry();
   PrintFormat("geometry: %s  brickSizePoints=%.4f",
               geom.ToString(), reader.BrickSizePoints());
   PrintFormat("brickCount=%I64d timeFirst=%s timeLast=%s createdAt=%s",
               reader.BrickCount(),
               FormatTimeMsc(reader.TimeMscFirst()),
               FormatTimeMsc(reader.TimeMscLast()),
               FormatTimeMsc(reader.CreatedAtMsc()));

   // Comparação contra conta corrente — warn-only (ADR-013 §3 / ADR-012 §3).
   string curBroker  = AccountInfoString(ACCOUNT_COMPANY);
   long   curAccount = AccountInfoInteger(ACCOUNT_LOGIN);
   if(StringCompare(reader.Broker(), curBroker) != 0)
      PrintFormat("WARN: broker do arquivo (%s) difere da conta corrente (%s)",
                  reader.Broker(), curBroker);
   if(reader.AccountLogin() != curAccount)
      PrintFormat("WARN: account do arquivo (%I64d) difere da conta corrente (%I64d)",
                  reader.AccountLogin(), curAccount);

   if(reader.BrickCount() == 0)
   {
      Print("Arquivo sem bricks (sessão sem cruzamento de threshold).");
      reader.Close();
      Print("=== fim ===");
      return;
   }

   int digits = reader.Digits();
   long total = reader.BrickCount();
   int firstN = (InpPrintAll ? (int)total : InpPrintFirstN);
   int lastN  = (InpPrintAll ? 0         : InpPrintLastN);

   int bullCount = 0, bearCount = 0;
   int mEq1 = 0, m2to5 = 0, m6to10 = 0, mGt10 = 0;
   MksBrick first;
   MksBrick last;
   bool hasFirst = false;

   // Buffer dos últimos N (lista circular simples) para imprimir no fim.
   int lastBufSize = (lastN > 0) ? lastN : 0;
   MksBrick lastBuf[];
   if(lastBufSize > 0)
   {
      ArrayResize(lastBuf, lastBufSize);
   }
   int lastBufHead = 0;
   int lastBufCount = 0;

   Print("");
   PrintFormat("--- primeiros %d bricks ---", firstN);
   for(long i = 0; i < total; i++)
   {
      MksBrick b;
      if(!reader.ReadNext(b, err))
      {
         PrintFormat("ReadNext falhou em i=%I64d: %s", i, err.ToString());
         break;
      }
      if(!hasFirst) { first = b; hasFirst = true; }
      last = b;

      if(b.IsBull()) bullCount++; else bearCount++;
      int m = b.thresholdsCrossed;
      if(m == 1) mEq1++;
      else if(m <= 5)  m2to5++;
      else if(m <= 10) m6to10++;
      else             mGt10++;

      if(InpPrintAll || i < firstN)
         PrintFormat("  [%I64d] %s", i, FormatBrick(b, digits));

      if(lastBufSize > 0)
      {
         lastBuf[lastBufHead] = b;
         lastBufHead = (lastBufHead + 1) % lastBufSize;
         if(lastBufCount < lastBufSize) lastBufCount++;
      }
   }

   if(!InpPrintAll && lastBufCount > 0 && total > firstN + lastBufCount)
   {
      Print("");
      PrintFormat("--- últimos %d bricks ---", lastBufCount);
      // Recompõe na ordem cronológica.
      int start = (lastBufHead - lastBufCount + lastBufSize) % lastBufSize;
      for(int k = 0; k < lastBufCount; k++)
      {
         int idx = (start + k) % lastBufSize;
         long absoluteIdx = total - lastBufCount + k;
         PrintFormat("  [%I64d] %s", absoluteIdx, FormatBrick(lastBuf[idx], digits));
      }
   }

   reader.Close();

   Print("");
   Print("=== RESUMO ===");
   PrintFormat("bricks: total=%I64d BULL=%d BEAR=%d", total, bullCount, bearCount);
   PrintFormat("thresholdsCrossed: M=1: %d  M=2..5: %d  M=6..10: %d  M>10: %d",
               mEq1, m2to5, m6to10, mGt10);
   PrintFormat("primeiro: %s", FormatBrick(first, digits));
   PrintFormat("último:   %s", FormatBrick(last,  digits));
   Print("=== fim ===");
}
//+------------------------------------------------------------------+
