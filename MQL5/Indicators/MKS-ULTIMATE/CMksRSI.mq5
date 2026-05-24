//+------------------------------------------------------------------+
//| @file           : CMksRSI.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Indicators / MKS-ULTIMATE
//| @responsibility : RSI brick-driven sobre o Custom Symbol — em
//|                   janela separada, eixo Y travado 0-100. Linha
//|                   colorida por zona: InpColorBull quando RSI >= 50,
//|                   InpColorBear quando RSI < 50. Níveis OB/OS
//|                   horizontais via INDICATOR_LEVELS.
//|
//|                   Algoritmo: Wilder's smoothing — idêntico ao
//|                   iRSI do MT5 (verificado pelo Test_*).
//|                     seedAvgGain = sum(gains[1..N]) / N
//|                     seedAvgLoss = sum(losses[1..N]) / N
//|                     avgGain[i]  = (avgGain[i-1] * (N-1) + gain[i]) / N
//|                     avgLoss[i]  = analogamente
//|                     RS = avgGain / avgLoss
//|                     RSI = 100 − 100 / (1 + RS)
//|
//|                   Interpretação em Renko: cada "gain" é o avanço
//|                   de preço entre 2 bricks fechados. Em sequência
//|                   pura de bricks bull o RSI dispara pra 100;
//|                   alternância equilibrada gira em torno de 50.
//|                   RSI em Renko ≈ "viés direcional dos últimos N
//|                   bricks" — mais limpo que em time bars porque o
//|                   Renko já filtrou ruído.
//| @depends_on     : (nenhuma dependência do core — API MT5 apenas)
//| @install_path   : MQL5/Indicators/MKS-ULTIMATE/CMksRSI.mq5
//+------------------------------------------------------------------+
#property strict
#property indicator_separate_window
#property indicator_minimum 0.0
#property indicator_maximum 100.0
#property indicator_buffers 4
#property indicator_plots   1

#property indicator_label1  "RSI"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLime, clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// === Cálculo ===
input int                InpPeriod        = 14;            // Período do RSI (em bricks)
input ENUM_APPLIED_PRICE InpAppliedPrice  = PRICE_CLOSE;   // Preço aplicado
input double             InpLevelOB       = 70.0;          // Nível overbought
input double             InpLevelOS       = 30.0;          // Nível oversold

// === Visual ===
input color              InpColorBull = clrLime;          // Cor da linha quando RSI >= 50
input color              InpColorBear = clrRed;           // Cor da linha quando RSI < 50
input int                InpLineWidth = 2;                // Grossura (1..5)
input ENUM_LINE_STYLE    InpLineStyle = STYLE_SOLID;      // Estilo

double RsiBuffer[];        // visível — valor do RSI
double ColorBuffer[];      // visível — índice de cor (0 = bull, 1 = bear)
double AvgGainBuffer[];    // hidden — Wilder avg gain
double AvgLossBuffer[];    // hidden — Wilder avg loss

int OnInit()
{
   if(InpPeriod < 2)
   {
      Print("CMksRSI: InpPeriod deve ser >= 2");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLevelOB <= InpLevelOS)
   {
      Print("CMksRSI: InpLevelOB deve ser > InpLevelOS");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLevelOB > 100.0 || InpLevelOS < 0.0)
   {
      Print("CMksRSI: niveis devem estar em [0..100]");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLineWidth < 1 || InpLineWidth > 5)
   {
      Print("CMksRSI: InpLineWidth deve estar em [1..5]");
      return INIT_PARAMETERS_INCORRECT;
   }

   SetIndexBuffer(0, RsiBuffer,     INDICATOR_DATA);
   SetIndexBuffer(1, ColorBuffer,   INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2, AvgGainBuffer, INDICATOR_CALCULATIONS);
   SetIndexBuffer(3, AvgLossBuffer, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_DRAW_TYPE,     DRAW_COLOR_LINE);
   PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 2);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, InpColorBull);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, InpColorBear);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpLineWidth);
   PlotIndexSetInteger(0, PLOT_LINE_STYLE, InpLineStyle);
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetInteger(INDICATOR_LEVELS,        2);
   IndicatorSetDouble (INDICATOR_LEVELVALUE, 0, InpLevelOB);
   IndicatorSetDouble (INDICATOR_LEVELVALUE, 1, InpLevelOS);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrDimGray);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 1, clrDimGray);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 1, STYLE_DOT);

   string shortName = StringFormat("MKS RSI(%d,%s)",
      InpPeriod, EnumToString(InpAppliedPrice));
   IndicatorSetString (INDICATOR_SHORTNAME, shortName);
   IndicatorSetInteger(INDICATOR_DIGITS, 2);

   return INIT_SUCCEEDED;
}

double Price(const double &op[], const double &hi[], const double &lo[],
             const double &cl[], int idx)
{
   switch(InpAppliedPrice)
   {
      case PRICE_OPEN:     return op[idx];
      case PRICE_HIGH:     return hi[idx];
      case PRICE_LOW:      return lo[idx];
      case PRICE_MEDIAN:   return (hi[idx] + lo[idx]) * 0.5;
      case PRICE_TYPICAL:  return (hi[idx] + lo[idx] + cl[idx]) / 3.0;
      case PRICE_WEIGHTED: return (hi[idx] + lo[idx] + 2.0 * cl[idx]) * 0.25;
      case PRICE_CLOSE:
      default:             return cl[idx];
   }
}

double ComputeRsi(double avgGain, double avgLoss)
{
   if(avgLoss == 0.0) return 100.0;
   double rs = avgGain / avgLoss;
   return 100.0 - 100.0 / (1.0 + rs);
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
   if(rates_total < InpPeriod + 1)
      return 0;

   int start;
   if(prev_calculated <= 0)
   {
      // Limpa bars sem RSI válido.
      for(int k = 0; k < InpPeriod; k++)
      {
         RsiBuffer[k]     = EMPTY_VALUE;
         ColorBuffer[k]   = 0.0;
         AvgGainBuffer[k] = 0.0;
         AvgLossBuffer[k] = 0.0;
      }

      // Seed Wilder no bar `InpPeriod`.
      double sumGain = 0.0, sumLoss = 0.0;
      for(int k = 1; k <= InpPeriod; k++)
      {
         double delta = Price(open, high, low, close, k) - Price(open, high, low, close, k - 1);
         if(delta > 0.0) sumGain += delta;
         else            sumLoss -= delta;
      }
      AvgGainBuffer[InpPeriod] = sumGain / InpPeriod;
      AvgLossBuffer[InpPeriod] = sumLoss / InpPeriod;
      double rsiSeed = ComputeRsi(AvgGainBuffer[InpPeriod], AvgLossBuffer[InpPeriod]);
      RsiBuffer[InpPeriod]   = rsiSeed;
      ColorBuffer[InpPeriod] = (rsiSeed >= 50.0) ? 0.0 : 1.0;

      start = InpPeriod + 1;
   }
   else
   {
      start = MathMax(prev_calculated - 1, InpPeriod + 1);
   }

   // Forma canônica de Wilder — uma única divisão por iteração,
   // bate com a ordem de operações do iRSI nativo (FP-stable).
   double periodD = (double)InpPeriod;
   double prevN   = (double)(InpPeriod - 1);

   for(int i = start; i < rates_total; i++)
   {
      double delta = Price(open, high, low, close, i) - Price(open, high, low, close, i - 1);
      double gain  = (delta > 0.0) ?  delta : 0.0;
      double loss  = (delta < 0.0) ? -delta : 0.0;

      AvgGainBuffer[i] = (AvgGainBuffer[i - 1] * prevN + gain) / periodD;
      AvgLossBuffer[i] = (AvgLossBuffer[i - 1] * prevN + loss) / periodD;

      double rsi = ComputeRsi(AvgGainBuffer[i], AvgLossBuffer[i]);
      RsiBuffer[i]   = rsi;
      ColorBuffer[i] = (rsi >= 50.0) ? 0.0 : 1.0;
   }
   return rates_total;
}
