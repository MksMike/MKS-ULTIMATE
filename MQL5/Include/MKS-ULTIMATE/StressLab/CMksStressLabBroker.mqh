//+------------------------------------------------------------------+
//| @file           : CMksStressLabBroker.mqh
//| @project        : MKS-ULTIMATE
//| @module         : StressLab
//| @responsibility : Wrapper de IBroker que aplica condicoes adversas
//|                   (slippage, rejeicao, requote, spread inflado) sobre
//|                   um IBroker subjacente. Determinismo garantido por
//|                   RNG seedavel (CMksRandom). Fase 7 ADR-019. Resposta
//|                   direta ao Eixo 3 do V5-POSTMORTEM (custo de
//|                   execucao aplicado ao trade, nunca contabilizado
//|                   ao lado).
//| @depends_on     : Core/Interfaces/IBroker.mqh,
//|                   Core/Interfaces/ISymbol.mqh,
//|                   Core/Types/OrderRequest.mqh,
//|                   Core/Types/ExecutionResult.mqh,
//|                   StressLab/CMksRandom.mqh,
//|                   StressLab/CMksStressParams.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/StressLab/CMksStressLabBroker.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_STRESSLAB_CMKSSTRESSLABBROKER_MQH
#define MKS_ULTIMATE_STRESSLAB_CMKSSTRESSLABBROKER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/StressLab/CMksRandom.mqh>
#include <MKS-ULTIMATE/StressLab/CMksStressParams.mqh>

// Metricas agregadas do StressLab durante uma execucao.
//
// Coletadas em runtime para permitir relatorio comparativo entre niveis
// (criterio de saida da Fase 7). Acessiveis via getter — o broker nao
// expoe via interface IBroker (que nao tem esse contrato) porque sao
// dado de auditoria do wrapper, nao do contrato de execucao.
struct CMksStressMetrics
{
   long   sendAttempts;       // total de Send recebidas
   long   sendsRejectedPre;   // rejeitadas antes do underlying (rejection probabilistica)
   long   sendsRejectedRequote; // rejeitadas pos maxRequotes
   long   sendsFilled;        // executadas com sucesso (pode incluir requotes anteriores)
   long   requoteEvents;      // numero total de requotes (pode ser >1 por Send)
   double slippageTotalPoints;// soma absoluta de slippage aplicado em pontos
   double slippageMaxPoints;  // pior slippage individual
   double latencyTotalMs;     // soma de latencias sorteadas (ADR-027)
   double latencyMaxMs;       // pior latencia individual

   CMksStressMetrics()
   {
      sendAttempts         = 0;
      sendsRejectedPre     = 0;
      sendsRejectedRequote = 0;
      sendsFilled          = 0;
      requoteEvents        = 0;
      slippageTotalPoints  = 0.0;
      slippageMaxPoints    = 0.0;
      latencyTotalMs       = 0.0;
      latencyMaxMs         = 0.0;
   }
};

// CMksStressLabBroker — implementa IBroker delegando para underlying
// e injetando ruido deterministico no caminho de execucao.
//
// COMPORTAMENTO POR ETAPA NO Send():
//   1. Sorteia rejeicao pre-execucao (rejectionProb). Se rejeitar:
//      retorna REJECTED sem chamar underlying; metrica++.
//   2. Loop de requote (ate maxRequotes):
//      a. underlying.Send(request)
//      b. se result.IsFilled() ou status irrecuperavel: sai do loop
//      c. se requoteProb sorteia: tenta de novo, metrica.requoteEvents++
//      d. se atingir maxRequotes sem fill: retorna REJECTED com motivo requote
//   3. Pos-fill: aplica slippage agregado sobre fillPrice — adverso ao lado.
//      slipTotal = sampledSlippage + extraHalfSpread + slipFromLatency
//        - sampledSlippage   : SampleSlippage() conforme distribuicao
//        - extraHalfSpread   : (mult - 1) * (baselineSpreadPoints / 2)
//                              compõe sobre o spread real do CostModel (ADR-027 §7.2)
//        - slipFromLatency   : sampledLatencyMs * latencyDriftPointsPerMs
//                              modela "preco se moveu durante a latencia" (ADR-027 §7.1)
//      BUY: fillPrice += slipTotal * point  (paga mais caro)
//      SELL: fillPrice -= slipTotal * point (recebe menos)
//
// Close e Modify sao PASSTHROUGH em v1 — stress se aplica a abertura.
// Pode evoluir em slice futuro para tambem estressar fechamento se for
// necessario modelar slippage de SL/TP.
//
// Determinismo: chamadas identicas, mesmas params, mesma seed → mesmo
// resultado byte-a-byte. Golden test possivel.
class CMksStressLabBroker : public IBroker
{
private:
   IBroker         *m_underlying;
   ISymbol         *m_symbol;
   CMksStressParams m_params;
   CMksRandom       m_rng;
   CMksStressMetrics m_metrics;

   double SampleSlippage()
   {
      if(m_params.slippageDist == MKS_STRESS_DIST_FIXED)
         return m_params.slippageMean;
      // NORMAL: clamp em zero — slip negativo (favoravel ao trader) e
      // contra a logica de "stress"; preferimos modelar so a cauda
      // adversa. Mantem semantica de "stress so piora".
      double v = m_rng.NextGaussian(m_params.slippageMean, m_params.slippageStdev);
      return (v < 0.0) ? 0.0 : v;
   }

   // Sorteia latencia em ms via Gaussiana, clampa em zero (latencia
   // negativa nao faz sentido fisico). Mean=Stdev=0 retorna 0 sem
   // tocar o RNG — preserva determinismo de testes que nao usam latencia.
   double SampleLatencyMs()
   {
      if(m_params.latencyMeanMs <= 0.0 && m_params.latencyStdevMs <= 0.0)
         return 0.0;
      double v = m_rng.NextGaussian(m_params.latencyMeanMs, m_params.latencyStdevMs);
      return (v < 0.0) ? 0.0 : v;
   }

   void ApplySlippageToFill(const MksOrderRequest &req, MksExecutionResult &res)
   {
      if(!res.IsFilled()) return;
      if(m_symbol == NULL) return;

      double slipFromDist = SampleSlippage();

      // Spread multiplier compõe sobre o spread baseline do CostModel.
      // (mult - 1) * (baseline / 2) = pontos extras adversos por lado
      // — equivalente a "spread real ficou mult× maior" (ADR-027 §7.2).
      double extraHalfSpread = 0.0;
      double spreadExcess = (m_params.spreadMultiplier - 1.0);
      if(spreadExcess > 0.0 && m_params.baselineSpreadPoints > 0.0)
         extraHalfSpread = spreadExcess * (m_params.baselineSpreadPoints / 2.0);

      // Latencia: modela "preço se moveu enquanto a ordem viajava".
      // sampledLatencyMs × driftPerMs = pontos extras adversos
      // (ADR-027 §7.1).
      double latencyMs = SampleLatencyMs();
      double slipFromLatency = latencyMs * m_params.latencyDriftPointsPerMs;

      double slipPoints = slipFromDist + extraHalfSpread + slipFromLatency;

      double point = m_symbol.Point();
      double priceDelta = slipPoints * point;
      if(req.side == MKS_ORDER_BUY)
         res.fillPrice += priceDelta;
      else
         res.fillPrice -= priceDelta;

      // Metricas
      m_metrics.slippageTotalPoints += slipPoints;
      if(slipPoints > m_metrics.slippageMaxPoints)
         m_metrics.slippageMaxPoints = slipPoints;
      m_metrics.latencyTotalMs += latencyMs;
      if(latencyMs > m_metrics.latencyMaxMs)
         m_metrics.latencyMaxMs = latencyMs;
   }

public:
   // underlying e symbol obrigatorios. params + seed via construtor.
   CMksStressLabBroker(IBroker *underlying, ISymbol *symbol,
                       const CMksStressParams &params)
      : m_rng(params.rngSeed)
   {
      m_underlying = underlying;
      m_symbol     = symbol;
      m_params     = params;
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

      // 1. Rejeicao pre-execucao
      if(m_rng.NextBool(m_params.rejectionProb))
      {
         m_metrics.sendsRejectedPre++;
         MksExecutionResult r;
         r.status        = MKS_EXEC_REJECTED;
         r.brokerRetcode = 10006; // TRADE_RETCODE_REJECT (canonico MT5)
         return r;
      }

      // 2. Loop de requote
      MksExecutionResult res;
      int attempts = 0;
      int maxTries = (m_params.maxRequotes > 0) ? (m_params.maxRequotes + 1) : 1;

      while(attempts < maxTries)
      {
         res = m_underlying.Send(request);
         attempts++;

         if(res.IsFilled())
            break;

         // Status nao-FILLED: se requoteProb sortear, tenta de novo
         if(attempts < maxTries && m_rng.NextBool(m_params.requoteProb))
         {
            m_metrics.requoteEvents++;
            continue;
         }
         break;
      }

      if(!res.IsFilled())
      {
         // Esgotou requotes ou underlying nao preencheu por outra razao
         if(m_metrics.requoteEvents > 0 && attempts >= maxTries)
            m_metrics.sendsRejectedRequote++;
         res.attempts = attempts; // sobrescreve com a contagem do StressLab
         return res;
      }

      // 3. Aplica slippage no preco de fill
      ApplySlippageToFill(request, res);
      res.attempts = attempts;
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
      return m_underlying.Close(positionId, lots);
   }

   bool Modify(ulong positionId, double slPrice, double tpPrice) override
   {
      if(m_underlying == NULL) return false;
      return m_underlying.Modify(positionId, slPrice, tpPrice);
   }

   //--- Inspecao -----------------------------------------------------+

   CMksStressMetrics Metrics() const { return m_metrics; }

   void ResetMetrics()
   {
      m_metrics.sendAttempts         = 0;
      m_metrics.sendsRejectedPre     = 0;
      m_metrics.sendsRejectedRequote = 0;
      m_metrics.sendsFilled          = 0;
      m_metrics.requoteEvents        = 0;
      m_metrics.slippageTotalPoints  = 0.0;
      m_metrics.slippageMaxPoints    = 0.0;
      m_metrics.latencyTotalMs       = 0.0;
      m_metrics.latencyMaxMs         = 0.0;
   }
};

#endif // MKS_ULTIMATE_STRESSLAB_CMKSSTRESSLABBROKER_MQH
