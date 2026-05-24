//+------------------------------------------------------------------+
//| @file           : CMksDonchian.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Indicators / MKS-ULTIMATE
//| @responsibility : Canal de Donchian brick-driven sobre o Custom
//|                   Symbol. Upper = máxima de N bricks; Lower =
//|                   mínima de N bricks. Sem ATR — apenas extremos.
//|                   Default Turtle: cada bar usa janela dos N bricks
//|                   ANTES dele (exclui self). Inputs visuais (cor
//|                   alta/baixa, grossura, estilo) configuráveis em
//|                   runtime via PlotIndexSetInteger.
//| @depends_on     : (nenhuma dependência do core — API MT5 apenas)
//| @install_path   : MQL5/Indicators/MKS-ULTIMATE/CMksDonchian.mq5
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "Donchian Upper"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "Donchian Lower"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

// === Cálculo ===
input int  InpPeriod         = 20;    // Período (em bricks)
input bool InpExcludeForming = true;  // Exclui bar atual (Turtle: usa N bars ANTES)
input int  InpShift          = 0;     // Deslocamento (bars a deslocar a janela)

// === Visual ===
input color           InpColorUp    = clrLime;     // Cor da banda superior (alta)
input color           InpColorDown  = clrRed;      // Cor da banda inferior (baixa)
input int             InpLineWidth  = 1;           // Grossura da linha (1..5)
input ENUM_LINE_STYLE InpLineStyle  = STYLE_SOLID; // Tipo de linha

double UpperBuffer[];
double LowerBuffer[];

int OnInit()
{
   if(InpPeriod < 1)
   {
      Print("CMksDonchian: InpPeriod deve ser >= 1");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpShift < 0)
   {
      Print("CMksDonchian: InpShift deve ser >= 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpLineWidth < 1 || InpLineWidth > 5)
   {
      Print("CMksDonchian: InpLineWidth deve estar em [1..5]");
      return INIT_PARAMETERS_INCORRECT;
   }

   SetIndexBuffer(0, UpperBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, LowerBuffer, INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpColorUp);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, InpLineWidth);
   PlotIndexSetInteger(0, PLOT_LINE_STYLE, InpLineStyle);

   PlotIndexSetInteger(1, PLOT_LINE_COLOR, InpColorDown);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, InpLineWidth);
   PlotIndexSetInteger(1, PLOT_LINE_STYLE, InpLineStyle);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   string shortName = StringFormat("MKS Donchian(%d%s%s)",
      InpPeriod,
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
         UpperBuffer[i] = EMPTY_VALUE;
         LowerBuffer[i] = EMPTY_VALUE;
         continue;
      }

      double hi = high[winStart];
      double lo = low[winStart];
      for(int k = winStart + 1; k <= winEnd; k++)
      {
         if(high[k] > hi) hi = high[k];
         if(low[k]  < lo) lo = low[k];
      }
      UpperBuffer[i] = hi;
      LowerBuffer[i] = lo;
   }
   return rates_total;
}
