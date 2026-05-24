//+------------------------------------------------------------------+
//| @file           : Test_CMksDonchian.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Valida o indicador CMksDonchian comparando seus
//|                   buffers (via iCustom + CopyBuffer) contra um
//|                   cálculo independente que percorre iHigh/iLow do
//|                   chart com MathMax/MathMin. Anexar ao chart onde
//|                   o indicador deve ser auditado (tipicamente o CS
//|                   do MKS-ULTIMATE). Reporta primeira divergência
//|                   ou OK. Tolerância 0.0 por padrão — sem ATR no
//|                   indicador significa zero acúmulo de FP, comparação
//|                   exata é o resultado esperado.
//| @depends_on     : Indicators/MKS-ULTIMATE/CMksDonchian.mq5
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksDonchian.mq5
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input int    InpPeriod         = 20;    // Período (deve bater com o indicador)
input bool   InpExcludeForming = true;  // Modo  (deve bater com o indicador)
input int    InpShift          = 0;     // Shift (deve bater com o indicador)
input int    InpBarsToCheck    = 500;   // Quantas bars verificar (do mais recente)
input double InpTolerance      = 0.0;   // Tolerância de comparação

void OnStart()
{
   ResetLastError();
   int handle = iCustom(_Symbol, _Period,
                        "MKS-ULTIMATE\\CMksDonchian",
                        InpPeriod,
                        InpExcludeForming,
                        InpShift);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("FAIL: iCustom retornou INVALID_HANDLE. err=%d", GetLastError());
      return;
   }

   // Espera o indicador ter calculado os bars necessários (até ~5s).
   int total = Bars(_Symbol, _Period);
   int bars  = MathMin(InpBarsToCheck, total - InpPeriod - InpShift - 2);
   if(bars < 1)
   {
      PrintFormat("FAIL: bars insuficientes (total=%d, period=%d, shift=%d)",
                  total, InpPeriod, InpShift);
      IndicatorRelease(handle);
      return;
   }

   int attempts = 0;
   while(BarsCalculated(handle) < bars && attempts < 50)
   {
      Sleep(100);
      attempts++;
   }
   if(BarsCalculated(handle) < bars)
   {
      PrintFormat("FAIL: indicador nao calculou %d bars em ~5s (calculated=%d)",
                  bars, BarsCalculated(handle));
      IndicatorRelease(handle);
      return;
   }

   double upBuf[], loBuf[];
   ArraySetAsSeries(upBuf, true);
   ArraySetAsSeries(loBuf, true);

   if(CopyBuffer(handle, 0, 0, bars, upBuf) <= 0 ||
      CopyBuffer(handle, 1, 0, bars, loBuf) <= 0)
   {
      PrintFormat("FAIL: CopyBuffer falhou. err=%d", GetLastError());
      IndicatorRelease(handle);
      return;
   }

   int    mismatches  = 0;
   int    firstMis    = -1;
   double firstUpInd  = 0, firstUpTrue = 0;
   double firstLoInd  = 0, firstLoTrue = 0;

   for(int s = 0; s < bars; s++)
   {
      double truthUp, truthLo;
      int    base, count;
      if(InpExcludeForming)
      {
         // Janela "bars-ago": [s+1+InpShift .. s+InpPeriod+InpShift]
         base  = s + 1 + InpShift;
         count = InpPeriod;
      }
      else
      {
         // Janela "bars-ago": [s+InpShift .. s+InpPeriod-1+InpShift]
         base  = s + InpShift;
         count = InpPeriod;
      }
      truthUp = iHigh(_Symbol, _Period, base);
      truthLo = iLow(_Symbol,  _Period, base);
      for(int k = 1; k < count; k++)
      {
         truthUp = MathMax(truthUp, iHigh(_Symbol, _Period, base + k));
         truthLo = MathMin(truthLo, iLow(_Symbol,  _Period, base + k));
      }

      bool upOk = MathAbs(upBuf[s] - truthUp) <= InpTolerance;
      bool loOk = MathAbs(loBuf[s] - truthLo) <= InpTolerance;
      if(!upOk || !loOk)
      {
         if(mismatches == 0)
         {
            firstMis    = s;
            firstUpInd  = upBuf[s];
            firstUpTrue = truthUp;
            firstLoInd  = loBuf[s];
            firstLoTrue = truthLo;
         }
         mismatches++;
      }
   }

   if(mismatches == 0)
   {
      PrintFormat("OK: %d bars verificadas, zero divergencia. period=%d ex=%s shift=%d",
                  bars, InpPeriod, InpExcludeForming ? "true" : "false", InpShift);
   }
   else
   {
      PrintFormat("FAIL: %d divergencias em %d bars. Primeira em shift=%d:",
                  mismatches, bars, firstMis);
      PrintFormat("  Upper: ind=%.*f truth=%.*f", _Digits, firstUpInd, _Digits, firstUpTrue);
      PrintFormat("  Lower: ind=%.*f truth=%.*f", _Digits, firstLoInd, _Digits, firstLoTrue);
   }

   IndicatorRelease(handle);
}
