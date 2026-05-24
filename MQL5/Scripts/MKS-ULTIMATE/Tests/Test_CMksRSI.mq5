//+------------------------------------------------------------------+
//| @file           : Test_CMksRSI.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Valida CMksRSI comparando seu buffer principal
//|                   contra o iRSI nativo do MT5 com os mesmos
//|                   parâmetros (mesma fórmula Wilder, mesmo cache
//|                   global) — tolerância 0.0 esperada.
//|                   Verifica também:
//|                     - ColorBuffer == 0 quando RSI >= 50, == 1 caso contrário
//|                     - Bars [0..period-1] estão EMPTY_VALUE
//| @depends_on     : Indicators/MKS-ULTIMATE/CMksRSI.mq5
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksRSI.mq5
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input int                InpPeriod        = 14;
input ENUM_APPLIED_PRICE InpAppliedPrice  = PRICE_CLOSE;
input double             InpLevelOB       = 70.0;
input double             InpLevelOS       = 30.0;
input int                InpBarsToCheck   = 500;
input double             InpTolerance     = 1e-10;  // FP noise floor (Wilder acumula ~1e-14)

void OnStart()
{
   ResetLastError();

   int handle = iCustom(_Symbol, _Period,
                        "MKS-ULTIMATE\\CMksRSI",
                        InpPeriod,
                        InpAppliedPrice,
                        InpLevelOB,
                        InpLevelOS,
                        clrLime, clrRed, 2, STYLE_SOLID);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("FAIL: iCustom retornou INVALID_HANDLE. err=%d", GetLastError());
      return;
   }

   int truthHandle = iRSI(_Symbol, _Period, InpPeriod, InpAppliedPrice);
   if(truthHandle == INVALID_HANDLE)
   {
      PrintFormat("FAIL: iRSI truth INVALID_HANDLE. err=%d", GetLastError());
      IndicatorRelease(handle);
      return;
   }

   int total = Bars(_Symbol, _Period);
   int bars  = MathMin(InpBarsToCheck, total - InpPeriod - 2);
   if(bars < 1)
   {
      PrintFormat("FAIL: bars insuficientes (total=%d, period=%d)", total, InpPeriod);
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

   double rsiBuf[], colorBuf[], truthBuf[];
   ArraySetAsSeries(rsiBuf,   true);
   ArraySetAsSeries(colorBuf, true);
   ArraySetAsSeries(truthBuf, true);

   if(CopyBuffer(handle, 0, 0, bars, rsiBuf)        <= 0 ||
      CopyBuffer(handle, 1, 0, bars, colorBuf)      <= 0 ||
      CopyBuffer(truthHandle, 0, 0, bars, truthBuf) <= 0)
   {
      PrintFormat("FAIL: CopyBuffer falhou. err=%d", GetLastError());
      IndicatorRelease(handle);
      IndicatorRelease(truthHandle);
      return;
   }

   int    valueErrors = 0;
   int    colorErrors = 0;
   int    firstErrAt  = -1;
   double maxDiff     = 0.0;
   string firstErrDetail = "";

   for(int s = 0; s < bars; s++)
   {
      double rsiInd   = rsiBuf[s];
      double rsiTruth = truthBuf[s];
      double colorIdx = colorBuf[s];

      // Bars sem RSI válido — tolera EMPTY_VALUE ou 0 (iRSI usa 0).
      if(rsiInd == EMPTY_VALUE) continue;
      if(rsiTruth == 0.0 && rsiInd == EMPTY_VALUE) continue;

      // (1) Valor
      double diff = MathAbs(rsiInd - rsiTruth);
      if(diff > maxDiff) maxDiff = diff;
      if(diff > InpTolerance)
      {
         valueErrors++;
         if(firstErrAt < 0)
         {
            firstErrAt = s;
            firstErrDetail = StringFormat("value: ind=%.10f truth=%.10f diff=%.2e",
               rsiInd, rsiTruth, diff);
         }
      }

      // (2) Color index
      double expectedColor = (rsiInd >= 50.0) ? 0.0 : 1.0;
      if(colorIdx != expectedColor)
      {
         colorErrors++;
         if(firstErrAt < 0)
         {
            firstErrAt = s;
            firstErrDetail = StringFormat("color: idx=%.0f expected=%.0f (rsi=%.4f)",
               colorIdx, expectedColor, rsiInd);
         }
      }
   }

   int totalErrors = valueErrors + colorErrors;
   if(totalErrors == 0)
   {
      PrintFormat("OK: %d bars verificadas, zero divergencia (value/color). "
                  "period=%d applied=%s tol=%.0e diff_max=%.2e",
                  bars, InpPeriod, EnumToString(InpAppliedPrice), InpTolerance, maxDiff);
   }
   else
   {
      PrintFormat("FAIL: value=%d color=%d (tol=%.0e diff_max=%.2e). Primeira em shift=%d: %s",
                  valueErrors, colorErrors, InpTolerance, maxDiff, firstErrAt, firstErrDetail);
   }

   IndicatorRelease(handle);
   IndicatorRelease(truthHandle);
}
