//+------------------------------------------------------------------+
//| @file           : CMksSimulatedBroker.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Broker
//| @responsibility : Implementação de IBroker para backtest. Mantém
//|                   estado interno de posições; aplica custos via
//|                   CMksCostModel; determinístico. ADR-017.
//| @depends_on     : Core/Interfaces/IBroker.mqh, Core/Interfaces/ISymbol.mqh,
//|                   Core/Broker/CMksCostModel.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/OrderRequest.mqh, Core/Types/ExecutionResult.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Broker/CMksSimulatedBroker.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_BROKER_CMKSSIMULATEDBROKER_MQH
#define MKS_ULTIMATE_CORE_BROKER_CMKSSIMULATEDBROKER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksCostModel.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>

// Posição mantida internamente pelo broker simulado.
// SL e TP armazenados em PREÇO ABSOLUTO (não em pontos).
// ADR-027 §7.3: auto-close de SL/TP agora é executado pelo broker no
// próximo OnTick que tocar o gatilho. Evento enfileirado em
// m_autoCloseEvents — caller polleva via PollAutoCloses para sincronizar
// journal/estado. Detecção usa bid/ask proxy via CostModel half-spread;
// close fill price inclui slippage do CostModel (slippage de SL hit
// realista).
struct MksSimPosition
{
   ulong  id;
   ENUM_MKS_ORDER_SIDE side;
   double lots;
   double openPrice;
   double sl;            // 0 = sem SL
   double tp;            // 0 = sem TP
   double commissionOpen;
   long   openTimeMsc;
   ulong  dealOpenId;
   bool   isOpen;

   MksSimPosition()
   {
      id = 0;
      side = MKS_ORDER_BUY;
      lots = 0.0;
      openPrice = 0.0;
      sl = 0.0;
      tp = 0.0;
      commissionOpen = 0.0;
      openTimeMsc = 0;
      dealOpenId = 0;
      isOpen = false;
   }
};

// Evento emitido pelo broker quando SL ou TP de uma posição é gatilhado
// pelo movimento de preço (ADR-027 §7.3). Caller drena via PollAutoCloses
// no fim de cada OnTick para atualizar journal/estado próprio.
struct MksSimAutoCloseEvent
{
   ulong  positionId;
   ENUM_MKS_ORDER_SIDE side;     // lado da POSIÇÃO original (não do close)
   double lots;
   double openPrice;
   double closePrice;
   double commissionClose;
   long   openTimeMsc;
   long   closeTimeMsc;
   ulong  triggerTickSeq;          // seq (run-local) do tick que cruzou SL/TP (E2)
   ulong  dealCloseId;
   bool   hitSl;                  // true = SL; false = TP

   MksSimAutoCloseEvent()
   {
      positionId = 0;
      side = MKS_ORDER_BUY;
      lots = 0.0;
      openPrice = 0.0;
      closePrice = 0.0;
      commissionClose = 0.0;
      openTimeMsc = 0;
      closeTimeMsc = 0;
      triggerTickSeq = 0;
      dealCloseId = 0;
      hitSl = false;
   }
};

// Broker simulado para backtest. Assume HEDGING — cada Send abre nova
// posição com ticket único. Netting fica para evolução futura.
//
// Uso típico:
//   CMksSimulatedBroker broker(GetPointer(sym), GetPointer(costModel));
//   broker.OnTick(currentTick);      // atualiza mid antes de cada Send/Close
//   MksExecutionResult r = broker.Send(req);
//
// Determinismo: sem RNG. Mesma sequência (OnTick + Send/Close/Modify)
// produz exatamente os mesmos MksExecutionResult — fundamental para
// paridade backtest/live (ADR-017).
class CMksSimulatedBroker : public IBroker
{
private:
   ISymbol            *m_symbol;
   CMksCostModel      *m_costModel;
   double              m_minSlPoints;   // E0.3: backstop de piso de SL (0 = off)
   MksSimPosition      m_positions[];
   ulong               m_nextPositionId;
   ulong               m_nextDealId;
   double              m_lastMid;
   long                m_lastTickTimeMsc;
   ulong               m_lastTickSeq;    // E2: seq do tick corrente (carimba auto-close)
   bool                m_hasMid;

   // Fila de auto-closes pendentes (ADR-027 §7.3). Crescem em OnTick
   // quando SL/TP gatilham; drena via PollAutoCloses. Contador
   // monotônico m_autoCloseTotal preserva visibilidade pós-drain.
   MksSimAutoCloseEvent m_autoCloseEvents[];
   long                 m_autoCloseTotal;

   int FindPositionIndex(ulong positionId) const
   {
      int n = ArraySize(m_positions);
      for(int i = 0; i < n; i++)
         if(m_positions[i].id == positionId)
            return i;
      return -1;
   }

   MksExecutionResult MakeError(int retcode, double requestedPrice = 0.0) const
   {
      MksExecutionResult r;
      r.status = MKS_EXEC_ERROR;
      r.brokerRetcode = retcode;
      r.requestedPrice = requestedPrice;
      r.execTimeMsc = m_lastTickTimeMsc;
      r.attempts = 1;
      return r;
   }

   MksExecutionResult MakeRejected(int retcode, double requestedPrice = 0.0) const
   {
      MksExecutionResult r;
      r.status = MKS_EXEC_REJECTED;
      r.brokerRetcode = retcode;
      r.requestedPrice = requestedPrice;
      r.execTimeMsc = m_lastTickTimeMsc;
      r.attempts = 1;
      return r;
   }

   // Detecta SL/TP gatilhados pelo m_lastMid corrente. Para cada posição
   // aberta com SL ou TP setado, computa bid/ask proxy via half-spread
   // do CostModel; se cruzou o nível, fecha a posição usando o CostModel
   // (inclui slippage de SL hit — close fill realista pode ser pior que
   // o nível). SL tem precedência sobre TP num mesmo tick (worst-case).
   void CheckSlTpTriggers()
   {
      if(m_symbol == NULL || m_costModel == NULL || !m_hasMid) return;

      double point      = m_symbol.Point();
      double halfSpread = (m_costModel.SpreadPoints() / 2.0) * point;
      double bidProxy   = m_lastMid - halfSpread;
      double askProxy   = m_lastMid + halfSpread;

      int n = ArraySize(m_positions);
      for(int i = 0; i < n; i++)
      {
         if(!m_positions[i].isOpen) continue;
         if(m_positions[i].sl == 0.0 && m_positions[i].tp == 0.0) continue;

         bool   hitSl   = false;
         bool   hitTp   = false;
         double sl      = m_positions[i].sl;
         double tp      = m_positions[i].tp;
         ENUM_MKS_ORDER_SIDE side = m_positions[i].side;

         if(side == MKS_ORDER_BUY)
         {
            // BUY fecha vendendo — gatilho referência o bid.
            if(sl > 0.0 && bidProxy <= sl) hitSl = true;
            if(tp > 0.0 && bidProxy >= tp) hitTp = true;
         }
         else
         {
            // SELL fecha comprando — gatilho referência o ask.
            if(sl > 0.0 && askProxy >= sl) hitSl = true;
            if(tp > 0.0 && askProxy <= tp) hitTp = true;
         }

         if(!hitSl && !hitTp) continue;

         // Fecha pelo CostModel — close price inclui spread real + slip
         // (slippage de SL hit é realista: pode fechar pior que SL).
         ENUM_MKS_ORDER_SIDE opposite =
            (side == MKS_ORDER_BUY) ? MKS_ORDER_SELL : MKS_ORDER_BUY;
         double closePrice = m_costModel.FillPriceFor(opposite, m_lastMid, point);
         double lots       = m_positions[i].lots;
         double commission = m_costModel.Commission(lots);

         MksSimAutoCloseEvent ev;
         ev.positionId       = m_positions[i].id;
         ev.side             = side;
         ev.lots             = lots;
         ev.openPrice        = m_positions[i].openPrice;
         ev.closePrice       = closePrice;
         ev.commissionClose  = commission;
         ev.openTimeMsc      = m_positions[i].openTimeMsc;
         ev.closeTimeMsc     = m_lastTickTimeMsc;
         ev.triggerTickSeq   = m_lastTickSeq; // E2: seq do tick que cruzou
         ev.dealCloseId      = m_nextDealId++;
         ev.hitSl            = hitSl; // SL tem precedência se ambos

         int q = ArraySize(m_autoCloseEvents);
         ArrayResize(m_autoCloseEvents, q + 1);
         m_autoCloseEvents[q] = ev;
         m_autoCloseTotal++;

         // Marca posição como fechada.
         m_positions[i].isOpen = false;
         m_positions[i].lots   = 0.0;
      }
   }

public:
   // minSlPoints: backstop de piso de SL (E0.3/M12). Default 0 = desligado
   // — preserva os sites de teste existentes. NÃO é o mecanismo
   // autoritativo de paridade (esse é o gate CMksRiskManager); é rede
   // para uso CRU do sim em testes. No runner de replay/StressLab (E2) o
   // sim é envolvido num CMksRiskGatedBroker com o MESMO RiskManager e
   // este backstop recebe o piso final já-computado.
   CMksSimulatedBroker(ISymbol *symbol, CMksCostModel *costModel,
                       double minSlPoints = 0.0)
   {
      m_symbol           = symbol;
      m_costModel        = costModel;
      m_minSlPoints      = minSlPoints;
      m_nextPositionId   = 1;
      m_nextDealId       = 1;
      m_lastMid          = 0.0;
      m_lastTickTimeMsc  = 0;
      m_lastTickSeq      = 0;
      m_hasMid           = false;
      m_autoCloseTotal   = 0;
      ArrayResize(m_positions, 0);
      ArrayResize(m_autoCloseEvents, 0);
   }

   // Atualiza preço corrente do broker e dispara auto-close de SL/TP
   // gatilhados pelo movimento (ADR-027 §7.3). Caller (EA/script) chama
   // a cada tick antes de Send/Close para garantir que o broker conheça
   // o mid; eventos resultantes ficam na fila até PollAutoCloses.
   void OnTick(const MksTick &tick)
   {
      if(!tick.IsValid()) return;
      m_lastMid         = (tick.bid + tick.ask) / 2.0;
      m_lastTickTimeMsc = tick.timeMsc;
      m_lastTickSeq     = tick.seq;   // E2: carimba o seq no auto-close
      m_hasMid          = true;
      CheckSlTpTriggers();
   }

   MksExecutionResult Send(const MksOrderRequest &request) override
   {
      if(m_symbol == NULL || m_costModel == NULL)
         return MakeError(MKS_ERR_BROKER_NOT_INITIALIZED);
      if(!m_hasMid)
         return MakeError(MKS_ERR_BROKER_NOT_INITIALIZED);
      if(!request.IsValid())
         return MakeRejected(MKS_ERR_CORE_INVALID_ARGUMENT, m_lastMid);

      // Backstop de piso de SL (E0.3): rejeita SL abaixo do piso, como o
      // servidor real (10016). MESMO código 410 do gate → registro de
      // rejeição idêntico bt/live. Só rede para uso cru do sim; a decisão
      // autoritativa é do CMksRiskManager (ver comentário do construtor).
      if(m_minSlPoints > 0.0 && request.slPoints > 0.0 &&
         request.slPoints < m_minSlPoints)
         return MakeRejected(MKS_ERR_RISK_REJECTED_SL_BELOW_STOPS, m_lastMid);

      double point     = m_symbol.Point();
      double fillPrice = m_costModel.FillPriceFor(request.side, m_lastMid, point);
      double commission = m_costModel.Commission(request.lots);

      // SL/TP em preço absoluto (request traz em pontos).
      double slPrice = 0.0;
      double tpPrice = 0.0;
      if(request.slPoints > 0.0)
      {
         if(request.side == MKS_ORDER_BUY)
            slPrice = fillPrice - request.slPoints * point;
         else
            slPrice = fillPrice + request.slPoints * point;
      }
      if(request.tpPoints > 0.0)
      {
         if(request.side == MKS_ORDER_BUY)
            tpPrice = fillPrice + request.tpPoints * point;
         else
            tpPrice = fillPrice - request.tpPoints * point;
      }

      // Cria position.
      MksSimPosition pos;
      pos.id              = m_nextPositionId++;
      pos.side            = request.side;
      pos.lots            = request.lots;
      pos.openPrice       = fillPrice;
      pos.sl              = slPrice;
      pos.tp              = tpPrice;
      pos.commissionOpen  = commission;
      pos.openTimeMsc     = m_lastTickTimeMsc;
      pos.dealOpenId      = m_nextDealId++;
      pos.isOpen          = true;
      int n = ArraySize(m_positions);
      ArrayResize(m_positions, n + 1);
      m_positions[n] = pos;

      // Monta resultado.
      MksExecutionResult r;
      r.status          = MKS_EXEC_FILLED;
      r.positionId      = pos.id;
      r.dealId          = pos.dealOpenId;
      r.fillPrice       = fillPrice;
      r.requestedPrice  = m_lastMid;
      r.filledLots      = request.lots;
      r.commission      = commission;
      r.swap            = 0.0; // sem carry na abertura
      r.execTimeMsc     = m_lastTickTimeMsc;
      r.brokerRetcode   = 0;
      r.attempts        = 1;
      return r;
   }

   MksExecutionResult Close(ulong positionId, double lots) override
   {
      if(m_symbol == NULL || m_costModel == NULL)
         return MakeError(MKS_ERR_BROKER_NOT_INITIALIZED);
      if(!m_hasMid)
         return MakeError(MKS_ERR_BROKER_NOT_INITIALIZED);

      int idx = FindPositionIndex(positionId);
      if(idx < 0 || !m_positions[idx].isOpen)
         return MakeRejected(MKS_ERR_CORE_INVALID_ARGUMENT, m_lastMid);
      if(lots <= 0.0 || lots > m_positions[idx].lots)
         return MakeRejected(MKS_ERR_CORE_INVALID_ARGUMENT, m_lastMid);

      double point = m_symbol.Point();
      // Close fill: lado oposto ao da posição.
      ENUM_MKS_ORDER_SIDE oppositeSide =
         (m_positions[idx].side == MKS_ORDER_BUY) ? MKS_ORDER_SELL : MKS_ORDER_BUY;
      double fillPrice  = m_costModel.FillPriceFor(oppositeSide, m_lastMid, point);
      double commission = m_costModel.Commission(lots);

      // Reduz/zera a posição.
      bool fullClose = (lots >= m_positions[idx].lots);
      if(fullClose)
      {
         m_positions[idx].isOpen = false;
         m_positions[idx].lots   = 0.0;
      }
      else
      {
         m_positions[idx].lots -= lots;
      }

      MksExecutionResult r;
      r.status          = MKS_EXEC_FILLED;
      r.positionId      = positionId;
      r.dealId          = m_nextDealId++;
      r.fillPrice       = fillPrice;
      r.requestedPrice  = m_lastMid;
      r.filledLots      = lots;
      r.commission      = commission;
      r.swap            = 0.0; // swap acumulado não é modelado em v1
      r.execTimeMsc     = m_lastTickTimeMsc;
      r.brokerRetcode   = 0;
      r.attempts        = 1;
      return r;
   }

   bool Modify(ulong positionId, double slPrice, double tpPrice) override
   {
      int idx = FindPositionIndex(positionId);
      if(idx < 0 || !m_positions[idx].isOpen) return false;
      m_positions[idx].sl = slPrice;
      m_positions[idx].tp = tpPrice;
      return true;
   }

   //--- Observabilidade (testes/diagnóstico) ---
   int OpenPositionsCount() const
   {
      int count = 0;
      int n = ArraySize(m_positions);
      for(int i = 0; i < n; i++)
         if(m_positions[i].isOpen) count++;
      return count;
   }

   int TotalPositionsCount() const { return ArraySize(m_positions); }

   bool TryGetPosition(ulong positionId, MksSimPosition &out) const
   {
      int idx = FindPositionIndex(positionId);
      if(idx < 0) return false;
      out = m_positions[idx];
      return true;
   }

   // Enumera as posições ABERTAS por índice (0..OpenPositionsCount()-1),
   // em ordem de abertura. Usado pelo CMksSimPositionBook (IPositionBook
   // lastreado no sim, E2) para TotalLots/PositionAt. false se o índice
   // está fora do range no instante da chamada.
   bool OpenPositionByIndex(const int openIndex, MksSimPosition &out) const
   {
      if(openIndex < 0) return false;
      int n = ArraySize(m_positions);
      int hits = 0;
      for(int i = 0; i < n; i++)
      {
         if(!m_positions[i].isOpen) continue;
         if(hits == openIndex) { out = m_positions[i]; return true; }
         hits++;
      }
      return false;
   }

   double LastMid() const { return m_lastMid; }
   bool   HasMid()  const { return m_hasMid; }

   // Drena a fila de eventos de auto-close (SL/TP gatilhados em OnTick).
   // Caller copia os eventos para sua estrutura e zera a fila — chamado
   // após cada OnTick para sincronizar journal/estado próprio. Contagem
   // monotônica total acessível via AutoCloseTotal mesmo após drain.
   int PollAutoCloses(MksSimAutoCloseEvent &out[])
   {
      int n = ArraySize(m_autoCloseEvents);
      ArrayResize(out, n);
      for(int i = 0; i < n; i++) out[i] = m_autoCloseEvents[i];
      ArrayResize(m_autoCloseEvents, 0);
      return n;
   }

   int  PendingAutoCloses() const { return ArraySize(m_autoCloseEvents); }
   long AutoCloseTotal()    const { return m_autoCloseTotal; }
};

#endif // MKS_ULTIMATE_CORE_BROKER_CMKSSIMULATEDBROKER_MQH
