//+------------------------------------------------------------------+
//| @file           : CMksChartPainter.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Output
//| @responsibility : Camada de visualização por chart objects (ADR-028).
//|                   Implementa ITradeVisualizer: setas de entrada/saída
//|                   + linha conectora colorida por P&L. Opcionalmente
//|                   desenha retângulos de brick (tester, sem CS) em dois
//|                   modos (ADR-028 + feedback 2026-05-27):
//|                     OVERLAY: retângulos proporcionais ao tempo sobre
//|                              os candles M1 (default).
//|                     CLEAN  : esconde os candles + bricks de LARGURA
//|                              IGUAL em slots sintéticos (renko clássico).
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
   MKS_RENKO_VIEW_OVERLAY = 0,  // retângulos proporcionais ao tempo sobre candles
   MKS_RENKO_VIEW_CLEAN   = 1   // largura igual em slots sintéticos + candles escondidos
};

// Desenha marcadores de trade (e opcionalmente bricks) como chart objects.
//
// Coordenada X dos objetos:
//   OVERLAY: tempo real (closeTimeMsc/1000) — alinha com os candles.
//   CLEAN  : slot sintético (base + N×60s) — largura igual, candles
//            escondidos; X não alinha com candles mas eles estão invisíveis.
// Marcadores de trade ancoram no MESMO X do brick que os disparou: o
// painter (via CMksBrickPainterSink) processa o brick ANTES da estratégia
// chamar MarkEntry/MarkExit no mesmo OnBrickClose, então m_lastDisplayTime
// é o X correto. No live (sem desenho de bricks), cai pro tempo real e o
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
   int    m_slotWidthSec;     // largura do slot sintético no modo CLEAN

   color  m_colorBuy;
   color  m_colorSell;
   color  m_colorProfit;
   color  m_colorLoss;
   color  m_colorBrickBull;
   color  m_colorBrickBear;

   long   m_brickCount;

   // OVERLAY: x-span = brick anterior → atual (tempo real).
   datetime m_lastBrickTime;
   bool     m_hasLastBrick;

   // CLEAN: slots sintéticos largura-igual.
   datetime m_baseSlotTime;
   long     m_slotIndex;
   bool     m_candlesHidden;

   // Mapeamento do último brick processado → X de exibição (p/ marcadores).
   long     m_lastCloseTimeMsc;
   datetime m_lastDisplayTime;
   bool     m_hasDisplay;

   // Rastreio de entradas por positionId (arrays paralelos — MQL5 sem map).
   // Guarda o X de exibição JÁ MAPEADO (não o timeMsc cru) para a linha
   // conectora ligar o slot/tempo correto da entrada ao da saída.
   ulong              m_entId[];
   datetime           m_entDisp[];
   double             m_entPrice[];
   ENUM_MKS_ORDER_SIDE m_entSide[];

   int FindEntry(ulong positionId) const
   {
      int n = ArraySize(m_entId);
      for(int i = 0; i < n; i++)
         if(m_entId[i] == positionId) return i;
      return -1;
   }

   // X de exibição de um trade. Se o timeMsc bate com o último brick
   // processado pelo painter, usa o X daquele brick (slot no CLEAN, tempo
   // real no OVERLAY). Senão (live sem desenho de bricks), tempo real.
   datetime MarkerX(long timeMsc) const
   {
      if(m_drawBricks && m_hasDisplay && timeMsc == m_lastCloseTimeMsc)
         return m_lastDisplayTime;
      return (datetime)(timeMsc / 1000);
   }

   void HideCandlesOnce()
   {
      if(m_candlesHidden) return;
      color bg = (color)ChartGetInteger(m_chartId, CHART_COLOR_BACKGROUND);
      ChartSetInteger(m_chartId, CHART_COLOR_CHART_UP,   bg);
      ChartSetInteger(m_chartId, CHART_COLOR_CHART_DOWN, bg);
      ChartSetInteger(m_chartId, CHART_COLOR_CANDLE_BULL, bg);
      ChartSetInteger(m_chartId, CHART_COLOR_CANDLE_BEAR, bg);
      ChartSetInteger(m_chartId, CHART_COLOR_CHART_LINE, bg);
      m_candlesHidden = true;
   }

   void RecordEntry(ulong positionId, datetime dispTime, double price, ENUM_MKS_ORDER_SIDE side)
   {
      int idx = FindEntry(positionId);
      if(idx < 0)
      {
         idx = ArraySize(m_entId);
         ArrayResize(m_entId,    idx + 1);
         ArrayResize(m_entDisp,  idx + 1);
         ArrayResize(m_entPrice, idx + 1);
         ArrayResize(m_entSide,  idx + 1);
      }
      m_entId[idx]    = positionId;
      m_entDisp[idx]  = dispTime;
      m_entPrice[idx] = price;
      m_entSide[idx]  = side;
   }

   void RemoveEntry(int idx)
   {
      int last = ArraySize(m_entId) - 1;
      if(idx < 0 || last < 0) return;
      m_entId[idx]    = m_entId[last];
      m_entDisp[idx]  = m_entDisp[last];
      m_entPrice[idx] = m_entPrice[last];
      m_entSide[idx]  = m_entSide[last];
      ArrayResize(m_entId,    last);
      ArrayResize(m_entDisp,  last);
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
      m_slotWidthSec = 60;

      m_colorBuy       = clrDodgerBlue;
      m_colorSell      = clrOrangeRed;
      m_colorProfit    = clrLimeGreen;
      m_colorLoss      = clrCrimson;
      m_colorBrickBull = clrSeaGreen;
      m_colorBrickBear = clrIndianRed;

      m_brickCount       = 0;
      m_lastBrickTime    = 0;
      m_hasLastBrick     = false;
      m_baseSlotTime     = 0;
      m_slotIndex        = 0;
      m_candlesHidden    = false;
      m_lastCloseTimeMsc = 0;
      m_lastDisplayTime  = 0;
      m_hasDisplay       = false;
      ArrayResize(m_entId, 0);
      ArrayResize(m_entDisp, 0);
      ArrayResize(m_entPrice, 0);
      ArrayResize(m_entSide, 0);
   }

   //--- ITradeVisualizer overrides ---------------------------------+

   virtual void MarkEntry(long timeMsc, ENUM_MKS_ORDER_SIDE side,
                          double price, ulong positionId) override
   {
      datetime x = MarkerX(timeMsc);
      RecordEntry(positionId, x, price, side); // registra mesmo se !enabled
      if(!m_enabled) return;
      int    code = (side == MKS_ORDER_BUY) ? 233 : 234; // 233 up, 234 down
      color  clr  = (side == MKS_ORDER_BUY) ? m_colorBuy : m_colorSell;
      string name = m_prefix + "E_" + (string)positionId;
      CreateArrow(name, x, price, code, clr);
   }

   virtual void MarkExit(long timeMsc, double price, ulong positionId) override
   {
      int idx = FindEntry(positionId);
      datetime x = MarkerX(timeMsc);

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
                            m_entDisp[idx], m_entPrice[idx], x, price))
            {
               ObjectSetInteger(m_chartId, cname, OBJPROP_COLOR, exitClr);
               ObjectSetInteger(m_chartId, cname, OBJPROP_WIDTH, 1);
               ObjectSetInteger(m_chartId, cname, OBJPROP_RAY_RIGHT, false);
               ObjectSetInteger(m_chartId, cname, OBJPROP_BACK, true);
               ObjectSetInteger(m_chartId, cname, OBJPROP_SELECTABLE, false);
            }
         }
         string name = m_prefix + "X_" + (string)positionId;
         CreateArrow(name, x, price, 251, exitClr); // 251 = x
      }

      if(idx >= 0) RemoveEntry(idx);
   }

   //--- Desenho de bricks (chamado pelo CMksBrickPainterSink) -------+

   void DrawBrick(const MksBrick &brick)
   {
      if(!m_enabled || !m_drawBricks) return;

      datetime realTime = (datetime)(brick.closeTimeMsc / 1000);
      datetime x1, x2;

      if(m_viewMode == MKS_RENKO_VIEW_CLEAN)
      {
         HideCandlesOnce();
         if(m_slotIndex == 0)
            m_baseSlotTime = (datetime)((long)realTime - ((long)realTime % 60));
         x1 = (datetime)((long)m_baseSlotTime + m_slotIndex * m_slotWidthSec);
         x2 = (datetime)((long)x1 + m_slotWidthSec);
         m_lastDisplayTime = (datetime)((long)x1 + m_slotWidthSec / 2); // centro p/ marcador
         m_slotIndex++;
      }
      else // OVERLAY
      {
         if(!m_hasLastBrick)
         {
            // Primeiro brick: sem span anterior. Só registra estado.
            m_lastBrickTime    = realTime;
            m_hasLastBrick     = true;
            m_lastCloseTimeMsc = brick.closeTimeMsc;
            m_lastDisplayTime  = realTime;
            m_hasDisplay       = true;
            return;
         }
         x1 = m_lastBrickTime;
         x2 = realTime;
         if((long)x2 <= (long)x1) x2 = (datetime)((long)x1 + 1); // guard p/ bricks no mesmo segundo
         m_lastDisplayTime = realTime;
         m_lastBrickTime   = realTime;
      }

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
      m_lastCloseTimeMsc = brick.closeTimeMsc;
      m_hasDisplay       = true;
   }

   // Remove todos os objetos desta camada (prefixo MKSCR_VIZ_).
   void Clear()
   {
      ObjectsDeleteAll(m_chartId, m_prefix);
   }

   //--- Inspeção (testes/diagnóstico) ---
   bool Enabled()    const { return m_enabled; }
   bool DrawBricks() const { return m_drawBricks; }
   long ChartId()    const { return m_chartId; }
   ENUM_MKS_RENKO_VIEW ViewMode() const { return m_viewMode; }
};

// Adaptador IRenkoSink → CMksChartPainter. MQL5 não tem herança múltipla,
// então o painter não pode ser ITradeVisualizer E IRenkoSink ao mesmo
// tempo. Este sink encaminha OnBrickClose ao painter.DrawBrick. Adicionado
// ao multiSink ANTES da estratégia (para que m_lastDisplayTime esteja
// correto quando a estratégia chamar MarkEntry/MarkExit no mesmo brick).
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
