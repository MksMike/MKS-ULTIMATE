//+------------------------------------------------------------------+
//| @file           : CMksStressLabBroker.mqh
//| @project        : MKS-ULTIMATE
//| @module         : StressLab
//| @responsibility : Wrapper de IBroker que aplica condicoes adversas
//|                   (slippage, rejeicao, requote, spread inflado,
//|                   latencia) ao caminho de execucao. ADR-019 + ADR-027
//|                   + ADR-030. Resposta ao Eixo 3 do V5-POSTMORTEM —
//|                   custo aplicado ao trade, nunca contabilizado ao lado.
//|                   ADR-030: adversidade SIMETRICA entrada/saida —
//|                   estressa Send (entrada), Close (saida explicita) e
//|                   auto-close de SL/TP; requote modelado internamente
//|                   (independente do fill do underlying). Determinismo
//|                   via RNG seedavel (CMksRandom).
//| @depends_on     : Core/Interfaces/IBroker.mqh,
//|                   Core/Interfaces/ISymbol.mqh,
//|                   Core/Broker/CMksSimulatedBroker.mqh,
//|                   Core/Types/OrderRequest.mqh,
//|                   Core/Types/ExecutionResult.mqh, Core/Types/Tick.mqh,
//|                   StressLab/CMksRandom.mqh, StressLab/CMksStressParams.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/StressLab/CMksStressLabBroker.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_STRESSLAB_CMKSSTRESSLABBROKER_MQH
#define MKS_ULTIMATE_STRESSLAB_CMKSSTRESSLABBROKER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksSimulatedBroker.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/StressLab/CMksRandom.mqh>
#include <MKS-ULTIMATE/StressLab/CMksStressParams.mqh>

// Metricas agregadas do StressLab durante uma execucao. Dado de auditoria
// do wrapper, exposto via getter (nao via IBroker).
struct CMksStressMetrics
{
   long   sendAttempts;         // total de Send recebidas
   long   sendsRejectedPre;     // rejeitadas antes do underlying (rejection probabilistica)
   long   sendsRejectedRequote; // rejeitadas por tempestade de requote
   long   sendsFilled;          // executadas com sucesso
   long   requoteEvents;        // numero total de requotes (pode ser >1 por Send)
   long   closesStressed;       // closes explicitos que receberam slip (ADR-030)
   long   autoClosesStressed;   // auto-closes (SL/TP) que receberam slip (ADR-030)
   double slippageTotalPoints;  // soma de slippage aplicado em pontos (entrada + saida)
   double slippageMaxPoints;    // pior slippage individual
   double latencyTotalMs;       // soma de latencias sorteadas
   double latencyMaxMs;         // pior latencia individual

   CMksStressMetrics()
   {
      sendAttempts         = 0;
      sendsRejectedPre     = 0;
      sendsRejectedRequote = 0;
      sendsFilled          = 0;
      requoteEvents        = 0;
      closesStressed       = 0;
      autoClosesStressed   = 0;
      slippageTotalPoints  = 0.0;
      slippageMaxPoints    = 0.0;
      latencyTotalMs       = 0.0;
      latencyMaxMs         = 0.0;
   }
};

// CMksStressLabBroker — IBroker que delega para um underlying e injeta
// ruido deterministico no caminho de execucao.
//
// ADR-030 — ADVERSIDADE SIMETRICA:
//   - Send (entrada): rejeicao pre-exec → requote interno → fill → slip adverso.
//   - Close (saida explicita): slip adverso, SE exitSim foi injetado (precisa
//     do lado da posicao, que so o CMksSimulatedBroker concreto sabe).
//   - Auto-close SL/TP: via OnTick/PollAutoCloses DESTE wrapper — delega ao
//     sim broker e aplica slip a cada auto-close drenado. O furo da auditoria
//     era a saida (stop hit) escapar do stress; aqui ela tambem sofre.
//
// REQUOTE (ADR-030): modelado INTERNAMENTE, independente do fill do underlying.
//   O CMksSimulatedBroker sempre preenche, entao um loop que so requota
//   quando o underlying nao preenche seria knob morto. Aqui o requote e
//   um sorteio proprio: cada requote = re-cotacao adversa (+1 sorteio de
//   slip); maxRequotes consecutivos = tempestade → REJECTED.
//
// COUPLING (ADR-030): o `exitSim` (CMksSimulatedBroker* concreto, opcional)
//   destrava a adversidade de SAIDA. Sem ele (underlying generico/mock),
//   Send e estressado normalmente, mas Close/auto-close ficam passthrough —
//   `OnTick`/`PollAutoCloses` nao estao em IBroker. No pipeline canonico,
//   underlying e exitSim sao o MESMO objeto (o broker simulado).
//
// SLIP ADVERSO (por lado da ORDEM): BUY paga mais (+), SELL recebe menos (-).
//   Fechar uma posicao BUY = ordem SELL; fechar SELL = ordem BUY.
//
// Determinismo: mesmas chamadas + mesma seed → mesmo resultado byte-a-byte.
class CMksStressLabBroker : public IBroker
{
private:
   IBroker             *m_underlying;   // delegacao Send/Close/Modify
   CMksSimulatedBroker *m_sim;          // opcional — destrava adversidade de saida
   ISymbol             *m_symbol;
   CMksStressParams     m_params;
   CMksRandom           m_rng;
   CMksStressMetrics    m_metrics;
   MksSimAutoCloseEvent m_autoCloseEvents[]; // auto-closes ja estressados (drenar via PollAutoCloses)

   double SampleSlippage()
   {
      if(m_params.slippageDist == MKS_STRESS_DIST_FIXED)
         return m_params.slippageMean;
      // NORMAL: clamp em zero — slip negativo (favoravel) e contra a logica
      // de "stress"; modela so a cauda adversa.
      double v = m_rng.NextGaussian(m_params.slippageMean, m_params.slippageStdev);
      return (v < 0.0) ? 0.0 : v;
   }

   // Latencia em ms via Gaussiana, clampada em zero. Mean=Stdev=0 retorna 0
   // SEM tocar o RNG — preserva determinismo de testes que nao usam latencia.
   double SampleLatencyMs()
   {
      if(m_params.latencyMeanMs <= 0.0 && m_params.latencyStdevMs <= 0.0)
         return 0.0;
      double v = m_rng.NextGaussian(m_params.latencyMeanMs, m_params.latencyStdevMs);
      return (v < 0.0) ? 0.0 : v;
   }

   // Slip adverso total em pontos: slip da distribuicao (+1 sorteio extra
   // por requote — cada requote moveu o preco) + half-spread composto
   // (ADR-027 §7.2) + drift de latencia (ADR-027 §7.1). Atualiza metrica
   // de latencia (o slip em si e contabilizado em ApplyAdverse).
   double SampleSlipPoints(int requoteDraws)
   {
      double slip = SampleSlippage();
      for(int i = 0; i < requoteDraws; i++)
         slip += SampleSlippage();

      double extraHalfSpread = 0.0;
      double spreadExcess = (m_params.spreadMultiplier - 1.0);
      if(spreadExcess > 0.0 && m_params.baselineSpreadPoints > 0.0)
         extraHalfSpread = spreadExcess * (m_params.baselineSpreadPoints / 2.0);

      double latencyMs = SampleLatencyMs();
      double slipFromLatency = latencyMs * m_params.latencyDriftPointsPerMs;
      m_metrics.latencyTotalMs += latencyMs;
      if(latencyMs > m_metrics.latencyMaxMs)
         m_metrics.latencyMaxMs = latencyMs;

      return slip + extraHalfSpread + slipFromLatency;
   }

   // Empurra `price` adversamente conforme `orderSide` (BUY → +, SELL → -)
   // e contabiliza o slip. Retorna o preco ajustado.
   double ApplyAdverse(double price, ENUM_MKS_ORDER_SIDE orderSide, double slipPoints)
   {
      if(m_symbol == NULL) return price;
      double delta = slipPoints * m_symbol.Point();
      double out = (orderSide == MKS_ORDER_BUY) ? (price + delta) : (price - delta);
      m_metrics.slippageTotalPoints += slipPoints;
      if(slipPoints > m_metrics.slippageMaxPoints)
         m_metrics.slippageMaxPoints = slipPoints;
      return out;
   }

public:
   // underlying e symbol obrigatorios. exitSim (opcional) = o MESMO broker
   // simulado tipado concretamente, para destravar a adversidade de saida.
   CMksStressLabBroker(IBroker *underlying, ISymbol *symbol,
                       const CMksStressParams &params,
                       CMksSimulatedBroker *exitSim = NULL)
      : m_rng(params.rngSeed)
   {
      m_underlying = underlying;
      m_sim        = exitSim;
      m_symbol     = symbol;
      m_params     = params;
      ArrayResize(m_autoCloseEvents, 0);
   }

   //--- IBroker overrides -------------------------------------------+

   MksExecutionResult Send(const MksOrderRequest &request) override
   {
      m_metrics.sendAttempts++;

      if(m_underlying == NULL)
      {
         MksExecutionResult r;
         r.status = MKS_EXEC_ERROR;
         return r;
      }

      // 1. Rejeicao pre-execucao.
      if(m_rng.NextBool(m_params.rejectionProb))
      {
         m_metrics.sendsRejectedPre++;
         MksExecutionResult r;
         r.status        = MKS_EXEC_REJECTED;
         r.brokerRetcode = 10006; // TRADE_RETCODE_REJECT
         return r;
      }

      // 2. Requote interno (ADR-030) — independente do fill do underlying.
      int requotes = 0;
      if(m_params.maxRequotes > 0)
      {
         while(m_rng.NextBool(m_params.requoteProb))
         {
            requotes++;
            m_metrics.requoteEvents++;
            if(requotes >= m_params.maxRequotes)
            {
               // Tempestade de requote — desiste. Underlying nem e chamado.
               m_metrics.sendsRejectedRequote++;
               MksExecutionResult r;
               r.status        = MKS_EXEC_REJECTED;
               r.brokerRetcode = 10004; // TRADE_RETCODE_REQUOTE
               r.attempts      = requotes + 1;
               return r;
            }
         }
      }

      // 3. Underlying preenche.
      MksExecutionResult res = m_underlying.Send(request);
      if(!res.IsFilled())
      {
         res.attempts = requotes + 1;
         return res;
      }

      // 4. Slippage adverso na entrada (com slip extra por requote).
      double slip = SampleSlipPoints(requotes);
      res.fillPrice = ApplyAdverse(res.fillPrice, request.side, slip);
      res.attempts  = requotes + 1;
      m_metrics.sendsFilled++;
      return res;
   }

   MksExecutionResult Close(ulong positionId, double lots) override
   {
      if(m_underlying == NULL)
      {
         MksExecutionResult r;
         r.status = MKS_EXEC_ERROR;
         return r;
      }

      // Lado da posicao (p/ slip adverso direcional) — so com exitSim
      // concreto. Capturado ANTES do Close (a posicao ainda esta aberta).
      bool haveSide = false;
      ENUM_MKS_ORDER_SIDE posSide = MKS_ORDER_BUY;
      if(m_sim != NULL)
      {
         MksSimPosition pos;
         if(m_sim.TryGetPosition(positionId, pos)) { posSide = pos.side; haveSide = true; }
      }

      MksExecutionResult res = m_underlying.Close(positionId, lots);
      if(!res.IsFilled()) return res;

      if(haveSide)
      {
         // Fechar = ordem do lado OPOSTO ao da posicao.
         ENUM_MKS_ORDER_SIDE closeSide =
            (posSide == MKS_ORDER_BUY) ? MKS_ORDER_SELL : MKS_ORDER_BUY;
         double slip = SampleSlipPoints(0);
         res.fillPrice = ApplyAdverse(res.fillPrice, closeSide, slip);
         m_metrics.closesStressed++;
      }
      return res;
   }

   bool Modify(ulong positionId, double slPrice, double tpPrice) override
   {
      // Modify nao gera fill → sem slip. Passthrough.
      if(m_underlying == NULL) return false;
      return m_underlying.Modify(positionId, slPrice, tpPrice);
   }

   //--- Superficie de tick / auto-close (ADR-030; requer exitSim) ---+

   // Delega OnTick ao broker simulado e aplica slip adverso do StressLab a
   // CADA auto-close (SL/TP) gerado — paridade de adversidade com a entrada.
   // O runner/teste DEVE drenar via PollAutoCloses DESTE wrapper (nao do sim
   // broker direto), senao os auto-closes saem sem stress.
   void OnTick(const MksTick &tick)
   {
      if(m_sim == NULL) return;
      m_sim.OnTick(tick);

      MksSimAutoCloseEvent evs[];
      int n = m_sim.PollAutoCloses(evs);
      for(int i = 0; i < n; i++)
      {
         MksSimAutoCloseEvent e = evs[i];
         ENUM_MKS_ORDER_SIDE closeSide =
            (e.side == MKS_ORDER_BUY) ? MKS_ORDER_SELL : MKS_ORDER_BUY;
         double slip = SampleSlipPoints(0);
         e.closePrice = ApplyAdverse(e.closePrice, closeSide, slip);
         m_metrics.autoClosesStressed++;

         int q = ArraySize(m_autoCloseEvents);
         ArrayResize(m_autoCloseEvents, q + 1);
         m_autoCloseEvents[q] = e;
      }
   }

   // Drena os auto-closes ja estressados. Caller drena apos cada OnTick.
   int PollAutoCloses(MksSimAutoCloseEvent &out[])
   {
      int n = ArraySize(m_autoCloseEvents);
      ArrayResize(out, n);
      for(int i = 0; i < n; i++) out[i] = m_autoCloseEvents[i];
      ArrayResize(m_autoCloseEvents, 0);
      return n;
   }

   int PendingAutoCloses() const { return ArraySize(m_autoCloseEvents); }

   //--- Inspecao -----------------------------------------------------+

   CMksStressMetrics Metrics() const { return m_metrics; }

   void ResetMetrics()
   {
      m_metrics = CMksStressMetrics();
   }
};

#endif // MKS_ULTIMATE_STRESSLAB_CMKSSTRESSLABBROKER_MQH
