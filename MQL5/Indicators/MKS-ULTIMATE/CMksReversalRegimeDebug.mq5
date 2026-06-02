//+------------------------------------------------------------------+
//| @file           : CMksReversalRegimeDebug.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Indicators / MKS-ULTIMATE
//| @responsibility : Indicador de DEBUG VISUAL do CMksReversalRegime
//|                   (Slice 2 do Caixote, ADR-025). Plota o score
//|                   [0..1] por bar numa janela separada, com linha
//|                   horizontal no threshold. Cor da linha indica
//|                   regime: bull quando score >= threshold (lateral
//|                   confirmada), bear caso contrário (trend ou mix).
//|
//|                   Não é indicador de produção — serve só para
//|                   validar visualmente que o detector acerta em
//|                   períodos lateral/trend conhecidos. Será removido
//|                   ou substituído quando o Caixote final entrar.
//| @depends_on     : Core/Sensors/Regime/CMksReversalRegime.mqh
//| @install_path   : MQL5/Indicators/MKS-ULTIMATE/CMksReversalRegimeDebug.mq5
//+------------------------------------------------------------------+
#property strict
#property indicator_separate_window
#property indicator_minimum 0.0
#property indicator_maximum 1.0
#property indicator_buffers 2
#property indicator_plots   1

#property indicator_label1  "Regime Score"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  clrLime, clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#include <MKS-ULTIMATE/Core/Sensors/Regime/CMksReversalRegime.mqh>

// === Cálculo ===
input int    InpPeriod    = 20;    // Janela em bricks
input double InpThreshold = 0.6;   // Score >= threshold = lateral

// === Visual ===
input color           InpColorBull = clrLime;     // Cor quando score >= threshold (lateral)
input color           InpColorBear = clrRed;      // Cor quando score < threshold (trend/mix)
input int             InpLineWidth = 2;           // Grossura (1..5)
input ENUM_LINE_STYLE InpLineStyle = STYLE_SOLID; // Estilo

double ScoreBuffer[];
double ColorBuffer[];

CMksReversalRegime g_regime;

int OnInit()
{
   if(InpPeriod < 2)
   {
      Print("CMksReversalRegimeDebug: InpPeriod deve ser >= 2");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpThreshold < 0.0 || InpThreshold > 1.0)
   {
      Print("CMksReversalRegimeDebug: InpThreshold deve estar em [0..1]");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLineWidth < 1 || InpLineWidth > 5)
   {
      Print("CMksReversalRegimeDebug: InpLineWidth deve estar em [1..5]");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_regime.Configure(InpPeriod, InpThreshold);

   SetIndexBuffer(0, ScoreBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, ColorBuffer, INDICATOR_COLOR_INDEX);

   PlotIndexSetInteger(0, PLOT_DRAW_TYPE,     DRAW_COLOR_LINE);
   PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 2);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, InpColorBull);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, InpColorBear);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpLineWidth);
   PlotIndexSetInteger(0, PLOT_LINE_STYLE, InpLineStyle);
   PlotIndexSetDouble (0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetInteger(INDICATOR_LEVELS,        1);
   IndicatorSetDouble (INDICATOR_LEVELVALUE, 0, InpThreshold);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrDimGray);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DOT);

   string shortName = StringFormat("MKS RegimeDebug(%d,%.2f)", InpPeriod, InpThreshold);
   IndicatorSetString (INDICATOR_SHORTNAME, shortName);
   IndicatorSetInteger(INDICATOR_DIGITS, 3);

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
   int minBars = InpPeriod;
   if(rates_total < minBars)
      return 0;

   int start;
   if(prev_calculated <= 0)
   {
      for(int k = 0; k < minBars - 1; k++)
      {
         ScoreBuffer[k] = EMPTY_VALUE;
         ColorBuffer[k] = 0.0;
      }
      start = minBars - 1;
   }
   else
   {
      start = MathMax(prev_calculated - 1, minBars - 1);
   }

   for(int i = start; i < rates_total; i++)
   {
      double score = g_regime.Compute(open, close, i);
      ScoreBuffer[i] = score;
      ColorBuffer[i] = g_regime.IsLateral(score) ? 0.0 : 1.0;
   }
   return rates_total;
}