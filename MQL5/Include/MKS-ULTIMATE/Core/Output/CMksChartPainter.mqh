//+------------------------------------------------------------------+
//| @file           : CMksChartPainter.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Output
//| @responsibility : Camada de visualização de TRADES por chart objects
//|                   (ADR-028). Implementa ITradeVisualizer: setas de
//|                   entrada/saída + linha conectora colorida por P&L,
//|                   ancoradas no tempo real do tick disparador. Funciona
//|                   em qualquer chart-alvo: no live desenha sobre o CS
//|                   renko (XAUUSDm.MKSCR_*); no tester desenha sobre os
//|                   candles M1 reais (onde os trades aconteceram).
//|                   NÃO desenha bricks — renko é responsabilidade do CS
//|                   (live) ou do visualizador de backtest (.mksbk → CS).
//|                   Tentar fingir bricks no chart de tempo real do tester
//|                   era gambiarra (ver nota ADR-028 2026-05-28); removido.
//|                   PURO OUTPUT — nunca lê chart/CS, nunca alimenta
//|                   decisão. No-op em backtest não-visual.
//| @depends_on     : Core/Interfaces/ITradeVisualizer.mqh,
//|                   Core/Types/OrderRequest.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Output/CMksChartPainter.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_OUTPUT_CMKSCHARTPAINTER_MQH
#define MKS_ULTIMATE_CORE_OUTPUT_CMKSCHARTPAINTER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/ITradeVisualizer.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ILogger.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>

// Desenha marcadores de trade como chart objects, ancorados no TEMPO REAL
// (timeMsc/1000) do tick disparador. No live o MT5 encaixa o marcador na
// barra do CS via timeline híbrida (ADR-023); no tester encaixa no candle
// M1 correspondente. Entrada: seta ▲ (BUY azul) / ▼ (SELL laranja).
// Saída: seta ✗ + linha conectora entrada→saída colorida por P&L (verde
// lucro, vermelho prejuízo).
class CMksChartPainter : public ITradeVisualizer
{
private:
   long     m_chartId;
   string   m_prefix;
   int      m_digits;
   bool     m_enabled;        // false em backtest não-visual
   ILogger *m_logger;         // opcional — diagnóstico de desenho

   color  m_colorBuy;
   color  m_colorSell;
   color  m_colorProfit;
   color  m_colorLoss;

   // Rastreio de entradas por positionId (arrays paralelos — MQL5 sem map).
   ulong              m_entId[];
   datetime           m_entTime[];
   double             m_entPrice[];
   ENUM_MKS_ORDER_SIDE m_entSide[];

   int FindEntry(ulong positionId) const
   {
      int n = ArraySize(m_entId);
      for(int i = 0; i < n; i++)
         if(m_entId[i] == positionId) return i;
      return -1;
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

   // Tempo de ancoragem do marcador. No chart-alvo, a barra mais recente
   // (index 0) é o brick que disparou o trade — o CSSink processa o brick
   // ANTES da estratégia na mesma OnBrickClose (ordem do multiSink), então
   // iTime(...,0) devolve exatamente a barra desse brick. Isso resolve o
   // descasamento: o CS usa timeline híbrida com bump (ADR-023), e o tempo
   // real do tick (timeMsc) diverge das barras do CS — ancorar no tempo
   // real jogava o marcador atrás das barras (fora da tela). Fallback ao
   // tempo real se a série do símbolo ainda não estiver disponível.
   datetime AnchorTime(long timeMsc) const
   {
      datetime barT = iTime(ChartSymbol(m_chartId), PERIOD_M1, 0);
      if(barT > 0) return barT;
      return (datetime)(timeMsc / 1000);
   }

   void LogDraw(const string &what, const string &name, datetime t, double price, bool ok)
   {
      if(m_logger == NULL) return;
      m_logger.Log(ok ? MKS_LOG_INFO : MKS_LOG_WARN, "ChartPainter", what,
         StringFormat("\"chartId\":%I64d,\"obj\":\"%s\",\"t\":%I64d,\"price\":%.5f,"
                      "\"ok\":%s,\"lastErr\":%d",
                      m_chartId, name, (long)t, price,
                      (ok ? "true" : "false"), (ok ? 0 : GetLastError())));
   }

   void CreateArrow(const string name, datetime t, double price, int arrowCode, color clr)
   {
      if(!m_enabled) return;
      bool ok = ObjectCreate(m_chartId, name, OBJ_ARROW, 0, t, price);
      if(ok)
      {
         ObjectSetInteger(m_chartId, name, OBJPROP_ARROWCODE, arrowCode);
         ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(m_chartId, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
         ObjectSetInteger(m_chartId, name, OBJPROP_BACK, false);
         ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
      }
      LogDraw("arrow", name, t, price, ok);
   }

public:
   // chartId: chart-alvo (CS no live, chart do tester no backtest).
   // digits: casas decimais. enabled: false desliga todo desenho
   // (backtest não-visual — paridade preservada, ADR-028 §7).
   CMksChartPainter(long chartId, int digits, bool enabled, ILogger *logger = NULL)
   {
      m_chartId = chartId;
      m_prefix  = "MKSCR_VIZ_";
      m_digits  = digits;
      m_enabled = enabled;
      m_logger  = logger;

      m_colorBuy    = clrDodgerBlue;
      m_colorSell   = clrOrangeRed;
      m_colorProfit = clrLimeGreen;
      m_colorLoss   = clrCrimson;

      ArrayResize(m_entId, 0);
      ArrayResize(m_entTime, 0);
      ArrayResize(m_entPrice, 0);
      ArrayResize(m_entSide, 0);
   }

   //--- ITradeVisualizer overrides ---------------------------------+

   virtual void MarkEntry(long timeMsc, ENUM_MKS_ORDER_SIDE side,
                          double price, ulong positionId) override
   {
      datetime t = AnchorTime(timeMsc);
      RecordEntry(positionId, t, price, side); // registra mesmo se !enabled
      if(!m_enabled) return;
      int    code = (side == MKS_ORDER_BUY) ? 233 : 234; // 233 up, 234 down
      color  clr  = (side == MKS_ORDER_BUY) ? m_colorBuy : m_colorSell;
      string name = m_prefix + "E_" + (string)positionId;
      CreateArrow(name, t, price, code, clr);
      // O painter desenha no chart do CS, que é DIFERENTE do chart que
      // processa os ticks do EA (o base). Objeto criado em outro chart só
      // aparece após ChartRedraw explícito daquele chart.
      ChartRedraw(m_chartId);
   }

   virtual void MarkExit(long timeMsc, double price, ulong positionId) override
   {
      int idx = FindEntry(positionId);
      datetime t = AnchorTime(timeMsc);

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
            bool okc = ObjectCreate(m_chartId, cname, OBJ_TREND, 0,
                            m_entTime[idx], m_entPrice[idx], t, price);
            if(okc)
            {
               ObjectSetInteger(m_chartId, cname, OBJPROP_COLOR, exitClr);
               ObjectSetInteger(m_chartId, cname, OBJPROP_WIDTH, 1);
               ObjectSetInteger(m_chartId, cname, OBJPROP_RAY_RIGHT, false);
               ObjectSetInteger(m_chartId, cname, OBJPROP_BACK, true);
               ObjectSetInteger(m_chartId, cname, OBJPROP_SELECTABLE, false);
            }
            LogDraw("connector", cname, t, price, okc);
         }
         string name = m_prefix + "X_" + (string)positionId;
         CreateArrow(name, t, price, 251, exitClr); // 251 = x
         ChartRedraw(m_chartId); // cross-chart: força refresh do chart do CS
      }

      if(idx >= 0) RemoveEntry(idx);
   }

   // Remove todos os objetos desta camada (prefixo MKSCR_VIZ_).
   void Clear()
   {
      ObjectsDeleteAll(m_chartId, m_prefix);
      ChartRedraw(m_chartId);
   }

   //--- Inspeção (testes/diagnóstico) ---
   bool Enabled() const { return m_enabled; }
   long ChartId() const { return m_chartId; }
};

#endif // MKS_ULTIMATE_CORE_OUTPUT_CMKSCHARTPAINTER_MQH
