//+------------------------------------------------------------------+
//| @file           : DumpMksTick.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE
//| @responsibility : Abre um arquivo .mkstick gerado pelo TickRecorder,
//|                   valida header + integridade e imprime resumo
//|                   detalhado (proveniência, range temporal, primeiros
//|                   e últimos ticks, estatísticas de spread e gaps
//|                   temporais). Permite inspeção visual humana da
//|                   qualidade da captura antes de usar como fonte
//|                   de backtest via Replayer.
//| @depends_on     : Core/Data/CMksTickFileReader.mqh,
//|                   Core/Types/Tick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/DumpMksTick.mq5
//+------------------------------------------------------------------+
#property script_show_inputs
#property copyright "MKS-ULTIMATE"

#include <MKS-ULTIMATE/Core/Data/CMksTickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

input string InpFilePath      = "";  // vazio => último .mkstick em MKS-ULTIMATE\Ticks\
input int    InpPrintFirstN   = 5;   // imprime os N primeiros ticks
input int    InpPrintLastN    = 5;   // imprime os N últimos ticks
input long   InpGapThresholdMs = 5000; // alerta gaps temporais > N ms (default 5s)
input bool   InpPrintAll      = false; // sobrescreve First/Last e imprime todos

//+------------------------------------------------------------------+
//| Decodifica bitmask TICK_FLAG_* em string legível.                 |
//+------------------------------------------------------------------+
string DecodeFlags(uint flags)
{
   string parts[];
   ArrayResize(parts, 0);
   if((flags & TICK_FLAG_BID) != 0)    { ArrayResize(parts, ArraySize(parts)+1); parts[ArraySize(parts)-1] = "BID";    }
   if((flags & TICK_FLAG_ASK) != 0)    { ArrayResize(parts, ArraySize(parts)+1); parts[ArraySize(parts)-1] = "ASK";    }
   if((flags & TICK_FLAG_LAST) != 0)   { ArrayResize(parts, ArraySize(parts)+1); parts[ArraySize(parts)-1] = "LAST";   }
   if((flags & TICK_FLAG_VOLUME) != 0) { ArrayResize(parts, ArraySize(parts)+1); parts[ArraySize(parts)-1] = "VOLUME"; }
   if((flags & TICK_FLAG_BUY) != 0)    { ArrayResize(parts, ArraySize(parts)+1); parts[ArraySize(parts)-1] = "BUY";    }
   if((flags & TICK_FLAG_SELL) != 0)   { ArrayResize(parts, ArraySize(parts)+1); parts[ArraySize(parts)-1] = "SELL";   }
   if(ArraySize(parts) == 0) return "(none)";
   string s = parts[0];
   for(int i = 1; i < ArraySize(parts); i++) s += "|" + parts[i];
   return s;
}

//+------------------------------------------------------------------+
//| Formata timestamp em ms para "YYYY.MM.DD HH:MM:SS.fff".           |
//+------------------------------------------------------------------+
string FormatTimeMsc(long timeMsc)
{
   datetime dt  = (datetime)(timeMsc / 1000);
   int      ms  = (int)(timeMsc % 1000);
   return StringFormat("%s.%03d",
                       TimeToString(dt, TIME_DATE | TIME_SECONDS), ms);
}

//+------------------------------------------------------------------+
//| Formata um tick em uma linha humana-legível.                      |
//+------------------------------------------------------------------+
string FormatTick(const MksTick &t, int digits)
{
   return StringFormat("seq=%-7I64u %s  bid=%s  ask=%s  spread=%s  last=%s  vol=%I64d  flags=%s",
                       t.seq,
                       FormatTimeMsc(t.timeMsc),
                       DoubleToString(t.bid,    digits),
                       DoubleToString(t.ask,    digits),
                       DoubleToString(t.ask - t.bid, digits),
                       (t.last > 0.0 ? DoubleToString(t.last, digits) : "    -  "),
                       t.volume,
                       DecodeFlags(t.flags));
}

//+------------------------------------------------------------------+
//| Procura o .mkstick com timestamp lexicograficamente maior.        |
//+------------------------------------------------------------------+
string FindMostRecentTickFile()
{
   string pattern = "MKS-ULTIMATE\\Ticks\\*.mkstick";
   string found = "";
   string best  = "";
   long h = FileFindFirst(pattern, found);
   if(h == INVALID_HANDLE) return "";
   do
   {
      if(StringCompare(found, best) > 0) best = found;
   }
   while(FileFindNext(h, found));
   FileFindClose(h);
   if(StringLen(best) == 0) return "";
   return "MKS-ULTIMATE\\Ticks\\" + best;
}

//+------------------------------------------------------------------+
//| OnStart                                                           |
//+------------------------------------------------------------------+
void OnStart()
{
   string path = InpFilePath;
   if(StringLen(path) == 0)
   {
      path = FindMostRecentTickFile();
      if(StringLen(path) == 0)
      {
         Print("ERRO: nenhum .mkstick encontrado em MKS-ULTIMATE\\Ticks\\");
         return;
      }
   }

   Print("");
   Print("=== DumpMksTick ===");
   PrintFormat("arquivo: %s", path);

   CMksTickFileReader reader;
   MksError err;
   if(!reader.Open(path, err))
   {
      PrintFormat("ERRO ao abrir: %s", err.ToString());
      return;
   }

   //--- Header ---
   Print("");
   Print("--- Header / Proveniência ---");
   PrintFormat("broker         : %s", reader.Broker());
   PrintFormat("accountLogin   : %I64d", reader.AccountLogin());
   PrintFormat("symbol         : %s", reader.Symbol());
   PrintFormat("digits         : %d", reader.Digits());
   PrintFormat("tickSize       : %s", DoubleToString(reader.TickSize(), reader.Digits() + 2));
   PrintFormat("point          : %s", DoubleToString(reader.Point(),    reader.Digits() + 2));
   PrintFormat("contractSize   : %s", DoubleToString(reader.ContractSize(), 2));
   PrintFormat("tickCount      : %I64d", reader.TickCount());
   PrintFormat("timeMscFirst   : %s (%I64d)",
               FormatTimeMsc(reader.TimeMscFirst()), reader.TimeMscFirst());
   PrintFormat("timeMscLast    : %s (%I64d)",
               FormatTimeMsc(reader.TimeMscLast()),  reader.TimeMscLast());
   PrintFormat("createdAtMsc   : %s", FormatTimeMsc(reader.CreatedAtMsc()));
   PrintFormat("closedAtMsc    : %s%s",
               FormatTimeMsc(reader.ClosedAtMsc()),
               (reader.ClosedAtMsc() == 0 ? "  (zero — arquivo ainda aberto OU writer crashou sem Close)" : ""));

   long   durationMsc = reader.TimeMscLast() - reader.TimeMscFirst();
   double durationSec = durationMsc / 1000.0;
   double durationMin = durationSec / 60.0;
   PrintFormat("");
   PrintFormat("janela temporal: %.1fs = %.2f min = %.2f h",
               durationSec, durationMin, durationMin / 60.0);
   if(reader.TickCount() > 0 && durationSec > 0)
   {
      double tps = (double)reader.TickCount() / durationSec;
      PrintFormat("taxa média     : %.2f ticks/segundo (%.0f ticks/minuto)",
                  tps, tps * 60.0);
   }

   //--- Leitura completa + agregação ---
   long n = reader.TickCount();
   if(n == 0)
   {
      Print("");
      Print("Arquivo vazio (0 ticks). Nada para dumpar.");
      reader.Close();
      return;
   }

   int  digits     = reader.Digits();
   int  firstN     = MathMin(InpPrintFirstN, (int)n);
   int  lastN      = MathMin(InpPrintLastN,  (int)n);
   bool printAll   = InpPrintAll;

   // Estatísticas agregadas
   double spreadSum = 0.0, spreadMin = 1e18, spreadMax = -1e18;
   long   gapsAboveThreshold = 0;
   long   largestGapMsc = 0;
   long   prevTimeMsc = 0;
   long   uniqueTimestamps = 0;
   ulong  prevSeq = 0;
   long   seqGaps = 0;
   long   ticksWithLast = 0;
   long   ticksWithVolume = 0;
   long   ticksInvalidPrice = 0; // bid<=0 || ask<=0 || ask<bid

   // Bucket para últimos N ticks (circular)
   MksTick lastBuf[];
   ArrayResize(lastBuf, lastN);
   int lastBufHead = 0;
   int lastBufCount = 0;

   Print("");
   Print(StringFormat("--- Primeiros %d ticks ---", firstN));

   for(long i = 0; i < n; i++)
   {
      MksTick t;
      if(!reader.ReadNext(t, err))
      {
         PrintFormat("ERRO ao ler tick %I64d: %s", i, err.ToString());
         break;
      }

      // Estatísticas
      double sp = t.ask - t.bid;
      spreadSum += sp;
      if(sp < spreadMin) spreadMin = sp;
      if(sp > spreadMax) spreadMax = sp;

      if(t.bid <= 0.0 || t.ask <= 0.0 || t.ask < t.bid) ticksInvalidPrice++;
      if(t.last  > 0.0) ticksWithLast++;
      if(t.volume > 0)  ticksWithVolume++;

      if(i > 0)
      {
         long dt = t.timeMsc - prevTimeMsc;
         if(dt < 0) seqGaps++; // tempo regrediu — anomalia séria
         if(dt > InpGapThresholdMs) gapsAboveThreshold++;
         if(dt > largestGapMsc) largestGapMsc = dt;
         if(dt > 0) uniqueTimestamps++;
      }
      prevTimeMsc = t.timeMsc;
      prevSeq = t.seq;

      // Imprime primeiros
      if(i < firstN)
         PrintFormat("  [%I64d] %s", i, FormatTick(t, digits));

      // Imprime todos se modo verbose
      if(printAll && i >= firstN && i < n - lastN)
         PrintFormat("  [%I64d] %s", i, FormatTick(t, digits));

      // Buffer dos últimos N (sempre atualiza)
      lastBuf[lastBufHead] = t;
      lastBufHead = (lastBufHead + 1) % lastN;
      if(lastBufCount < lastN) lastBufCount++;
   }

   //--- Últimos N ---
   Print("");
   Print(StringFormat("--- Últimos %d ticks ---", lastN));
   long startIdx = n - lastN;
   if(startIdx < 0) startIdx = 0;
   // Ordena buffer circular para ordem cronológica
   int orderStart = (lastBufCount < lastN) ? 0 : lastBufHead;
   for(int k = 0; k < lastBufCount; k++)
   {
      int idx = (orderStart + k) % lastN;
      PrintFormat("  [%I64d] %s", startIdx + k, FormatTick(lastBuf[idx], digits));
   }

   //--- Estatísticas finais ---
   Print("");
   Print("--- Estatísticas ---");
   PrintFormat("ticks lidos              : %I64d (esperado %I64d)",
               reader.TicksRead(), n);
   double spreadAvg = (n > 0) ? spreadSum / (double)n : 0.0;
   PrintFormat("spread (bid-ask)         : min=%s  média=%s  max=%s",
               DoubleToString(spreadMin, digits),
               DoubleToString(spreadAvg, digits),
               DoubleToString(spreadMax, digits));
   PrintFormat("ticks com last > 0       : %I64d (%.1f%%)",
               ticksWithLast,
               n > 0 ? 100.0 * ticksWithLast / n : 0.0);
   PrintFormat("ticks com volume > 0     : %I64d (%.1f%%)",
               ticksWithVolume,
               n > 0 ? 100.0 * ticksWithVolume / n : 0.0);
   PrintFormat("ticks com preço inválido : %I64d%s",
               ticksInvalidPrice,
               ticksInvalidPrice > 0 ? "  ⚠ (bid<=0 OU ask<=0 OU ask<bid)" : "");
   PrintFormat("timestamps regredindo    : %I64d%s",
               seqGaps,
               seqGaps > 0 ? "  ⚠ (tick com timeMsc < anterior — anomalia séria!)" : " ✓");
   PrintFormat("gaps temporais > %I64dms  : %I64d",
               InpGapThresholdMs, gapsAboveThreshold);
   PrintFormat("maior gap temporal       : %I64d ms (%.2fs)",
               largestGapMsc, largestGapMsc / 1000.0);

   reader.Close();

   Print("");
   Print("=== DumpMksTick fim ===");
}
//+------------------------------------------------------------------+
