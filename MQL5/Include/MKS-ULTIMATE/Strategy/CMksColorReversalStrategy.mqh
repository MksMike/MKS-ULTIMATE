//+------------------------------------------------------------------+
//| @file           : CMksColorReversalStrategy.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Strategy
//| @responsibility : Estratégia minimalista da Fase 9 — "reversão de
//|                   cor pura". Implementa IRenkoSink. Em cada flip
//|                   de direção de brick (BULL→BEAR ou inverso): fecha
//|                   posição corrente (se houver) e abre nova posição
//|                   na direção da nova cor. SL fixo em pontos. Sem TP
//|                   (saída só por flip seguinte ou SL hit). Magic
//|                   próprio para coexistir com outras estratégias.
//|                   Auto-detach: consulta IPositionBook a cada brick
//|                   antes de decidir; se posição "atual" sumiu do
//|                   broker, zera estado interno. Reconciliação de
//|                   restart: AdoptPosition religa órfã de sessão
//|                   anterior; FlattenForSafety fecha a posição fora
//|                   do fluxo de flip (halt de stream, M19).
//|                   ROADMAP Fase 9. Estratégia deliberadamente simples
//|                   — alvo é exercitar todas as peças do core, não ser
//|                   lucrativa.
//| @depends_on     : Core/Interfaces/IRenkoSink.mqh,
//|                   Core/Interfaces/IBroker.mqh,
//|                   Core/Interfaces/IPositionSizer.mqh,
//|                   Core/Interfaces/IPositionBook.mqh,
//|                   Core/Interfaces/ISymbol.mqh,
//|                   Core/Interfaces/ILogger.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/FormingBrick.mqh,
//|                   Core/Types/OrderRequest.mqh,
//|                   Core/Types/ExecutionResult.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Strategy/CMksColorReversalStrategy.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_STRATEGY_CMKSCOLORREVERSALSTRATEGY_MQH
#define MKS_ULTIMATE_STRATEGY_CMKSCOLORREVERSALSTRATEGY_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IPositionSizer.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IPositionBook.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ITradeVisualizer.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ILogger.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/FormingBrick.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>

// Métricas agregadas para auditoria de execução. Acessíveis via getter.
struct CMksColorReversalMetrics
{
   long bricksSeen;             // total de OnBrickClose recebidos
   long flipsDetected;          // mudanças de direção brick→brick
   long sendsAttempted;         // tentativas de abrir posição
   long sendsFilled;            // abertas com sucesso (broker retornou FILLED)
   long sendsRejected;          // rejeitadas (risk gate ou broker)
   long closesAttempted;        // tentativas de fechar posição existente
   long closesFilled;
   long closesRejected;
   long autoDetected;           // detecções de auto-close externo (book)

   CMksColorReversalMetrics()
   {
      bricksSeen      = 0;
      flipsDetected   = 0;
      sendsAttempted  = 0;
      sendsFilled     = 0;
      sendsRejected   = 0;
      closesAttempted = 0;
      closesFilled    = 0;
      closesRejected  = 0;
      autoDetected    = 0;
   }
};

// CMksColorReversalStrategy — IRenkoSink que toma decisões em cada brick.
//
// Lógica em OnBrickClose:
//   1. Se book != NULL e currentPositionId != 0 e !book.IsOpen(currentId):
//      detecta auto-close externo (SL hit do broker, manual close, etc).
//      Zera currentPositionId. Métrica autoDetected++.
//   2. Se !hasLastBrick: registra direção e retorna (sem ação).
//   3. Se brick.direction == lastBrickDir: sem flip. Atualiza lastBrickDir
//      (idempotente) e retorna.
//   4. FLIP detectado:
//      a. Se currentPositionId != 0: broker.Close(currentId, fullLots).
//         Sucesso ou falha, currentPositionId é zerado (Phase 9 simplista:
//         falha de close é responsabilidade do risk operacional, não
//         da estratégia bloquear nova entrada).
//      b. Calcula lots via sizer.ComputeLots(slPoints).
//      c. side = (brick.direction == BULL) ? BUY : SELL.
//      d. request com slPoints fixo, tpPoints=0, comment="ColorReversal".
//      e. broker.Send(request). Se FILLED: registra novo positionId.
//   5. Atualiza lastBrickDir.
//
// Determinismo: estratégia tem estado interno mas não usa RNG. Mesma
// sequência de bricks + mesmo broker → mesma sequência de Send/Close.
// Paridade entre backtest e live é prerrogativa do composition root
// (mesmo broker mock, mesmo símbolo, mesmo clock). Estratégia em si
// é função pura do stream de bricks.
class CMksColorReversalStrategy : public IRenkoSink
{
private:
   IBroker          *m_broker;
   IPositionSizer   *m_sizer;
   IPositionBook    *m_book;        // opcional — habilita auto-detach
   ITradeVisualizer *m_visualizer;  // opcional — desenha entradas/saídas (ADR-028)
   ISymbol          *m_symbol;
   ILogger          *m_logger;
   double            m_slPoints;
   long              m_magic;

   // Estado da estratégia
   bool                  m_hasLastBrick;
   ENUM_MKS_BRICK_DIR    m_lastBrickDir;
   ulong                 m_currentPositionId;
   ENUM_MKS_ORDER_SIDE   m_currentSide;
   double                m_currentLots;
   bool                  m_warmup;   // true durante fill histórico — rastreia
                                     // direção mas NÃO opera (sem Send/Close)

   // Métricas
   CMksColorReversalMetrics m_metrics;

   void LogInfo(const string &msg, const string &ctx)
   {
      if(m_logger == NULL) return;
      m_logger.Log(MKS_LOG_INFO, "ColorReversal", msg, ctx);
   }

   void LogWarn(const string &msg, const string &ctx)
   {
      if(m_logger == NULL) return;
      m_logger.Log(MKS_LOG_WARN, "ColorReversal", msg, ctx);
   }

   // Detecta auto-close externo via book. Se nossa state diz "tenho
   // posição X" mas book diz "X não está aberta", reconhece que o
   // broker fechou externamente (SL hit, manual close, etc) e zera
   // o vínculo interno. Marca a saída na visualização no tempo do brick
   // que detectou o fechamento (aproximação — preço exato do SL não é
   // conhecido aqui; usa triggerPrice do brick).
   void CheckAutoCloseExternal(const MksBrick &brick)
   {
      if(m_book == NULL) return;
      if(m_currentPositionId == 0) return;
      if(m_book.IsOpen(m_currentPositionId)) return;

      ulong closedId = m_currentPositionId;
      if(m_visualizer != NULL)
         m_visualizer.MarkExit(brick.closeTimeMsc, brick.triggerPrice, closedId);
      m_currentPositionId = 0;
      m_currentLots       = 0.0;
      m_metrics.autoDetected++;
      LogInfo("auto-close externo detectado",
              StringFormat("\"pid\":%I64u", closedId));
   }

   // Fecha posição corrente, se houver. Best-effort: limpa state
   // interno mesmo se Close falhar (Fase 9 simplista). Retorna true
   // se houve close bem-sucedido, false caso contrário. Marca a saída
   // na visualização no tempo do brick do flip.
   bool CloseCurrentIfAny(const MksBrick &brick)
   {
      if(m_currentPositionId == 0) return false;
      m_metrics.closesAttempted++;
      ulong closingId = m_currentPositionId;
      MksExecutionResult r = m_broker.Close(m_currentPositionId, m_currentLots);
      bool ok = (r.status == MKS_EXEC_FILLED);
      if(ok)
      {
         m_metrics.closesFilled++;
         if(m_visualizer != NULL)
            m_visualizer.MarkExit(brick.closeTimeMsc, r.fillPrice, closingId);
         LogInfo("posição fechada (flip)",
                 StringFormat("\"pid\":%I64u,\"price\":%.5f,\"lots\":%.4f",
                              m_currentPositionId, r.fillPrice, r.filledLots));
      }
      else
      {
         m_metrics.closesRejected++;
         LogWarn("Close falhou em flip — limpando state internamente",
                 StringFormat("\"pid\":%I64u,\"status\":%d,\"retcode\":%d",
                              m_currentPositionId, (int)r.status, r.brokerRetcode));
      }
      m_currentPositionId = 0;
      m_currentLots       = 0.0;
      return ok;
   }

   // Abre nova posição na direção do brick recém-flippado. Side é
   // direto da cor: BULL → BUY, BEAR → SELL.
   void OpenNewInDirection(ENUM_MKS_BRICK_DIR brickDir, const MksBrick &triggerBrick)
   {
      if(m_broker == NULL || m_sizer == NULL || m_symbol == NULL) return;

      double lots = 0.0;
      MksError sizerErr;
      if(!m_sizer.ComputeLots(m_slPoints, lots, sizerErr))
      {
         LogWarn("sizer falhou — sem entrada",
                 StringFormat("\"err\":\"%s\"", sizerErr.ToString()));
         return;
      }
      if(lots <= 0.0)
      {
         LogWarn("sizer retornou lots <= 0 — sem entrada",
                 StringFormat("\"lots\":%.6f", lots));
         return;
      }

      MksOrderRequest req;
      req.side     = (brickDir == MKS_BRICK_BULL) ? MKS_ORDER_BUY : MKS_ORDER_SELL;
      req.lots     = lots;
      req.slPoints = m_slPoints;
      req.tpPoints = 0.0;  // sem TP por design
      req.comment  = "ColorReversal";

      m_metrics.sendsAttempted++;
      MksExecutionResult r = m_broker.Send(req);
      if(r.status == MKS_EXEC_FILLED)
      {
         m_metrics.sendsFilled++;
         m_currentPositionId = r.positionId;
         m_currentSide       = req.side;
         m_currentLots       = r.filledLots;
         if(m_visualizer != NULL)
            m_visualizer.MarkEntry(triggerBrick.closeTimeMsc, req.side,
                                    r.fillPrice, r.positionId);
         LogInfo("posição aberta (flip)",
                 StringFormat("\"pid\":%I64u,\"side\":%s,\"price\":%.5f,\"lots\":%.4f,"
                              "\"slPts\":%.2f,\"triggerBrickId\":%I64u",
                              r.positionId,
                              (req.side == MKS_ORDER_BUY ? "BUY" : "SELL"),
                              r.fillPrice, r.filledLots, m_slPoints,
                              triggerBrick.triggerTickId));
      }
      else
      {
         m_metrics.sendsRejected++;
         LogWarn("Send rejeitada",
                 StringFormat("\"status\":%d,\"retcode\":%d", (int)r.status, r.brokerRetcode));
      }
   }

public:
   // broker, sizer e symbol obrigatórios. book/logger opcionais (book
   // habilita auto-detach; logger habilita audit). slPoints = distância
   // do SL em pontos do símbolo. magic identifica trades desta estratégia.
   CMksColorReversalStrategy(IBroker          *broker,
                             IPositionSizer   *sizer,
                             ISymbol          *symbol,
                             double            slPoints,
                             long              magic,
                             ILogger          *logger     = NULL,
                             IPositionBook    *book       = NULL,
                             ITradeVisualizer *visualizer = NULL)
   {
      m_broker     = broker;
      m_sizer      = sizer;
      m_book       = book;
      m_visualizer = visualizer;
      m_symbol     = symbol;
      m_logger     = logger;
      m_slPoints   = slPoints;
      m_magic      = magic;

      m_hasLastBrick      = false;
      m_lastBrickDir      = MKS_BRICK_BULL; // inerte até hasLastBrick
      m_currentPositionId = 0;
      m_currentSide       = MKS_ORDER_BUY;
      m_currentLots       = 0.0;
      m_warmup            = false;
   }

   // Liga/desliga o modo warm-up. Durante warm-up (fill histórico), o
   // OnBrickClose rastreia a direção dos bricks mas NÃO abre/fecha
   // posições — senão a estratégia "operaria" sobre bricks do passado.
   // Composition root chama SetWarmup(true) antes do fill, SetWarmup(false)
   // depois. A direção do último brick histórico fica registrada, então o
   // primeiro flip live decide corretamente.
   void SetWarmup(bool v) { m_warmup = v; }
   bool IsWarmup() const  { return m_warmup; }

   // Adota posição deixada aberta por sessão anterior (mesmo symbol+
   // magic). Restaura o vínculo interno como se esta instância a
   // tivesse aberto: flips futuros a fecham, auto-detach a monitora.
   // Sem adoção, a órfã nunca é gerenciada e, com maxOpenPositions=1,
   // bloqueia todo Send novo via 405 — EA mudo até o SL bater.
   // Chamada pelo composition root no OnInit (M10, auditoria
   // 2026-07-19 — invariante 5 do V5-POSTMORTEM aplicado a posições:
   // reconstrução de estado é completa ou não acontece).
   void AdoptPosition(const ulong positionId, const ENUM_MKS_ORDER_SIDE side,
                      const double lots)
   {
      m_currentPositionId = positionId;
      m_currentSide       = side;
      m_currentLots       = lots;
      LogWarn("posição órfã adotada",
              StringFormat("\"pid\":%I64u,\"side\":\"%s\",\"lots\":%.4f",
                           positionId,
                           (side == MKS_ORDER_BUY ? "BUY" : "SELL"), lots));
   }

   // Fecha imediatamente a posição corrente, fora do fluxo de flip.
   // Usada pelo composition root quando o stream halta (M19): EA cego
   // não gerencia posição, e segurá-la só com o SL distante é risco
   // silencioso. Diferente do CloseCurrentIfAny, MANTÉM o vínculo em
   // falha — não há entrada nova vindo, e auto-detach/operador ainda
   // precisam enxergar a posição. Sem marcador de visualização (não há
   // brick aqui); o log carrega o evento.
   // true = fechou (ou não havia posição); false = Close falhou.
   bool FlattenForSafety(const string &reason)
   {
      if(m_currentPositionId == 0) return true;
      m_metrics.closesAttempted++;
      ulong closingId = m_currentPositionId;
      MksExecutionResult r = m_broker.Close(m_currentPositionId, m_currentLots);
      if(r.status == MKS_EXEC_FILLED)
      {
         m_metrics.closesFilled++;
         m_currentPositionId = 0;
         m_currentLots       = 0.0;
         LogWarn("posição fechada por segurança (flatten)",
                 StringFormat("\"pid\":%I64u,\"price\":%.5f,\"reason\":\"%s\"",
                              closingId, r.fillPrice, reason));
         return true;
      }
      m_metrics.closesRejected++;
      LogWarn("flatten FALHOU — posição segue aberta",
              StringFormat("\"pid\":%I64u,\"status\":%d,\"retcode\":%d,\"reason\":\"%s\"",
                           closingId, (int)r.status, r.brokerRetcode, reason));
      return false;
   }

   //--- IRenkoSink overrides ---------------------------------------+

   virtual void OnBrickClose(const MksBrick &brick) override
   {
      m_metrics.bricksSeen++;

      // 1. Auto-detach externo (SL hit, manual close, etc).
      CheckAutoCloseExternal(brick);

      // 2. Primeiro brick: só registra direção.
      if(!m_hasLastBrick)
      {
         m_lastBrickDir = brick.direction;
         m_hasLastBrick = true;
         return;
      }

      // 3. Sem flip → sem ação.
      if(brick.direction == m_lastBrickDir)
      {
         m_lastBrickDir = brick.direction; // idempotente
         return;
      }

      // 4. FLIP. Durante warm-up (fill histórico), só rastreia a direção —
      // não opera sobre bricks do passado.
      if(m_warmup)
      {
         m_lastBrickDir = brick.direction;
         return;
      }

      // 5. FLIP live. Fecha + abre na nova direção.
      m_metrics.flipsDetected++;
      CloseCurrentIfAny(brick);
      OpenNewInDirection(brick.direction, brick);

      // 6. Atualiza última direção observada.
      m_lastBrickDir = brick.direction;
   }

   // Não usa bar parcial nesta versão. ADR-021 permite usar; estratégias
   // futuras com filtros de excursão podem implementar.
   virtual void OnBrickForming(const MksFormingBrick &fb) override { }

   //--- Inspeção / state público (testes + logging) ----------------+

   bool                  HasOpenPosition() const { return m_currentPositionId != 0; }
   ulong                 CurrentPositionId() const { return m_currentPositionId; }
   ENUM_MKS_ORDER_SIDE   CurrentSide()       const { return m_currentSide; }
   double                CurrentLots()       const { return m_currentLots; }
   bool                  HasLastBrick()      const { return m_hasLastBrick; }
   ENUM_MKS_BRICK_DIR    LastBrickDir()      const { return m_lastBrickDir; }

   CMksColorReversalMetrics Metrics() const { return m_metrics; }

   double SlPoints() const { return m_slPoints; }
   long   Magic()    const { return m_magic; }

   void ResetMetrics()
   {
      m_metrics = CMksColorReversalMetrics();
   }
};

#endif // MKS_ULTIMATE_STRATEGY_CMKSCOLORREVERSALSTRATEGY_MQH
