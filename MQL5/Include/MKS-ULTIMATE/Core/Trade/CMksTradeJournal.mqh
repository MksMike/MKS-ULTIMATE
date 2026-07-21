//+------------------------------------------------------------------+
//| @file           : CMksTradeJournal.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Trade
//| @responsibility : Diario de trades — rastreia posicoes abertas
//|                   e trades fechados, calcula metricas agregadas
//|                   (win rate, profit factor, gross/avg/largest,
//|                   sequencias). Componente puro de coleta: caller
//|                   chama OnFill/OnClose nos pontos certos. Usado
//|                   pelo CMksStressLabReport (Fase 7) e disponivel
//|                   para qualquer estrategia que queira auditar
//|                   seu proprio desempenho.
//| @depends_on     : Core/Types/OrderRequest.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Trade/CMksTradeJournal.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TRADE_CMKSTRADEJOURNAL_MQH
#define MKS_ULTIMATE_CORE_TRADE_CMKSTRADEJOURNAL_MQH

#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>

// Trade fechado: snapshot completo do que aconteceu, em pontos.
//
// pnlPoints e funcao pura de (open, close, side, point):
//   BUY:  pnlPoints = (close - open) / point
//   SELL: pnlPoints = (open - close) / point
// Lots NAO entra no calculo de pnlPoints — esse e o overhead unitario.
// Conversao para moeda da conta fica a cargo do consumer (pnlPoints
// * lots * tickValue / tickSize).
struct MksClosedTrade
{
   ulong  positionId;
   ENUM_MKS_ORDER_SIDE side;
   double lots;
   double openPrice;
   double closePrice;
   long   openTimeMsc;
   long   closeTimeMsc;
   double pnlPoints;
   double commission;   // custo total do trade (abertura + fechamento), em moeda — E4.1/ADR-034
   double swap;         // swap acumulado, em moeda (0 em v1 — swap OFF, ADR-030)
};

// Posicao em aberto. Quando RecordClose for chamado, vira MksClosedTrade.
struct MksOpenPosition
{
   ulong  positionId;
   ENUM_MKS_ORDER_SIDE side;
   double lots;
   double openPrice;
   long   openTimeMsc;
   double commissionOpen; // comissão paga na abertura, em moeda — E4.1
};

class CMksTradeJournal
{
private:
   double m_pointSize;  // tamanho do point do simbolo — usado p/ pnlPoints
   // Conversao pontos->moeda (E4.1/ADR-034). 0 = nao configurada: os
   // agregados em MOEDA (currency) devolvem 0 e HasMoneyConversion()=false.
   // Fórmula idêntica à do CMksSimAccount: (priceDiff/tickSize)·tickValue·lots.
   double m_tickSize;
   double m_tickValue;
   MksOpenPosition m_open[];
   MksClosedTrade  m_closed[];

   int FindOpenIndex(ulong positionId) const
   {
      int n = ArraySize(m_open);
      for(int i = 0; i < n; i++)
         if(m_open[i].positionId == positionId) return i;
      return -1;
   }

   void RemoveOpenAt(int idx)
   {
      int n = ArraySize(m_open);
      for(int i = idx; i < n - 1; i++) m_open[i] = m_open[i + 1];
      ArrayResize(m_open, n - 1);
   }

   double ComputePnlPoints(const MksClosedTrade &t) const
   {
      if(m_pointSize <= 0.0) return 0.0;
      double diff = t.closePrice - t.openPrice;
      double sign = (t.side == MKS_ORDER_BUY) ? 1.0 : -1.0;
      return (diff * sign) / m_pointSize;
   }

   // PnL em MOEDA de um trade (bruto, antes de comissão/swap). Função pura
   // de (open, close, side, lots, tickSize, tickValue). 0 se a conversão de
   // moeda não foi configurada. E4.1/ADR-034.
   double PnlCurrency(const MksClosedTrade &t) const
   {
      if(m_tickSize <= 0.0 || m_tickValue <= 0.0) return 0.0;
      double diff = t.closePrice - t.openPrice;
      double sign = (t.side == MKS_ORDER_BUY) ? 1.0 : -1.0;
      return ((diff * sign) / m_tickSize) * m_tickValue * t.lots;
   }

public:
   CMksTradeJournal(double pointSize = 0.01)
   {
      m_pointSize = (pointSize > 0.0) ? pointSize : 0.01;
      m_tickSize  = 0.0;  // conversão de moeda desligada até SetMoneyConversion
      m_tickValue = 0.0;
   }

   void SetPointSize(double v) { if(v > 0.0) m_pointSize = v; }
   double PointSize() const { return m_pointSize; }

   // Habilita os agregados em MOEDA. tickSize/tickValue do símbolo (mesma
   // convenção do sizer/conta). Ambos > 0 → HasMoneyConversion()=true.
   void SetMoneyConversion(double tickSize, double tickValue)
   {
      m_tickSize  = (tickSize  > 0.0) ? tickSize  : 0.0;
      m_tickValue = (tickValue > 0.0) ? tickValue : 0.0;
   }
   bool HasMoneyConversion() const { return m_tickSize > 0.0 && m_tickValue > 0.0; }

   //--- Coleta ------------------------------------------------------+

   // Registra abertura de posicao. Caller chama logo apos broker.Send
   // bem-sucedido. Se positionId ja estiver em aberto, sobrescreve
   // (defensive — caller bug, mas evita estado corrompido).
   void RecordOpen(ulong positionId, ENUM_MKS_ORDER_SIDE side,
                   double lots, double openPrice, long openTimeMsc,
                   double commissionOpen = 0.0)
   {
      int idx = FindOpenIndex(positionId);
      MksOpenPosition pos;
      pos.positionId     = positionId;
      pos.side           = side;
      pos.lots           = lots;
      pos.openPrice      = openPrice;
      pos.openTimeMsc    = openTimeMsc;
      pos.commissionOpen = commissionOpen;
      if(idx >= 0)
      {
         m_open[idx] = pos;
      }
      else
      {
         int n = ArraySize(m_open);
         ArrayResize(m_open, n + 1);
         m_open[n] = pos;
      }
   }

   // Registra fechamento. Move da lista de abertas para fechadas,
   // computa pnlPoints. Retorna false se positionId nao estava aberta.
   bool RecordClose(ulong positionId, double closePrice, long closeTimeMsc,
                    double commissionClose = 0.0)
   {
      int idx = FindOpenIndex(positionId);
      if(idx < 0) return false;
      MksOpenPosition pos = m_open[idx];

      MksClosedTrade t;
      t.positionId    = positionId;
      t.side          = pos.side;
      t.lots          = pos.lots;
      t.openPrice     = pos.openPrice;
      t.closePrice    = closePrice;
      t.openTimeMsc   = pos.openTimeMsc;
      t.closeTimeMsc  = closeTimeMsc;
      t.pnlPoints     = ComputePnlPoints(t);
      t.commission    = pos.commissionOpen + commissionClose; // custo total do trade
      t.swap          = 0.0;                                  // swap OFF em v1 (ADR-030)

      int nc = ArraySize(m_closed);
      ArrayResize(m_closed, nc + 1);
      m_closed[nc] = t;

      RemoveOpenAt(idx);
      return true;
   }

   //--- Estado ------------------------------------------------------+

   int OpenCount()   const { return ArraySize(m_open);   }
   int ClosedCount() const { return ArraySize(m_closed); }

   MksClosedTrade ClosedAt(int idx) const { return m_closed[idx]; }
   MksOpenPosition OpenAt(int idx)  const { return m_open[idx]; }

   //--- Agregados ---------------------------------------------------+

   int WinCount() const
   {
      int c = 0, n = ArraySize(m_closed);
      for(int i = 0; i < n; i++) if(m_closed[i].pnlPoints > 0.0) c++;
      return c;
   }

   int LossCount() const
   {
      int c = 0, n = ArraySize(m_closed);
      for(int i = 0; i < n; i++) if(m_closed[i].pnlPoints < 0.0) c++;
      return c;
   }

   int BreakevenCount() const
   {
      int c = 0, n = ArraySize(m_closed);
      for(int i = 0; i < n; i++) if(m_closed[i].pnlPoints == 0.0) c++;
      return c;
   }

   // Win rate considera apenas wins / (wins + losses); breakeven ignorado.
   double WinRate() const
   {
      int w = WinCount(), l = LossCount();
      int denom = w + l;
      return (denom > 0) ? ((double)w / (double)denom) : 0.0;
   }

   // Soma dos pontos positivos.
   double GrossProfitPoints() const
   {
      double s = 0.0; int n = ArraySize(m_closed);
      for(int i = 0; i < n; i++) if(m_closed[i].pnlPoints > 0.0) s += m_closed[i].pnlPoints;
      return s;
   }

   // Soma absoluta dos pontos negativos (positivo).
   double GrossLossPoints() const
   {
      double s = 0.0; int n = ArraySize(m_closed);
      for(int i = 0; i < n; i++) if(m_closed[i].pnlPoints < 0.0) s -= m_closed[i].pnlPoints;
      return s;
   }

   // Profit factor = grossProfit / grossLoss. Convencoes:
   //   grossLoss == 0 e grossProfit > 0 -> INF (representamos como 1e18)
   //   grossLoss == 0 e grossProfit == 0 -> 0.0
   double ProfitFactor() const
   {
      double gp = GrossProfitPoints();
      double gl = GrossLossPoints();
      if(gl == 0.0) return (gp > 0.0) ? 1e18 : 0.0;
      return gp / gl;
   }

   double NetPnLPoints() const { return GrossProfitPoints() - GrossLossPoints(); }

   //--- Agregados em MOEDA (E4.1/ADR-034) ---------------------------+
   // Fecham o eixo 3 do V5-POSTMORTEM: o custo (comissão) deixa de ser
   // computado-e-descartado e passa a reduzir o resultado. Classificação
   // win/loss segue por pnlPoints (mesmo sinal que PnlCurrency). Sem
   // SetMoneyConversion, os *Currency devolvem 0 (HasMoneyConversion()=false).

   // Soma do PnL em moeda dos trades vencedores (bruto, sem custo).
   double GrossProfitCurrency() const
   {
      double s = 0.0; int n = ArraySize(m_closed);
      for(int i = 0; i < n; i++)
         if(m_closed[i].pnlPoints > 0.0) s += PnlCurrency(m_closed[i]);
      return s;
   }

   // Soma absoluta (positiva) do PnL em moeda dos trades perdedores.
   double GrossLossCurrency() const
   {
      double s = 0.0; int n = ArraySize(m_closed);
      for(int i = 0; i < n; i++)
         if(m_closed[i].pnlPoints < 0.0) s -= PnlCurrency(m_closed[i]);
      return s;
   }

   // Comissão total acumulada (abertura + fechamento de todos os trades).
   double TotalCommission() const
   {
      double s = 0.0; int n = ArraySize(m_closed);
      for(int i = 0; i < n; i++) s += m_closed[i].commission;
      return s;
   }

   // Swap total acumulado (0 em v1 — swap OFF, ADR-030).
   double TotalSwap() const
   {
      double s = 0.0; int n = ArraySize(m_closed);
      for(int i = 0; i < n; i++) s += m_closed[i].swap;
      return s;
   }

   // Resultado LÍQUIDO em moeda = bruto − comissão − swap. É a métrica que
   // "diz pra ir pra live" sentindo o custo. 0 sem conversão de moeda.
   double NetPnLCurrency() const
   {
      if(!HasMoneyConversion()) return 0.0;
      return (GrossProfitCurrency() - GrossLossCurrency())
             - TotalCommission() - TotalSwap();
   }

   double AvgWinPoints() const
   {
      int w = WinCount();
      return (w > 0) ? (GrossProfitPoints() / w) : 0.0;
   }

   double AvgLossPoints() const
   {
      int l = LossCount();
      return (l > 0) ? (GrossLossPoints() / l) : 0.0;
   }

   double LargestWinPoints() const
   {
      double best = 0.0; int n = ArraySize(m_closed);
      for(int i = 0; i < n; i++)
         if(m_closed[i].pnlPoints > best) best = m_closed[i].pnlPoints;
      return best;
   }

   double LargestLossPoints() const
   {
      double worst = 0.0; int n = ArraySize(m_closed);
      for(int i = 0; i < n; i++)
         if(-m_closed[i].pnlPoints > worst) worst = -m_closed[i].pnlPoints;
      return worst;
   }

   int MaxConsecutiveWins() const
   {
      int n = ArraySize(m_closed); int run = 0, best = 0;
      for(int i = 0; i < n; i++)
      {
         if(m_closed[i].pnlPoints > 0.0) { run++; if(run > best) best = run; }
         else run = 0;
      }
      return best;
   }

   int MaxConsecutiveLosses() const
   {
      int n = ArraySize(m_closed); int run = 0, best = 0;
      for(int i = 0; i < n; i++)
      {
         if(m_closed[i].pnlPoints < 0.0) { run++; if(run > best) best = run; }
         else run = 0;
      }
      return best;
   }

   void Reset()
   {
      ArrayResize(m_open,   0);
      ArrayResize(m_closed, 0);
   }
};

#endif // MKS_ULTIMATE_CORE_TRADE_CMKSTRADEJOURNAL_MQH
