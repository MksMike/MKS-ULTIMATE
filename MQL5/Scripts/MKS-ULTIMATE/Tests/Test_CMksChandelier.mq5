//+------------------------------------------------------------------+
//| @file           : Test_CMksChandelier.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Valida CMksChandelier (versão sem ATR, flipping
//|                   com ratchet). Lê os 4 buffers (Bull, Bear,
//|                   Trend, ActiveStop) e confere quatro invariantes
//|                   por bar:
//|                     1) Visibilidade: só Bull ou só Bear, conforme trend
//|                     2) Igualdade: active stop == Bull[i] ou Bear[i]
//|                     3) Math: dado trend[i] vs trend[i-1], o active stop
//|                        bate com candidate / ratchet / flip
//|                     4) Flip rule: se trend mudou, close cruzou
//|                        active prévio na direção certa.
//|                   brickSize auto-inferido igual ao indicador.
//| @depends_on     : Indicators/MKS-ULTIMATE/CMksChandelier.mq5
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksChandelier.mq5
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

input int    InpPeriod         = 22;     // Período (deve bater com o indicador)
input double InpOffsetBricks   = 3.0;    // Offset (deve bater com o indicador)
input double InpBrickSizePts   = 0.0;    // BrickSize (deve bater com o indicador, 0 = auto)
input bool   InpExcludeForming = true;
input int    InpShift          = 0;
input int    InpBarsToCheck    = 500;
input double InpTolerance      = 0.0;

void OnStart()
{
   ResetLastError();

   int handle = iCustom(_Symbol, _Period,
                        "MKS-ULTIMATE\\CMksChandelier",
                        InpPeriod,
                        InpOffsetBricks,
                        InpBrickSizePts,
                        InpExcludeForming,
                        InpShift,
                        clrLime, clrRed, 1, STYLE_SOLID);
   if(handle == INVALID_HANDLE)
   {
      PrintFormat("FAIL: iCustom retornou INVALID_HANDLE. err=%d", GetLastError());
      return;
   }

   int total = Bars(_Symbol, _Period);
   int bars  = MathMin(InpBarsToCheck, total - InpPeriod - InpShift - 2);
   if(bars < 2)
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

   double bullBuf[], bearBuf[], trendBuf[], activeBuf[];
   ArraySetAsSeries(bullBuf,   true);
   ArraySetAsSeries(bearBuf,   true);
   ArraySetAsSeries(trendBuf,  true);
   ArraySetAsSeries(activeBuf, true);

   if(CopyBuffer(handle, 0, 0, bars, bullBuf)   <= 0 ||
      CopyBuffer(handle, 1, 0, bars, bearBuf)   <= 0 ||
      CopyBuffer(handle, 2, 0, bars, trendBuf)  <= 0 ||
      CopyBuffer(handle, 3, 0, bars, activeBuf) <= 0)
   {
      PrintFormat("FAIL: CopyBuffer falhou. err=%d", GetLastError());
      IndicatorRelease(handle);
      return;
   }

   // Resolve brickSize igual ao indicador: input se > 0, senão auto.
   double brickSizePrice;
   if(InpBrickSizePts > 0.0)
      brickSizePrice = InpBrickSizePts * _Point;
   else
   {
      // Bar fechada mais recente em coordenada "bars-ago" = 1.
      double sz = MathAbs(iClose(_Symbol, _Period, 1) - iOpen(_Symbol, _Period, 1));
      if(sz <= 0.0)
      {
         Print("FAIL: auto-infer de brickSize falhou (|close-open|=0). Defina InpBrickSizePts.");
         IndicatorRelease(handle);
         return;
      }
      brickSizePrice = sz;
   }
   double offsetPrice = InpOffsetBricks * brickSizePrice;

   int visibilityErrors = 0;
   int equalityErrors   = 0;
   int mathErrors       = 0;
   int flipErrors       = 0;
   int firstErrAt       = -1;
   string firstErrDetail = "";

   for(int s = 0; s < bars - 1; s++)
   {
      double trendNow  = trendBuf[s];
      double trendPrev = trendBuf[s + 1];
      double activeNow = activeBuf[s];
      double activePrv = activeBuf[s + 1];
      double bullNow   = bullBuf[s];
      double bearNow   = bearBuf[s];
      double closeNow  = iClose(_Symbol, _Period, s);

      // (1) Visibilidade
      bool vizOk;
      if(trendNow > 0.0)
         vizOk = (bullNow != EMPTY_VALUE) && (bearNow == EMPTY_VALUE);
      else if(trendNow < 0.0)
         vizOk = (bearNow != EMPTY_VALUE) && (bullNow == EMPTY_VALUE);
      else
         vizOk = (bullNow == EMPTY_VALUE) && (bearNow == EMPTY_VALUE);
      if(!vizOk)
      {
         visibilityErrors++;
         if(firstErrAt < 0)
         {
            firstErrAt = s;
            firstErrDetail = StringFormat("visibility: trend=%.0f bull=%g bear=%g",
               trendNow, bullNow, bearNow);
         }
      }

      // (2) Igualdade activeStop vs linha visível
      bool eqOk = true;
      if(trendNow > 0.0)
         eqOk = (MathAbs(activeNow - bullNow) <= InpTolerance);
      else if(trendNow < 0.0)
         eqOk = (MathAbs(activeNow - bearNow) <= InpTolerance);
      if(!eqOk)
      {
         equalityErrors++;
         if(firstErrAt < 0)
         {
            firstErrAt = s;
            firstErrDetail = StringFormat("equality: active=%.*f line=%.*f trend=%.0f",
               _Digits, activeNow, _Digits, (trendNow > 0 ? bullNow : bearNow), trendNow);
         }
      }

      // (3) Math: reconstrói candidateLong/candidateShort
      int base = InpExcludeForming ? (s + 1 + InpShift) : (s + InpShift);
      double hh = iHigh(_Symbol, _Period, base);
      double ll = iLow(_Symbol,  _Period, base);
      for(int k = 1; k < InpPeriod; k++)
      {
         hh = MathMax(hh, iHigh(_Symbol, _Period, base + k));
         ll = MathMin(ll, iLow(_Symbol,  _Period, base + k));
      }
      double candLong  = hh - offsetPrice;
      double candShort = ll + offsetPrice;

      double expectedStop;
      if(trendPrev == 0.0)
         continue;
      else if(trendNow > 0.0 && trendPrev > 0.0)
         expectedStop = MathMax(candLong, activePrv);
      else if(trendNow < 0.0 && trendPrev < 0.0)
         expectedStop = MathMin(candShort, activePrv);
      else if(trendNow > 0.0 && trendPrev < 0.0)
         expectedStop = candLong;
      else
         expectedStop = candShort;

      if(MathAbs(activeNow - expectedStop) > InpTolerance)
      {
         mathErrors++;
         if(firstErrAt < 0)
         {
            firstErrAt = s;
            firstErrDetail = StringFormat("math: active=%.*f expected=%.*f (trend %.0f→%.0f)",
               _Digits, activeNow, _Digits, expectedStop, trendPrev, trendNow);
         }
      }

      // (4) Flip rule
      if(trendNow != trendPrev)
      {
         bool flipOk;
         if(trendNow < 0.0)
            flipOk = (closeNow < activePrv);
         else
            flipOk = (closeNow > activePrv);
         if(!flipOk)
         {
            flipErrors++;
            if(firstErrAt < 0)
            {
               firstErrAt = s;
               firstErrDetail = StringFormat("flip: close=%.*f vs activePrev=%.*f trend %.0f→%.0f",
                  _Digits, closeNow, _Digits, activePrv, trendPrev, trendNow);
            }
         }
      }
   }

   int totalErrors = visibilityErrors + equalityErrors + mathErrors + flipErrors;
   if(totalErrors == 0)
   {
      PrintFormat("OK: %d bars verificadas, zero divergencia (viz/eq/math/flip). "
                  "period=%d offset=%.2f brickSize(pts)=%.2f",
                  bars - 1, InpPeriod, InpOffsetBricks, brickSizePrice / _Point);
   }
   else
   {
      PrintFormat("FAIL: viz=%d eq=%d math=%d flip=%d. Primeira em shift=%d: %s",
                  visibilityErrors, equalityErrors, mathErrors, flipErrors,
                  firstErrAt, firstErrDetail);
   }

   IndicatorRelease(handle);
}
