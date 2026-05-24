//+------------------------------------------------------------------+
//| @file           : Test_CMksMACD.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Valida CMksMACD comparando seus buffers contra
//|                   iMACD nativo com os mesmos parâmetros — mesma
//|                   fórmula (fast/slow EMA + SMA signal). Tolerância
//|                   default 1e-10 (família com smoothing recursivo
//|                   nas EMAs). Verifica:
//|                     1) MACD line bate com iMACD buffer 0
//|                     2) Signal line bate com iMACD buffer 1
//|                     3) Hist == MACD − Signal (consistência interna)
//|                     4) HistColor == 0 quando Hist >= 0, == 1 caso contrário
//| @depends_on     : Indicators/MKS-ULTIMATE/CMksMACD.mq5
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksMACD.mq5
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input int                InpFastPeriod    = 12;
input int                InpSlowPeriod    = 26;
input int                InpSignalPeriod  = 9;
input ENUM_APPLIED_PRICE InpAppliedPrice  = PRICE_CLOSE;
input int                InpBarsToCheck   = 500;
input double             InpTolerance     = 1e-10;

void OnStart()
{
   ResetLastError();

   int handle = iCustom(_Symbol, _Period,
                        "MKS-ULTIMATE\\CMksMACD",
                        InpFastPeriod,
                        InpSlowPeriod,
                        InpSignalPeriod,
                        InpAppliedPrice,
                        clrDodgerBlue, clrRed, clrLime, clrCrimson,
                        1, 3, STYLE_SOLID);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("FAIL: iCustom retornou INVALID_HANDLE. err=%d", GetLastError());
      return;
   }

   int truthHandle = iMACD(_Symbol, _Period,
                           InpFastPeriod, InpSlowPeriod, InpSignalPeriod,
                           InpAppliedPrice);
   if(truthHandle == INVALID_HANDLE)
   {
      PrintFormat("FAIL: iMACD truth INVALID_HANDLE. err=%d", GetLastError());
      IndicatorRelease(handle);
      return;
   }

   int total = Bars(_Symbol, _Period);
   int bars  = MathMin(InpBarsToCheck, total - (InpSlowPeriod + InpSignalPeriod) - 2);
   if(bars < 1)
   {
      PrintFormat("FAIL: bars insuficientes (total=%d, slow=%d, signal=%d)",
                  total, InpSlowPeriod, InpSignalPeriod);
      IndicatorRelease(handle);
      IndicatorRelease(truthHandle);
      return;
   }

   int attempts = 0;
   while((BarsCalculated(handle)      < bars ||
          BarsCalculated(truthHandle) < bars) && attempts < 50)
   {
      Sleep(100);
      attempts++;
   }
   if(BarsCalculated(handle) < bars || BarsCalculated(truthHandle) < bars)
   {
      PrintFormat("FAIL: nao calculou %d bars em ~5s (ind=%d truth=%d)",
                  bars, BarsCalculated(handle), BarsCalculated(truthHandle));
      IndicatorRelease(handle);
      IndicatorRelease(truthHandle);
      return;
   }

   double macdBuf[], signalBuf[], histBuf[], colorBuf[];
   double truthMACD[], truthSignal[];
   ArraySetAsSeries(macdBuf,     true);
   ArraySetAsSeries(signalBuf,   true);
   ArraySetAsSeries(histBuf,     true);
   ArraySetAsSeries(colorBuf,    true);
   ArraySetAsSeries(truthMACD,   true);
   ArraySetAsSeries(truthSignal, true);

   if(CopyBuffer(handle, 0, 0, bars, macdBuf)          <= 0 ||
      CopyBuffer(handle, 1, 0, bars, signalBuf)        <= 0 ||
      CopyBuffer(handle, 2, 0, bars, histBuf)          <= 0 ||
      CopyBuffer(handle, 3, 0, bars, colorBuf)         <= 0 ||
      CopyBuffer(truthHandle, 0, 0, bars, truthMACD)   <= 0 ||
      CopyBuffer(truthHandle, 1, 0, bars, truthSignal) <= 0)
   {
      PrintFormat("FAIL: CopyBuffer falhou. err=%d", GetLastError());
      IndicatorRelease(handle);
      IndicatorRelease(truthHandle);
      return;
   }

   int    macdErrors   = 0;
   int    signalErrors = 0;
   int    histErrors   = 0;
   int    colorErrors  = 0;
   int    firstErrAt   = -1;
   double maxDiff      = 0.0;
   string firstErrDetail = "";

   for(int s = 0; s < bars; s++)
   {
      double macdInd   = macdBuf[s];
      double signalInd = signalBuf[s];
      double histInd   = histBuf[s];
      double colorIdx  = colorBuf[s];
      double macdT     = truthMACD[s];
      double signalT   = truthSignal[s];

      // Pula bars sem MACD válido em qualquer dos lados.
      if(macdInd == EMPTY_VALUE) continue;

      // (1) MACD line
      double dMACD = MathAbs(macdInd - macdT);
      if(dMACD > maxDiff) maxDiff = dMACD;
      if(dMACD > InpTolerance)
      {
         macdErrors++;
         if(firstErrAt < 0)
         {
            firstErrAt = s;
            firstErrDetail = StringFormat("macd: ind=%.10f truth=%.10f diff=%.2e",
               macdInd, macdT, dMACD);
         }
      }

      // (2) Signal line — só compara onde está válido nos 2 lados
      if(signalInd != EMPTY_VALUE)
      {
         double dSig = MathAbs(signalInd - signalT);
         if(dSig > maxDiff) maxDiff = dSig;
         if(dSig > InpTolerance)
         {
            signalErrors++;
            if(firstErrAt < 0)
            {
               firstErrAt = s;
               firstErrDetail = StringFormat("signal: ind=%.10f truth=%.10f diff=%.2e",
                  signalInd, signalT, dSig);
            }
         }

         // (3) Hist consistency: hist == MACD − Signal
         double expectedHist = macdInd - signalInd;
         double dHist = MathAbs(histInd - expectedHist);
         if(dHist > InpTolerance)
         {
            histErrors++;
            if(firstErrAt < 0)
            {
               firstErrAt = s;
               firstErrDetail = StringFormat("hist: ind=%.10f expected=%.10f diff=%.2e",
                  histInd, expectedHist, dHist);
            }
         }

         // (4) Color index
         double expectedColor = (histInd >= 0.0) ? 0.0 : 1.0;
         if(colorIdx != expectedColor)
         {
            colorErrors++;
            if(firstErrAt < 0)
            {
               firstErrAt = s;
               firstErrDetail = StringFormat("color: idx=%.0f expected=%.0f (hist=%.4f)",
                  colorIdx, expectedColor, histInd);
            }
         }
      }
   }

   int totalErrors = macdErrors + signalErrors + histErrors + colorErrors;
   if(totalErrors == 0)
   {
      PrintFormat("OK: %d bars verificadas, zero divergencia (macd/signal/hist/color). "
                  "fast=%d slow=%d signal=%d tol=%.0e diff_max=%.2e",
                  bars, InpFastPeriod, InpSlowPeriod, InpSignalPeriod,
                  InpTolerance, maxDiff);
   }
   else
   {
      PrintFormat("FAIL: macd=%d signal=%d hist=%d color=%d (tol=%.0e diff_max=%.2e). "
                  "Primeira em shift=%d: %s",
                  macdErrors, signalErrors, histErrors, colorErrors,
                  InpTolerance, maxDiff, firstErrAt, firstErrDetail);
   }

   IndicatorRelease(handle);
   IndicatorRelease(truthHandle);
}
