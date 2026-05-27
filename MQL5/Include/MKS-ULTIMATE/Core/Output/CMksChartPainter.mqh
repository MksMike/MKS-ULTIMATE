//+------------------------------------------------------------------+
//| @file           : CMksChartPainter.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Output
//| @responsibility : Camada de visualização por chart objects (ADR-028).
//|                   Implementa ITradeVisualizer: desenha setas de
//|                   entrada/saída + linha conectora colorida por P&L
//|                   no chart configurado. Opcionalmente desenha
//|                   retângulos de brick (tester, onde não há CS).
//|                   PURO OUTPUT — nunca lê chart/CS, nunca alimenta
//|                   decisão. No-op em backtest não-visual.
//|                   CMksBrickPainterSink: adaptador IRenkoSink que
//|                   encaminha bricks ao painter (MQL5 não tem herança
//|                   múltipla, então o painter não pode ser os dois).
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

// Desenha marcadores de trade (e opcionalmente bricks) como chart objects.
// Ancora tudo em TEMPO (closeTimeMsc/1000) — o MT5 encaixa na barra mais
// próxima; com timeline híbrida (ADR-023), é a barra do brick correto.
//
// Objetos levam prefixo MKSCR_VIZ_ para Clear() removê-los em bloco sem
// tocar outros objetos do chart. Em backtest não-visual, m_enabled=false
// e todo desenho vira no-op (otimização não paga custo de objeto).
class CMksChartPainter : public ITradeVisualizer
{
private:
   long   m_chartId;
   string m_prefix;
   int    m_digits;
   bool   m_enabled;       // false em backtest não-visual
   bool   m_drawBricks;    // true no tester (sem CS); false no live (CS mostra)

   color  m_colorBuy;
   color  m_colorSell;
   color  m_colorProfit;
   color  m_colorLoss;
   color  m_colorBrickBull;
   color  m_colorBrickBear;

   long   m_brickCount;

   // Rastreio de entradas por positionId (arrays paralelos — MQL5 sem map).
   ulong              m_entId[];
   long               m_entTime[];
   double             m_entPrice[];
   ENUM_MKS_ORDER_SIDE m_entSide[];

   // Estado p/ retângulos de brick (x-span = brick anterior → atual).
   datetime m_lastBrickTime;
   bool     m_hasLastBrick;

   int FindEntry(ulong positionId) const
   {
      int n = ArraySize(m_entId);
      for(int i = 0; i < n; i++)
         if(m_entId[i] == positionId) return i;
      return -1;
   }

   void RecordEntry(ulong positionId, long timeMsc, double price, ENUM_MKS_ORDER_SIDE side)
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
      m_entTime[idx]  = timeMsc;
      m_entPrice[idx] = price;
      m_entSide[idx]  = side;
   }

   void CreateArrow(const string name, long timeMsc, double price, int arrowCode, color clr)
   {
      if(!m_enabled) return;
      datetime t = (datetime)(timeMsc / 1000);
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
   // chartId: chart-alvo (CS no live, chart do tester em backtest).
   // digits: casas decimais do símbolo (não usado hoje, reservado p/ labels).
   // drawBricks: desenhar retângulos de brick (tester=true, live=false).
   // enabled: false desliga todo desenho (backtest não-visual).
   CMksChartPainter(long chartId, int digits, bool drawBricks, bool enabled)
   {
      m_chartId    = chartId;
      m_prefix     = "MKSCR_VIZ_";
      m_digits     = digits;
      m_drawBricks = drawBricks;
      m_enabled    = enabled;

      m_colorBuy       = clrDodgerBlue;
      m_colorSell      = clrOrangeRed;
      m_colorProfit    = clrLimeGreen;
      m_colorLoss      = clrCrimson;
      m_colorBrickBull = clrSeaGreen;
      m_colorBrickBear = clrIndianRed;

      m_brickCount    = 0;
      m_lastBrickTime = 0;
      m_hasLastBrick  = false;
      ArrayResize(m_entId, 0);
      ArrayResize(m_entTime, 0);
      ArrayResize(m_entPrice, 0);
      ArrayResize(m_entSide, 0);
   }

   //--- ITradeVisualizer overrides ---------------------------------+

   virtual void MarkEntry(long timeMsc, ENUM_MKS_ORDER_SIDE side,
                          double price, ulong positionId) override
   {
      RecordEntry(positionId, timeMsc, price, side); // registra mesmo se !enabled
      if(!m_enabled) return;
      // Seta de entrada: code 233 (up) p/ BUY, 234 (down) p/ SELL.
      int    code = (side == MKS_ORDER_BUY) ? 233 : 234;
      color  clr  = (side == MKS_ORDER_BUY) ? m_colorBuy : m_colorSell;
      string name = m_prefix + "E_" + (string)positionId;
      CreateArrow(name, timeMsc, price, code, clr);
   }

   virtual void MarkExit(long timeMsc, double price, ulong positionId) override
   {
      int idx = FindEntry(positionId);

      if(m_enabled)
      {
         // Seta de saída: code 251 (x). Cor por P&L se houver entrada.
         color exitClr = clrSilver;
         if(idx >= 0)
         {
            bool profit = (m_entSide[idx] == MKS_ORDER_BUY)
                          ? (price > m_entPrice[idx])
                          : (price < m_entPrice[idx]);
            exitClr = profit ? m_colorProfit : m_colorLoss;

            // Linha conectora entrada → saída, colorida por P&L.
            string cname = m_prefix + "C_" + (string)positionId;
            datetime t1 = (datetime)(m_entTime[idx] / 1000);
            datetime t2 = (datetime)(timeMsc / 1000);
            if(ObjectCreate(m_chartId, cname, OBJ_TREND, 0,
                            t1, m_entPrice[idx], t2, price))
            {
               ObjectSetInteger(m_chartId, cname, OBJPROP_COLOR, exitClr);
               ObjectSetInteger(m_chartId, cname, OBJPROP_WIDTH, 1);
               ObjectSetInteger(m_chartId, cname, OBJPROP_RAY_RIGHT, false);
               ObjectSetInteger(m_chartId, cname, OBJPROP_BACK, true);
               ObjectSetInteger(m_chartId, cname, OBJPROP_SELECTABLE, false);
            }
         }
         string name = m_prefix + "X_" + (string)positionId;
         CreateArrow(name, timeMsc, price, 251, exitClr);
      }

      // Remove o registro da entrada (posição encerrada).
      if(idx >= 0)
      {
         int last = ArraySize(m_entId) - 1;
         m_entId[idx]    = m_entId[last];
         m_entTime[idx]  = m_entTime[last];
         m_entPrice[idx] = m_entPrice[last];
         m_entSide[idx]  = m_entSide[last];
         ArrayResize(m_entId,    last);
         ArrayResize(m_entTime,  last);
         ArrayResize(m_entPrice, last);
         ArrayResize(m_entSide,  last);
      }
   }

   //--- Desenho de bricks (chamado pelo CMksBrickPainterSink) -------+

   void DrawBrick(const MksBrick &brick)
   {
      if(!m_enabled || !m_drawBricks) { UpdateBrickTime(brick); return; }

      datetime thisTime = (datetime)(brick.closeTimeMsc / 1000);
      if(m_hasLastBrick && thisTime > m_lastBrickTime)
      {
         string name = m_prefix + "B_" + (string)m_brickCount;
         color clr = brick.IsBull() ? m_colorBrickBull : m_colorBrickBear;
         if(ObjectCreate(m_chartId, name, OBJ_RECTANGLE, 0,
                         m_lastBrickTime, brick.open, thisTime, brick.close))
         {
            ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
            ObjectSetInteger(m_chartId, name, OBJPROP_FILL, true);
            ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
            ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
            m_brickCount++;
         }
      }
      UpdateBrickTime(brick);
   }

private:
   void UpdateBrickTime(const MksBrick &brick)
   {
      datetime thisTime = (datetime)(brick.closeTimeMsc / 1000);
      if(thisTime > m_lastBrickTime)
      {
         m_lastBrickTime = thisTime;
         m_hasLastBrick  = true;
      }
   }

public:
   // Remove todos os objetos desta camada (prefixo MKSCR_VIZ_).
   void Clear()
   {
      ObjectsDeleteAll(m_chartId, m_prefix);
   }

   //--- Inspeção (testes/diagnóstico) ---
   bool Enabled()    const { return m_enabled; }
   bool DrawBricks() const { return m_drawBricks; }
   long ChartId()    const { return m_chartId; }
};

// Adaptador IRenkoSink → CMksChartPainter. MQL5 não tem herança múltipla,
// então o painter não pode ser ITradeVisualizer E IRenkoSink ao mesmo
// tempo. Este sink encaminha OnBrickClose ao painter.DrawBrick. Adicionado
// ao multiSink apenas quando bricks devem ser desenhados (tester).
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
