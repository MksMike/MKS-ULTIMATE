//+------------------------------------------------------------------+
//| @file           : CMksSuperTrend.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Indicators / MKS-ULTIMATE
//| @responsibility : SuperTrend brick-driven sobre o Custom Symbol —
//|                   sem ATR. Estilo flipping: a cada bar apenas UMA
//|                   linha aparece — bull (lower band) enquanto a
//|                   tendência é de alta, bear (upper band) quando é
//|                   de baixa. Mesma arquitetura do CMksChandelier;
//|                   muda só o que ancora a banda.
//|
//|                   Fórmulas brick-native:
//|                     src         = (high + low) / 2 (midpoint)
//|                     offset      = InpOffsetBricks × brickSize
//|                     basicLower  = src − offset
//|                     basicUpper  = src + offset
//|                   Stop ativo trava (ratchet): em bull só sobe;
//|                   em bear só desce. Flip quando close cruza.
//|
//|                   Diferença do Chandelier: aqui a banda é ancorada
//|                   no midpoint da bar fonte (instantâneo). No
//|                   Chandelier é ancorada nos extremos de uma janela
//|                   de N bricks. Sem ATR e com ratchet ambos viram
//|                   stops trailing, mas SuperTrend reage a cada bar
//|                   nova; Chandelier sente menos pulsos isolados.
//|
//|                   brickSize em pontos é auto-inferido de
//|                   |close[1]−open[1]| do próprio CS (ADR-022 §8).
//|                   Override manual via input.
//| @depends_on     : (nenhuma dependência do core — API MT5 apenas)
//| @install_path   : MQL5/Indicators/MKS-ULTIMATE/CMksSuperTrend.mq5
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   2

#property indicator_label1  "SuperTrend Bull"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "SuperTrend Bear"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

// === Cálculo ===
input double InpOffsetBricks   = 3.0;   // Afastamento do midpoint (em múltiplos de brickSize)
input double InpBrickSizePts   = 0.0;   // Tamanho do brick em pontos (0 = auto-inferir do CS)
input bool   InpExcludeForming = true;  // Usa midpoint da bar ANTERIOR (estabilidade)
input int    InpShift          = 0;     // Deslocamento adicional da bar fonte

// === Visual ===
input color           InpColorBull  = clrLime;     // Cor da linha bull (lower band)
input color           InpColorBear  = clrRed;      // Cor da linha bear (upper band)
input int             InpLineWidth  = 1;           // Grossura da linha (1..5)
input ENUM_LINE_STYLE InpLineStyle  = STYLE_SOLID; // Tipo de linha

double BullBuffer[];        // visível — só preenche quando trend == +1
double BearBuffer[];        // visível — só preenche quando trend == -1
double TrendBuffer[];       // hidden — +1 = bull, −1 = bear
double ActiveStopBuffer[];  // hidden — stop ativo atual, independente de direção

double g_brickSizePrice = 0.0;

int OnInit()
{
   if(InpOffsetBricks <= 0.0)
   {
      Print("CMksSuperTrend: InpOffsetBricks deve ser > 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpShift < 0)
   {
      Print("CMksSuperTrend: InpShift deve ser >= 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLineWidth < 1 || InpLineWidth > 5)
   {
      Print("CMksSuperTrend: InpLineWidth deve estar em [1..5]");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpBrickSizePts > 0.0)
      g_brickSizePrice = InpBrickSizePts * _Point;

   SetIndexBuffer(0, BullBuffer,       INDICATOR_DATA);
   SetIndexBuffer(1, BearBuffer,       INDICATOR_DATA);
   SetIndexBuffer(2, TrendBuffer,      INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, ActiveStopBuffer, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpColorBull);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpLineWidth);
   PlotIndexSetInteger(0, PLOT_LINE_STYLE, InpLineStyle);

   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpColorBear);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, InpLineWidth);
   PlotIndexSetInteger(1, PLOT_LINE_STYLE, InpLineStyle);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   string shortName = StringFormat("MKS SuperTrend(%.1fb%s%s)",
      InpOffsetBricks,
      InpExcludeForming ? ",ex" : "",
      InpShift > 0 ? StringFormat(",sh=%d", InpShift) : "");
   IndicatorSetString(INDICATOR_SHORTNAME, shortName);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   int minBars = (InpExcludeForming ? 1 : 0) + InpShift + 1;
   if(rates_total < minBars + 1)  // +1 pra ter prev em [i-1]
      return 0;

   if(g_brickSizePrice <= 0.0)
   {
      int probe = rates_total - 2;
      if(probe < 0) return 0;
      double sz = MathAbs(close[probe] - open[probe]);
      if(sz <= 0.0)
      {
         Print("CMksSuperTrend: auto-infer de brickSize falhou (|close-open|=0). "
               "Defina InpBrickSizePts manualmente.");
         return 0;
      }
      g_brickSizePrice = sz;
   }

   double offsetPrice = InpOffsetBricks * g_brickSizePrice;
   int    srcLag      = (InpExcludeForming ? 1 : 0) + InpShift;

   int start;
   if(prev_calculated <= 0)
   {
      start = minBars;
      // Auditoria 2026-07-22: limpar o warm-up [0..start-1] (buffers novos = 0.0,
      // não EMPTY_VALUE) senão as bandas plotam mergulho até zero. Trend=0.0
      // deixa isFirst=true no 1o bar calculado (i==minBars) — seed intacto.
      for(int j = 0; j < start; j++)
      {
         BullBuffer[j]       = EMPTY_VALUE;
         BearBuffer[j]       = EMPTY_VALUE;
         TrendBuffer[j]      = 0.0;
         ActiveStopBuffer[j] = 0.0;
      }
   }
   else
      start = MathMax(prev_calculated - 1, minBars);

   for(int i = start; i < rates_total; i++)
   {
      int srcIdx = i - srcLag;
      if(srcIdx < 0)
      {
         BullBuffer[i]       = EMPTY_VALUE;
         BearBuffer[i]       = EMPTY_VALUE;
         TrendBuffer[i]      = 0.0;
         ActiveStopBuffer[i] = 0.0;
         continue;
      }

      double src        = (high[srcIdx] + low[srcIdx]) * 0.5;
      double basicLower = src - offsetPrice;
      double basicUpper = src + offsetPrice;

      double trendNew;
      double stopNew;
      bool isFirst = (i == minBars) || (TrendBuffer[i - 1] == 0.0);
      if(isFirst)
      {
         if(close[i] >= src)
         {
            trendNew = +1.0;
            stopNew  = basicLower;
         }
         else
         {
            trendNew = -1.0;
            stopNew  = basicUpper;
         }
      }
      else
      {
         double prevTrend = TrendBuffer[i - 1];
         double prevStop  = ActiveStopBuffer[i - 1];

         if(prevTrend > 0.0)  // estava bull → linha = lowerBand
         {
            if(close[i] < prevStop)
            {
               // Flip para bear.
               trendNew = -1.0;
               stopNew  = basicUpper;
            }
            else
            {
               trendNew = +1.0;
               stopNew  = MathMax(basicLower, prevStop);  // ratchet up
            }
         }
         else  // estava bear → linha = upperBand
         {
            if(close[i] > prevStop)
            {
               // Flip para bull.
               trendNew = +1.0;
               stopNew  = basicLower;
            }
            else
            {
               trendNew = -1.0;
               stopNew  = MathMin(basicUpper, prevStop);  // ratchet down
            }
         }
      }

      TrendBuffer[i]      = trendNew;
      ActiveStopBuffer[i] = stopNew;
      if(trendNew > 0.0)
      {
         BullBuffer[i] = stopNew;
         BearBuffer[i] = EMPTY_VALUE;
      }
      else
      {
         BullBuffer[i] = EMPTY_VALUE;
         BearBuffer[i] = stopNew;
      }
   }
   return rates_total;
}
