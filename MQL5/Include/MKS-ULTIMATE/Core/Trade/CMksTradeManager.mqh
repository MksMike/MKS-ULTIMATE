//+------------------------------------------------------------------+
//| @file           : CMksTradeManager.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Trade
//| @responsibility : Gestao de posicao aberta — break-even, trailing
//|                   stop e partial close. State machine clara (idem-
//|                   potente: re-executar Update nao re-aplica acoes).
//|                   Uma instancia por posicao (multi-posicao = varios
//|                   managers, gerenciados pelo composition root).
//|                   Slice 5b da ADR-019. Licao V5 #2: gestao tem
//|                   state machine, nao "vou lembrar de fechar".
//| @depends_on     : Core/Interfaces/IBroker.mqh,
//|                   Core/Interfaces/ISymbol.mqh,
//|                   Core/Interfaces/ILogger.mqh,
//|                   Core/Types/Tick.mqh,
//|                   Core/Types/OrderRequest.mqh,
//|                   Core/Types/ExecutionResult.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Trade/CMksTradeManager.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TRADE_CMKSTRADEMANAGER_MQH
#define MKS_ULTIMATE_CORE_TRADE_CMKSTRADEMANAGER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ILogger.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IPositionBook.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Parâmetros da gestão. Tudo configurável; cada feature individualmente
// ligavel via flag para que estratégias possam pegar só o que precisam
// (so trailing, so partial, so BE, ou combinações).
//
// Pontos (points) são unidades do símbolo (point obtido via ISymbol::Point()
// — o módulo NÃO chama SymbolInfoDouble direto, ver Protocolo 9).
// Para XAUUSD com 3 digits, 1 ponto = 0.001 unidade de preço.
//
// beActivationPoints/trailStartPoints/partialTriggerPoints são lucros
// MINIMOS para ativar a ação — calculados sobre o preço de saída
// (bid para BUY, ask para SELL) menos o preço de entrada.
//
// beOffsetPoints: deslocamento do SL em relação ao entry quando BE
// dispara. Positivo = lucro garantido (SL acima do entry para BUY).
// Zero = breakeven exato. Negativo = não permitido (Validate rejeita).
//
// trailStepPoints: distância entre o preço atual e o novo SL no trail.
// Trail nunca afrouxa — SL só avança no sentido favorável.
//
// partialClosePct: percentual dos lots INICIAIS (não do volume corrente)
// a fechar quando o trigger dispara. Faixa válida (0, 100). 100 = fecha
// tudo (= stop manual); 0 = desliga.
struct CMksTradeManagerParams
{
   bool   beEnabled;
   double beActivationPoints;
   double beOffsetPoints;

   bool   trailEnabled;
   double trailStartPoints;
   double trailStepPoints;

   bool   partialEnabled;
   double partialTriggerPoints;
   double partialClosePct;

   CMksTradeManagerParams()
   {
      beEnabled            = false;
      beActivationPoints   = 0.0;
      beOffsetPoints       = 0.0;

      trailEnabled         = false;
      trailStartPoints     = 0.0;
      trailStepPoints      = 0.0;

      partialEnabled       = false;
      partialTriggerPoints = 0.0;
      partialClosePct      = 0.0;
   }
};

// Resultado do Update() — quantas acoes foram tomadas neste tick.
struct MksTradeManagerStep
{
   bool beApplied;     // BE foi aplicado neste Update (transição)
   bool partialDone;   // partial foi executada neste Update
   bool trailUpdated;  // SL foi movido pelo trailing neste Update
   bool autoDetached;  // posicao sumiu do book — auto-detach (ADR-027 §7.3 + Fase 9 prep)
   int  brokerCalls;   // total de chamadas a broker (Modify+Close)

   MksTradeManagerStep()
   {
      beApplied    = false;
      partialDone  = false;
      trailUpdated = false;
      autoDetached = false;
      brokerCalls  = 0;
   }
};

class CMksTradeManager
{
private:
   IBroker      *m_broker;
   ISymbol      *m_symbol;
   ILogger      *m_logger;
   IPositionBook *m_book;   // opcional — habilita auto-detach quando != NULL
   CMksTradeManagerParams m_params;

   // Estado da posição vinculada
   bool   m_attached;
   ulong  m_positionId;
   ENUM_MKS_ORDER_SIDE m_side;
   double m_entryPrice;
   double m_initialLots;
   double m_initialTp;

   // Estado da gestão
   bool   m_beApplied;
   bool   m_trailActive;
   bool   m_partialDone;
   double m_partialFilledLots; // volume ACUMULADO já fechado pelo partial
                               // (soma dos fills, inclui parciais). Alvo do
                               // partial = m_initialLots·pct; done quando o
                               // acumulado alcança o alvo. ADR-035 / E5.2.
   double m_currentSl;      // último SL aplicado (broker ou setup inicial)

   void LogInfo(const string &msg, const string &ctx)
   {
      if(m_logger == NULL) return;
      m_logger.Log(MKS_LOG_INFO, "TradeManager", msg, ctx);
   }

   void LogWarn(const string &msg, const string &ctx)
   {
      if(m_logger == NULL) return;
      m_logger.Log(MKS_LOG_WARN, "TradeManager", msg, ctx);
   }

   // Preço relevante para SAÍDA da posição.
   double ExitPriceFor(const MksTick &tick) const
   {
      return (m_side == MKS_ORDER_BUY) ? tick.bid : tick.ask;
   }

   // Lucro corrente em pontos. Positivo = lucro, negativo = perda.
   double ProfitPoints(const MksTick &tick) const
   {
      double point = m_symbol.Point();
      if(point <= 0.0) return 0.0;
      double exit = ExitPriceFor(tick);
      double diff = (m_side == MKS_ORDER_BUY)
                    ? (exit - m_entryPrice)
                    : (m_entryPrice - exit);
      return diff / point;
   }

   // SL alvo para BE: entry + offset (BUY) ou entry - offset (SELL).
   double BreakEvenSlPrice() const
   {
      double off = m_params.beOffsetPoints * m_symbol.Point();
      return (m_side == MKS_ORDER_BUY)
             ? m_entryPrice + off
             : m_entryPrice - off;
   }

   // SL alvo para trail: exit - step (BUY) ou exit + step (SELL).
   double TrailSlPrice(const MksTick &tick) const
   {
      double step = m_params.trailStepPoints * m_symbol.Point();
      double exit = ExitPriceFor(tick);
      return (m_side == MKS_ORDER_BUY) ? (exit - step) : (exit + step);
   }

   // Trail só avança — nunca afrouxa.
   bool TrailWouldImproveSl(double candidateSl) const
   {
      return (m_side == MKS_ORDER_BUY)
             ? (candidateSl > m_currentSl)
             : (candidateSl < m_currentSl);
   }

public:
   // broker e symbol são obrigatorios. logger e book são opcionais.
   // book habilita auto-detach: em cada Update, se m_positionId não
   // estiver mais aberto no book, o manager auto-detacha sem chamar
   // Modify/Close sobre positionId fantasma. Necessário com brokers
   // que auto-fecham por SL/TP (CMksSimulatedBroker pós-ADR-027 §7.3,
   // ou qualquer broker live onde stop hit é executado pelo servidor).
   CMksTradeManager(IBroker *broker, ISymbol *symbol,
                    const CMksTradeManagerParams &params,
                    ILogger *logger = NULL,
                    IPositionBook *book = NULL)
   {
      m_broker = broker;
      m_symbol = symbol;
      m_logger = logger;
      m_book   = book;
      m_params = params;
      m_attached    = false;
      m_positionId  = 0;
      m_side        = MKS_ORDER_BUY;
      m_entryPrice  = 0.0;
      m_initialLots = 0.0;
      m_initialTp   = 0.0;
      m_beApplied   = false;
      m_trailActive = false;
      m_partialDone = false;
      m_partialFilledLots = 0.0;
      m_currentSl   = 0.0;
   }

   // Validate config — chame apos construir, antes de Attach.
   bool Validate(MksError &err) const
   {
      if(m_broker == NULL || m_symbol == NULL)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_MANAGER_INVALID_PARAM,
                       "broker/symbol nulos", "");
         return false;
      }
      if(m_params.beEnabled && m_params.beActivationPoints <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_MANAGER_INVALID_PARAM,
                       "beActivationPoints <= 0 com beEnabled",
                       StringFormat("be=%.4f", m_params.beActivationPoints));
         return false;
      }
      if(m_params.beEnabled && m_params.beOffsetPoints < 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_MANAGER_INVALID_PARAM,
                       "beOffsetPoints negativo",
                       StringFormat("offset=%.4f", m_params.beOffsetPoints));
         return false;
      }
      // No gatilho, profit >= beActivation (>=) ⇒ bid ≈ entry + beActivation·point
      // (BUY). O SL de BE vai para entry + beOffset·point. Se beOffset >= beActivation
      // o SL cai no/acima do preço corrente → Modify inválido / stop-out imediato.
      // Mesma álgebra no SELL (bid/ask e sinais se cancelam). '>=' rejeita o caso ==
      // (SL == preço no gatilho já é inválido). NÃO cobre SYMBOL_TRADE_STOPS_LEVEL —
      // ver follow-up: StopsLevel fica fora do runtime por paridade (decisão de ADR).
      if(m_params.beEnabled
         && m_params.beOffsetPoints >= m_params.beActivationPoints)
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_MANAGER_INVALID_PARAM,
                       "beOffsetPoints >= beActivationPoints (SL ficaria >= preço no gatilho de BE)",
                       StringFormat("offset=%.4f act=%.4f",
                                    m_params.beOffsetPoints,
                                    m_params.beActivationPoints));
         return false;
      }
      if(m_params.trailEnabled
         && (m_params.trailStartPoints <= 0.0 || m_params.trailStepPoints <= 0.0))
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_MANAGER_INVALID_PARAM,
                       "trail params <= 0 com trailEnabled",
                       StringFormat("start=%.4f step=%.4f",
                                    m_params.trailStartPoints,
                                    m_params.trailStepPoints));
         return false;
      }
      if(m_params.partialEnabled
         && (m_params.partialTriggerPoints <= 0.0
             || m_params.partialClosePct <= 0.0
             || m_params.partialClosePct >= 100.0))
      {
         MKS_SET_ERROR(err, MKS_ERR_TRADE_MANAGER_INVALID_PARAM,
                       "partial params fora do range (0,100) ou trigger<=0",
                       StringFormat("trig=%.4f pct=%.4f",
                                    m_params.partialTriggerPoints,
                                    m_params.partialClosePct));
         return false;
      }
      return true;
   }

   // Vincula uma posicao recem-aberta ao manager. Reseta estado de gestao.
   void Attach(ulong positionId, ENUM_MKS_ORDER_SIDE side,
               double entryPrice, double lots,
               double initialSl, double initialTp)
   {
      m_attached    = true;
      m_positionId  = positionId;
      m_side        = side;
      m_entryPrice  = entryPrice;
      m_initialLots = lots;
      m_initialTp   = initialTp;
      m_currentSl   = initialSl;
      m_beApplied   = false;
      m_trailActive = false;
      m_partialDone = false;
      m_partialFilledLots = 0.0;
   }

   // Desvincula sem ação de broker. Usado em fechamento externo
   // (SL/TP hit) ou em desligamento gracioso do EA.
   void Detach()
   {
      m_attached = false;
   }

   //--- Estado --------------------------------------------------------+

   bool   IsAttached()  const { return m_attached; }
   bool   IsBeApplied() const { return m_beApplied; }
   bool   IsTrailing()  const { return m_trailActive; }
   bool   IsPartialDone() const { return m_partialDone; }
   double PartialFilledLots() const { return m_partialFilledLots; }
   double CurrentSl()   const { return m_currentSl; }
   ulong  PositionId()  const { return m_positionId; }

   // Avalia gestao da posicao no tick corrente. Ordem fixa:
   //   1. BE (se elegivel e nao aplicado)
   //   2. Partial (se elegivel e nao executada)
   //   3. Trail (se elegivel; pode mover SL alem do BE)
   //
   // Retorna struct com transicoes detectadas. Idempotente: chamar
   // duas vezes com o mesmo tick nao re-aplica BE/partial.
   MksTradeManagerStep Update(const MksTick &tick)
   {
      MksTradeManagerStep step;
      if(!m_attached) return step;

      // Auto-detach: se book foi injetado e posição sumiu (SL/TP hit,
      // close manual, auto-close do broker simulado), zera o vínculo
      // e retorna sem chamar broker. Evita Modify/Close em positionId
      // fantasma.
      if(m_book != NULL && !m_book.IsOpen(m_positionId))
      {
         ulong closedId = m_positionId;
         m_attached = false;
         step.autoDetached = true;
         LogInfo("auto-detach: posição fechada externamente",
                 StringFormat("\"pid\":%I64u", closedId));
         return step;
      }

      double profit = ProfitPoints(tick);

      // 1. Break-even
      if(m_params.beEnabled && !m_beApplied
         && profit >= m_params.beActivationPoints)
      {
         double newSl = BreakEvenSlPrice();
         if(m_broker.Modify(m_positionId, newSl, m_initialTp))
         {
            m_currentSl = newSl;
            m_beApplied = true;
            step.beApplied = true;
            step.brokerCalls++;
            LogInfo("BE aplicado",
                    StringFormat("\"pid\":%I64u,\"sl\":%.5f", m_positionId, newSl));
         }
         else
         {
            LogWarn("broker.Modify falhou em BE",
                    StringFormat("\"pid\":%I64u,\"sl\":%.5f", m_positionId, newSl));
         }
      }

      // 2. Partial close — fecha um volume-ALVO (target = lots iniciais·pct)
      //    UMA vez. Fill parcial (MKS_EXEC_PARTIAL) é PROGRESSO, não falha:
      //    acumula o r.filledLots e re-emite só o RESIDUAL (target − acumulado)
      //    no próximo tick elegível, até o alvo ser atingido. Sem isso, um
      //    PARTIAL deixaria m_partialDone=false e o próximo tick re-fecharia
      //    o target INTEIRO sobre o residual (over-close). ADR-035 / E5.2.
      //    Zero-fill num status "ok" (broker degenerado) cai no ramo de WARN
      //    — evita acumular nada e reprocessa no próximo tick.
      if(m_params.partialEnabled && !m_partialDone
         && profit >= m_params.partialTriggerPoints)
      {
         const double lotEps = 1e-9;
         double targetLots    = m_initialLots * m_params.partialClosePct / 100.0;
         double remainingLots = targetLots - m_partialFilledLots;
         if(remainingLots > lotEps)
         {
            MksExecutionResult r = m_broker.Close(m_positionId, remainingLots);
            step.brokerCalls++;
            bool progressed = (r.status == MKS_EXEC_FILLED
                               || r.status == MKS_EXEC_PARTIAL)
                              && r.filledLots > lotEps;
            if(progressed)
            {
               m_partialFilledLots += r.filledLots;
               if(m_partialFilledLots >= targetLots - lotEps)
               {
                  m_partialDone    = true;
                  step.partialDone = true;
                  LogInfo("partial concluído",
                          StringFormat("\"pid\":%I64u,\"target\":%.4f,\"filled\":%.4f,\"pct\":%.2f",
                                       m_positionId, targetLots, m_partialFilledLots,
                                       m_params.partialClosePct));
               }
               else
               {
                  // Fill parcial: registra o progresso; o residual fica para
                  // o próximo tick elegível (NÃO re-fecha o target inteiro).
                  LogInfo("partial parcial — acumulando residual",
                          StringFormat("\"pid\":%I64u,\"filledNow\":%.4f,\"cum\":%.4f,\"target\":%.4f",
                                       m_positionId, r.filledLots,
                                       m_partialFilledLots, targetLots));
               }
            }
            else
            {
               LogWarn("broker.Close falhou/zero-fill em partial",
                       StringFormat("\"pid\":%I64u,\"lots\":%.4f,\"status\":%d,\"filled\":%.4f",
                                    m_positionId, remainingLots, (int)r.status,
                                    r.filledLots));
            }
         }
      }

      // 3. Trailing stop
      if(m_params.trailEnabled
         && profit >= m_params.trailStartPoints)
      {
         double newSl = TrailSlPrice(tick);
         if(TrailWouldImproveSl(newSl))
         {
            if(m_broker.Modify(m_positionId, newSl, m_initialTp))
            {
               m_currentSl = newSl;
               m_trailActive = true;
               step.trailUpdated = true;
               step.brokerCalls++;
               // Trail update é por tick — log INFO seria poluição.
               // Mantém em estado interno; auditoria via CurrentSl().
            }
            else
            {
               LogWarn("broker.Modify falhou em trail",
                       StringFormat("\"pid\":%I64u,\"sl\":%.5f", m_positionId, newSl));
            }
         }
      }

      return step;
   }
};

#endif // MKS_ULTIMATE_CORE_TRADE_CMKSTRADEMANAGER_MQH
