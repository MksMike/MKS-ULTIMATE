//+------------------------------------------------------------------+
//| @file           : CMksChartPainter.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Output
//| @responsibility : Camada de visualização por chart objects (ADR-028).
//|                   Implementa ITradeVisualizer: setas de entrada/saída
//|                   + linha conectora colorida por P&L. Opcionalmente
//|                   desenha retângulos de brick (tester, sem CS).
//|                   Dois modos de view (feedback empírico 2026-05-27):
//|                     OVERLAY: caixas renko sobre os candles M1.
//|                     CLEAN  : candles escondidos (cor=fundo + redraw),
//|                              só as caixas renko.
//|                   Ambos no TEMPO REAL — caixas alinham com a janela
//|                   visível do tester. (Largura-igual verdadeira só no
//|                   CS do live, que é símbolo renko próprio; num chart
//|                   de tempo real do tester remapear tempo joga as
//|                   caixas pra fora da tela — ver nota ADR-028.)
//|                   PURO OUTPUT — nunca lê chart/CS, nunca alimenta
//|                   decisão. No-op em backtest não-visual.
//|                   CMksBrickPainterSink: adaptador IRenkoSink → painter.
//| @depends_on     : Core/Interfaces/ITradeVisualizer.mqh,
//|                   Core/Interfaces/IRenkoSink.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/OrderRequest.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Output/CMksChartPainter.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_OUTPUT_CMKSCHARTPAINTER_MQH
#define MKS_ULTIMATE_CORE_OUTPUT_CMKSCHARTPAINTER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/ITradeVisualizer.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>

// Modo de desenho dos bricks no chart (tester). No live os bricks vêm do
// Custom Symbol nativo — este modo não se aplica.
enum ENUM_MKS_RENKO_VIEW
{
   MKS_RENKO_VIEW_OVERLAY = 0,  // caixas renko sobre os candles M1
   MKS_RENKO_VIEW_CLEAN   = 1   // candles escondidos, só as caixas renko
};

// Desenha marcadores de trade (e opcionalmente bricks) como chart objects,
// ancorados no TEMPO REAL (closeTimeMsc/1000) — alinha com a janela
// visível do chart. Marcadores idem. No live (sem desenho de bricks), o
// MT5 encaixa o marcador na barra do CS via timeline híbrida (ADR-023).
class CMksChartPainter : public ITradeVisualizer
{
private:
   long   m_chartId;
   string m_prefix;
   int    m_digits;
   bool   m_enabled;          // false em backtest não-visual
   bool   m_drawBricks;       // true no tester (sem CS); false no live
   ENUM_MKS_RENKO_VIEW m_viewMode;

   color  m_colorBuy;
   color  m_colorSell;
   color  m_colorProfit;
   color  m_colorLoss;
   color  m_colorBrickBull;
   color  m_colorBrickBear;

   long   m_brickCount;

   // x-span do retângulo = brick anterior → atual (tempo real).
   datetime m_lastBrickTime;
   bool     m_hasLastBrick;
   bool     m_candlesHidden;

   // Rastreio de entradas por positionId (arrays paralelos — MQL5 sem map).
   ulong              m_entId[];
   datetime           m_entTime[];     // tempo real da entrada (p/ linha conectora)
   double             m_entPrice[];
   ENUM_MKS_ORDER_SIDE m_entSide[];

   int FindEntry(ulong positionId) const
   {
      int n = ArraySize(m_entId);
      for(int i = 0; i < n; i++)
         if(m_entId[i] == positionId) return i;
      return -1;
   }

   void HideCandlesOnce()
   {
      if(m_candlesHidden) return;
      color bg = (color)ChartGetInteger(m_chartId, CHART_COLOR_BACKGROUND);
      ChartSetInteger(m_chartId, CHART_COLOR_CHART_UP,    bg);
      ChartSetInteger(m_chartId, CHART_COLOR_CHART_DOWN,  bg);
      ChartSetInteger(m_chartId, CHART_COLOR_CANDLE_BULL, bg);
      ChartSetInteger(m_chartId, CHART_COLOR_CANDLE_BEAR, bg);
      ChartSetInteger(m_chartId, CHART_COLOR_CHART_LINE,  bg);
      ChartRedraw(m_chartId);   // sem redraw a mudança de cor não aparece no tester
      m_candlesHidden = true;
   }

   void RecordEntry(ulong positionId, datetime t, double price, ENUM_MKS_ORDER_SIDE side)
   {
      int idx = FindEntry(positionId);
      if(idx < 0)
      {
         idx = ArraySize(m_entId);
         ArrayResize(m_entId,    idx + 1);
         ArrayResize(m_entTime,  idx + 1);
         ArrayResize(m_entPrice, idx + 1);
         ArrayResize(m_entSide,  idx + 1);
      }
      m_entId[idx]    = positionId;
      m_entTime[idx]  = t;
      m_entPrice[idx] = price;
      m_entSide[idx]  = side;
   }

   void RemoveEntry(int idx)
   {
      int last = ArraySize(m_entId) - 1;
      if(idx < 0 || last < 0) return;
      m_entId[idx]    = m_entId[last];
      m_entTime[idx]  = m_entTime[last];
      m_entPrice[idx] = m_entPrice[last];
      m_entSide[idx]  = m_entSide[last];
      ArrayResize(m_entId,    last);
      ArrayResize(m_entTime,  last);
      ArrayResize(m_entPrice, last);
      ArrayResize(m_entSide,  last);
   }

   void CreateArrow(const string name, datetime t, double price, int arrowCode, color clr)
   {
      if(!m_enabled) return;
      if(ObjectCreate(m_chartId, name, OBJ_ARROW, 0, t, price))
      {
         ObjectSetInteger(m_chartId, name, OBJPROP_ARROWCODE, arrowCode);
         ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(m_chartId, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
         ObjectSetInteger(m_chartId, name, OBJPROP_BACK, false);
         ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
      }
   }

public:
   // chartId: chart-alvo. digits: casas decimais. drawBricks: desenhar
   // retângulos (tester=true, live=false). enabled: false desliga todo
   // desenho (backtest não-visual). viewMode: OVERLAY ou CLEAN.
   CMksChartPainter(long chartId, int digits, bool drawBricks, bool enabled,
                    ENUM_MKS_RENKO_VIEW viewMode = MKS_RENKO_VIEW_OVERLAY)
   {
      m_chartId      = chartId;
      m_prefix       = "MKSCR_VIZ_";
      m_digits       = digits;
      m_drawBricks   = drawBricks;
      m_enabled      = enabled;
      m_viewMode     = viewMode;

      m_colorBuy       = clrDodgerBlue;
      m_colorSell      = clrOrangeRed;
      m_colorProfit    = clrLimeGreen;
      m_colorLoss      = clrCrimson;
      m_colorBrickBull = clrSeaGreen;
      m_colorBrickBear = clrIndianRed;

      m_brickCount    = 0;
      m_lastBrickTime = 0;
      m_hasLastBrick  = false;
      m_candlesHidden = false;
      ArrayResize(m_entId, 0);
      ArrayResize(m_entTime, 0);
      ArrayResize(m_entPrice, 0);
      ArrayResize(m_entSide, 0);
   }

   //--- ITradeVisualizer overrides ---------------------------------+

   virtual void MarkEntry(long timeMsc, ENUM_MKS_ORDER_SIDE side,
                          double price, ulong positionId) override
   {
      datetime t = (datetime)(timeMsc / 1000);
      RecordEntry(positionId, t, price, side); // registra mesmo se !enabled
      if(!m_enabled) return;
      int    code = (side == MKS_ORDER_BUY) ? 233 : 234; // 233 up, 234 down
      color  clr  = (side == MKS_ORDER_BUY) ? m_colorBuy : m_colorSell;
      string name = m_prefix + "E_" + (string)positionId;
      CreateArrow(name, t, price, code, clr);
   }

   virtual void MarkExit(long timeMsc, double price, ulong positionId) override
   {
      int idx = FindEntry(positionId);
      datetime t = (datetime)(timeMsc / 1000);

      if(m_enabled)
      {
         color exitClr = clrSilver;
         if(idx >= 0)
         {
            bool profit = (m_entSide[idx] == MKS_ORDER_BUY)
                          ? (price > m_entPrice[idx])
                          : (price < m_entPrice[idx]);
            exitClr = profit ? m_colorProfit : m_colorLoss;

            string cname = m_prefix + "C_" + (string)positionId;
            if(ObjectCreate(m_chartId, cname, OBJ_TREND, 0,
                            m_entTime[idx], m_entPrice[idx], t, price))
            {
               ObjectSetInteger(m_chartId, cname, OBJPROP_COLOR, exitClr);
               ObjectSetInteger(m_chartId, cname, OBJPROP_WIDTH, 1);
               ObjectSetInteger(m_chartId, cname, OBJPROP_RAY_RIGHT, false);
               ObjectSetInteger(m_chartId, cname, OBJPROP_BACK, true);
               ObjectSetInteger(m_chartId, cname, OBJPROP_SELECTABLE, false);
            }
         }
         string name = m_prefix + "X_" + (string)positionId;
         CreateArrow(name, t, price, 251, exitClr); // 251 = x
      }

      if(idx >= 0) RemoveEntry(idx);
   }

   //--- Desenho de bricks (chamado pelo CMksBrickPainterSink) -------+

   void DrawBrick(const MksBrick &brick)
   {
      if(!m_enabled || !m_drawBricks) return;
      if(m_viewMode == MKS_RENKO_VIEW_CLEAN) HideCandlesOnce();

      datetime realTime = (datetime)(brick.closeTimeMsc / 1000);
      if(!m_hasLastBrick)
      {
         // Primeiro brick: sem span anterior. Só registra estado.
         m_lastBrickTime = realTime;
         m_hasLastBrick  = true;
         return;
      }

      datetime x1 = m_lastBrickTime;
      datetime x2 = realTime;
      if((long)x2 <= (long)x1) x2 = (datetime)((long)x1 + 1); // bricks no mesmo segundo

      string name = m_prefix + "B_" + (string)m_brickCount;
      color clr = brick.IsBull() ? m_colorBrickBull : m_colorBrickBear;
      if(ObjectCreate(m_chartId, name, OBJ_RECTANGLE, 0, x1, brick.open, x2, brick.close))
      {
         ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(m_chartId, name, OBJPROP_FILL, true);
         ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
         ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
         m_brickCount++;
      }
      m_lastBrickTime = realTime;
   }

   // Remove todos os objetos desta camada (prefixo MKSCR_VIZ_) e restaura
   // o redraw. Não restaura as cores dos candles (sessão transiente no
   // tester; no live o painter atua no chart do CS, não no base).
   void Clear()
   {
      ObjectsDeleteAll(m_chartId, m_prefix);
      ChartRedraw(m_chartId);
   }

   //--- Inspeção (testes/diagnóstico) ---
   bool Enabled()    const { return m_enabled; }
   bool DrawBricks() const { return m_drawBricks; }
   long ChartId()    const { return m_chartId; }
   ENUM_MKS_RENKO_VIEW ViewMode() const { return m_viewMode; }
};

// Adaptador IRenkoSink → CMksChartPainter. MQL5 não tem herança múltipla,
// então o painter não pode ser ITradeVisualizer E IRenkoSink ao mesmo
// tempo. Este sink encaminha OnBrickClose ao painter.DrawBrick.
class CMksBrickPainterSink : public IRenkoSink
{
private:
   CMksChartPainter *m_painter;

public:
   CMksBrickPainterSink(CMksChartPainter *painter) { m_painter = painter; }

   virtual void OnBrickClose(const MksBrick &brick) override
   {
      if(m_painter != NULL) m_painter.DrawBrick(brick);
   }

   virtual void OnBrickForming(const MksFormingBrick &fb) override { }
};

#endif // MKS_ULTIMATE_CORE_OUTPUT_CMKSCHARTPAINTER_MQH
