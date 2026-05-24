//+------------------------------------------------------------------+
//| @file           : CMksMACD.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Indicators / MKS-ULTIMATE
//| @responsibility : MACD brick-driven sobre o Custom Symbol — em
//|                   janela separada. Implementa a variante do MT5:
//|                   fast/slow EMAs sobre o preço aplicado, signal
//|                   é SMA do MACD (não EMA — preserva paridade com
//|                   iMACD nativo).
//|
//|                   Fórmulas:
//|                     fastEMA[i] = price[i] × k_f + fastEMA[i-1] × (1-k_f)
//|                       k_f = 2 / (fast + 1), seed = SMA do primeiro fast
//|                     slowEMA[i] = idem com slow
//|                     MACD[i]    = fastEMA[i] − slowEMA[i]
//|                     Signal[i]  = SMA(MACD[i-signal+1..i])
//|                     Hist[i]    = MACD[i] − Signal[i]
//|
//|                   Interpretação em Renko: MACD captura a diferença
//|                   entre EMAs de close de brick — quando bricks
//|                   recentes empurram fastEMA acima da slowEMA, MACD
//|                   sobe. Histograma cresce nas acelerações de
//|                   tendência e contrai nas inversões iminentes.
//| @depends_on     : (nenhuma dependência do core — API MT5 apenas)
//| @install_path   : MQL5/Indicators/MKS-ULTIMATE/CMksMACD.mq5
//+------------------------------------------------------------------+
#property strict
#property indicator_separate_window
#property indicator_buffers 6
#property indicator_plots   3

#property indicator_label1  "MACD"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "Signal"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "Histogram"
#property indicator_type3   DRAW_COLOR_HISTOGRAM
#property indicator_color3  clrLime, clrCrimson
#property indicator_style3  STYLE_SOLID
#property indicator_width3  3

// === Cálculo ===
input int                InpFastPeriod    = 12;            // Período da EMA rápida
input int                InpSlowPeriod    = 26;            // Período da EMA lenta
input int                InpSignalPeriod  = 9;             // Período do SMA do signal
input ENUM_APPLIED_PRICE InpAppliedPrice  = PRICE_CLOSE;   // Preço aplicado

// === Visual ===
input color           InpColorMACD   = clrDodgerBlue;   // Cor da linha MACD
input color           InpColorSignal = clrRed;          // Cor da linha Signal
input color           InpColorBull   = clrLime;         // Cor do histograma quando >= 0
input color           InpColorBear   = clrCrimson;      // Cor do histograma quando < 0
input int             InpLineWidth   = 1;               // Grossura das linhas MACD e Signal
input int             InpHistWidth   = 3;               // Largura das barras do histograma
input ENUM_LINE_STYLE InpLineStyle   = STYLE_SOLID;     // Estilo das linhas

double MACDBuffer[];        // visível — MACD line
double SignalBuffer[];      // visível — Signal line
double HistBuffer[];        // visível — Histograma
double HistColorBuffer[];   // visível auxiliar — índice de cor do histograma
double FastEMABuffer[];     // hidden — EMA rápida
double SlowEMABuffer[];     // hidden — EMA lenta

int OnInit()
{
   if(InpFastPeriod < 2)
   {
      Print("CMksMACD: InpFastPeriod deve ser >= 2");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpSlowPeriod <= InpFastPeriod)
   {
      Print("CMksMACD: InpSlowPeriod deve ser > InpFastPeriod");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpSignalPeriod < 1)
   {
      Print("CMksMACD: InpSignalPeriod deve ser >= 1");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLineWidth < 1 || InpLineWidth > 5)
   {
      Print("CMksMACD: InpLineWidth deve estar em [1..5]");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpHistWidth < 1 || InpHistWidth > 5)
   {
      Print("CMksMACD: InpHistWidth deve estar em [1..5]");
      return INIT_PARAMETERS_INCORRECT;
   }

   SetIndexBuffer(0, MACDBuffer,      INDICATOR_DATA);
   SetIndexBuffer(1, SignalBuffer,    INDICATOR_DATA);
   SetIndexBuffer(2, HistBuffer,      INDICATOR_DATA);
   SetIndexBuffer(3, HistColorBuffer, INDICATOR_COLOR_INDEX);
   SetIndexBuffer(4, FastEMABuffer,   INDICATOR_CALCULATIONS);
   SetIndexBuffer(5, SlowEMABuffer,   INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpColorMACD);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpLineWidth);
   PlotIndexSetInteger(0, PLOT_LINE_STYLE, InpLineStyle);
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpColorSignal);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, InpLineWidth);
   PlotIndexSetInteger(1, PLOT_LINE_STYLE, InpLineStyle);
   PlotIndexSetDouble (1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(2, PLOT_DRAW_TYPE,     DRAW_COLOR_HISTOGRAM);
   PlotIndexSetInteger(2, PLOT_COLOR_INDEXES, 2);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, 0, InpColorBull);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, 1, InpColorBear);
   PlotIndexSetInteger(2, PLOT_LINE_WIDTH, InpHistWidth);
   PlotIndexSetDouble (2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Linha zero (referência) na janela.
   IndicatorSetInteger(INDICATOR_LEVELS,        1);
   IndicatorSetDouble (INDICATOR_LEVELVALUE, 0, 0.0);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrDimGray);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);

   string shortName = StringFormat("MKS MACD(%d,%d,%d,%s)",
      InpFastPeriod, InpSlowPeriod, InpSignalPeriod,
      EnumToString(InpAppliedPrice));
   IndicatorSetString (INDICATOR_SHORTNAME, shortName);
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits + 1);

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
   int minBars = InpSlowPeriod + InpSignalPeriod;  // primeira bar com signal completo
   if(rates_total < minBars)
      return 0;

   double kFast = 2.0 / ((double)InpFastPeriod + 1.0);
   double kSlow = 2.0 / ((double)InpSlowPeriod + 1.0);

   int start;
   if(prev_calculated <= 0)
   {
      // Limpa bars sem MACD válido (antes do slow EMA estar pronto).
      for(int k = 0; k < InpSlowPeriod - 1; k++)
      {
         MACDBuffer[k]      = EMPTY_VALUE;
         SignalBuffer[k]    = EMPTY_VALUE;
         HistBuffer[k]      = EMPTY_VALUE;
         HistColorBuffer[k] = 0.0;
         FastEMABuffer[k]   = 0.0;
         SlowEMABuffer[k]   = 0.0;
      }

      // Seed fast EMA em (fast-1) com SMA dos primeiros `fast` preços.
      double sumFast = 0.0;
      for(int k = 0; k < InpFastPeriod; k++)
         sumFast += Price(open, high, low, close, k);
      FastEMABuffer[InpFastPeriod - 1] = sumFast / (double)InpFastPeriod;

      // Recursão fast EMA de fast até slow-1.
      for(int i = InpFastPeriod; i < InpSlowPeriod; i++)
      {
         double p = Price(open, high, low, close, i);
         FastEMABuffer[i] = p * kFast + FastEMABuffer[i - 1] * (1.0 - kFast);
      }

      // Seed slow EMA em (slow-1) com SMA dos primeiros `slow` preços.
      double sumSlow = 0.0;
      for(int k = 0; k < InpSlowPeriod; k++)
         sumSlow += Price(open, high, low, close, k);
      SlowEMABuffer[InpSlowPeriod - 1] = sumSlow / (double)InpSlowPeriod;

      // MACD no slow-1 (primeira bar com ambas EMAs prontas).
      MACDBuffer[InpSlowPeriod - 1] = FastEMABuffer[InpSlowPeriod - 1] - SlowEMABuffer[InpSlowPeriod - 1];
      SignalBuffer[InpSlowPeriod - 1]    = EMPTY_VALUE;
      HistBuffer[InpSlowPeriod - 1]      = EMPTY_VALUE;
      HistColorBuffer[InpSlowPeriod - 1] = 0.0;

      start = InpSlowPeriod;
   }
   else
   {
      start = MathMax(prev_calculated - 1, InpSlowPeriod);
   }

   int firstSignalBar = InpSlowPeriod + InpSignalPeriod - 2;

   for(int i = start; i < rates_total; i++)
   {
      double p = Price(open, high, low, close, i);
      FastEMABuffer[i] = p * kFast + FastEMABuffer[i - 1] * (1.0 - kFast);
      SlowEMABuffer[i] = p * kSlow + SlowEMABuffer[i - 1] * (1.0 - kSlow);
      MACDBuffer[i]    = FastEMABuffer[i] - SlowEMABuffer[i];

      if(i >= firstSignalBar)
      {
         double sumMACD = 0.0;
         for(int k = 0; k < InpSignalPeriod; k++)
            sumMACD += MACDBuffer[i - k];
         SignalBuffer[i]    = sumMACD / (double)InpSignalPeriod;
         HistBuffer[i]      = MACDBuffer[i] - SignalBuffer[i];
         HistColorBuffer[i] = (HistBuffer[i] >= 0.0) ? 0.0 : 1.0;
      }
      else
      {
         SignalBuffer[i]    = EMPTY_VALUE;
         HistBuffer[i]      = EMPTY_VALUE;
         HistColorBuffer[i] = 0.0;
      }
   }
   return rates_total;
}
