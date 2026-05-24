//+------------------------------------------------------------------+
//| @file           : CMksChandelier.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Indicators / MKS-ULTIMATE
//| @responsibility : Chandelier Exit brick-driven sobre o Custom
//|                   Symbol — sem ATR. Estilo flipping: a cada bar
//|                   apenas UMA linha aparece — bull (long stop)
//|                   enquanto a tendência é de alta, bear (short
//|                   stop) quando é de baixa.
//|
//|                   Fórmulas brick-native:
//|                     offset         = InpOffsetBricks × brickSize
//|                     candidateLong  = HighestHigh(N) − offset
//|                     candidateShort = LowestLow(N)   + offset
//|                   Stop ativo trava (ratchet): em bull só sobe;
//|                   em bear só desce. Flip quando close cruza.
//|
//|                   brickSize em pontos é auto-inferido de
//|                   |close[1]−open[1]| do próprio CS (Producer
//|                   força essa igualdade quando brickSizePts>0,
//|                   ADR-022 §8). Override manual via input.
//| @depends_on     : (nenhuma dependência do core — API MT5 apenas)
//| @install_path   : MQL5/Indicators/MKS-ULTIMATE/CMksChandelier.mq5
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   2

#property indicator_label1  "Chandelier Bull"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "Chandelier Bear"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

// === Cálculo ===
input int    InpPeriod         = 22;    // Período do canal (high/low de N bricks)
input double InpOffsetBricks   = 3.0;   // Afastamento do extremo (em múltiplos de brickSize)
input double InpBrickSizePts   = 0.0;   // Tamanho do brick em pontos (0 = auto-inferir do CS)
input bool   InpExcludeForming = true;  // Exclui bar atual (Turtle: usa N bars ANTES)
input int    InpShift          = 0;     // Deslocamento (bars a deslocar a janela)

// === Visual ===
input color           InpColorBull  = clrLime;     // Cor da linha bull (long stop)
input color           InpColorBear  = clrRed;      // Cor da linha bear (short stop)
input int             InpLineWidth  = 1;           // Grossura da linha (1..5)
input ENUM_LINE_STYLE InpLineStyle  = STYLE_SOLID; // Tipo de linha

double BullBuffer[];        // visível — só preenche quando trend == +1
double BearBuffer[];        // visível — só preenche quando trend == -1
double TrendBuffer[];       // hidden — +1 = bull, −1 = bear
double ActiveStopBuffer[];  // hidden — stop ativo atual, independente de direção

double g_brickSizePrice = 0.0;  // brickSize em unidades de preço (após resolução)

int OnInit()
{
   if(InpPeriod < 1)
   {
      Print("CMksChandelier: InpPeriod deve ser >= 1");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpOffsetBricks <= 0.0)
   {
      Print("CMksChandelier: InpOffsetBricks deve ser > 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpShift < 0)
   {
      Print("CMksChandelier: InpShift deve ser >= 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLineWidth < 1 || InpLineWidth > 5)
   {
      Print("CMksChandelier: InpLineWidth deve estar em [1..5]");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Se brickSize foi fornecido manualmente, resolve já. Caso contrário,
   // resolve no primeiro OnCalculate com bars suficientes.
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

   string shortName = StringFormat("MKS Chandelier(%d,%.1fb%s%s)",
      InpPeriod, InpOffsetBricks,
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
   int minBars = InpPeriod + InpShift + (InpExcludeForming ? 1 : 0);
   if(rates_total < minBars)
      return 0;

   // Resolve brickSize por auto-inferência se ainda não foi setado.
   // Premissa: ADR-022 §8 — Producer escreve bar com |close-open| =
   // brickSizePts × _Point, constante em todas as bars fechadas.
   if(g_brickSizePrice <= 0.0)
   {
      // Pega bar fechada mais recente (idx rates_total-2 em non-series).
      int probe = rates_total - 2;
      if(probe < 0) return 0;
      double sz = MathAbs(close[probe] - open[probe]);
      if(sz <= 0.0)
      {
         Print("CMksChandelier: auto-infer de brickSize falhou (|close-open|=0). "
               "Defina InpBrickSizePts manualmente.");
         return 0;
      }
      g_brickSizePrice = sz;
   }

   double offsetPrice = InpOffsetBricks * g_brickSizePrice;

   int start;
   if(prev_calculated <= 0)
      start = minBars - 1;
   else
      start = MathMax(prev_calculated - 1, minBars - 1);

   for(int i = start; i < rates_total; i++)
   {
      int winEnd, winStart;
      if(InpExcludeForming)
      {
         winEnd   = i - 1 - InpShift;
         winStart = i - InpPeriod - InpShift;
      }
      else
      {
         winEnd   = i - InpShift;
         winStart = i - InpPeriod + 1 - InpShift;
      }

      if(winStart < 0)
      {
         BullBuffer[i]       = EMPTY_VALUE;
         BearBuffer[i]       = EMPTY_VALUE;
         TrendBuffer[i]      = 0.0;
         ActiveStopBuffer[i] = 0.0;
         continue;
      }

      double hh = high[winStart];
      double ll = low[winStart];
      for(int k = winStart + 1; k <= winEnd; k++)
      {
         if(high[k] > hh) hh = high[k];
         if(low[k]  < ll) ll = low[k];
      }

      double candidateLong  = hh - offsetPrice;
      double candidateShort = ll + offsetPrice;

      // Determina trend novo e stop ativo. Bar inicial (sem prev): decide
      // pela posição do close em relação ao midpoint (hh+ll)/2.
      double trendNew;
      double stopNew;
      bool isFirst = (i == minBars - 1) || (TrendBuffer[i - 1] == 0.0);
      if(isFirst)
      {
         double midpoint = (hh + ll) * 0.5;
         if(close[i] >= midpoint)
         {
            trendNew = +1.0;
            stopNew  = candidateLong;
         }
         else
         {
            trendNew = -1.0;
            stopNew  = candidateShort;
         }
      }
      else
      {
         double prevTrend = TrendBuffer[i - 1];
         double prevStop  = ActiveStopBuffer[i - 1];

         if(prevTrend > 0.0)  // estava bull
         {
            if(close[i] < prevStop)
            {
               // Flip para bear.
               trendNew = -1.0;
               stopNew  = candidateShort;
            }
            else
            {
               // Continua bull, ratcheta para cima.
               trendNew = +1.0;
               stopNew  = MathMax(candidateLong, prevStop);
            }
         }
         else  // estava bear
         {
            if(close[i] > prevStop)
            {
               // Flip para bull.
               trendNew = +1.0;
               stopNew  = candidateLong;
            }
            else
            {
               // Continua bear, ratcheta para baixo.
               trendNew = -1.0;
               stopNew  = MathMin(candidateShort, prevStop);
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
