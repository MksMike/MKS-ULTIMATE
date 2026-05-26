//+------------------------------------------------------------------+
//| @file           : CMksRenkoBuilder.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / RenkoBuilder
//| @responsibility : Motor de construção de bricks Renko a partir de
//|                   ticks. Guarda ADR-006, formação ADR-010,
//|                   multi-threshold ADR-011.
//| @depends_on     : Core/Interfaces/IBrickSizer.mqh,
//|                   Core/Interfaces/IRenkoSink.mqh,
//|                   Core/Types/RenkoGeometry.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/RenkoBuilder/CMksRenkoBuilder.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_RENKOBUILDER_CMKSRENKOBUILDER_MQH
#define MKS_ULTIMATE_CORE_RENKOBUILDER_CMKSRENKOBUILDER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/FormingBrick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Motor de construção de bricks Renko (ADR-010). Consome ticks via
// IngestTick e emite bricks fechados via IRenkoSink::OnBrickClose.
// Implementa: guarda de validade do tick (ADR-006), preço-condutor mid
// (ADR-010 §4) e cruzamento multi-threshold (ADR-011).
//
// Modelo de threshold (decisão de implementação; ADR-010 não fixa fórmula):
// - Continuação: lastClose ± (1-PO)*S, no sentido do último brick.
// - Reversão:    lastClose ∓ (1-PRO)*S*revSizeRatio, sentido oposto.
// Consistente com classic (0.0,0.0,1.0) → S em ambos os lados e
// median (0.5,0.5,1.0) → 0.5*S em ambos os lados, simétricos. Producer
// usa classic em produção (ADR-026); median permanece no core para testes
// e para leitura de .mksbk antigos.

// Coração do framework — transforma stream de ticks em sequência
// determinística de bricks Renko. Caminho único entre live e replay.
class CMksRenkoBuilder
{
private:
   MksRenkoGeometry      m_geometry;
   IBrickSizer          *m_sizer;
   IRenkoSink           *m_sink;
   int                   m_invalidLimit;
   int                   m_thresholdLimit;
   int                   m_consecutiveInvalid;
   bool                  m_streamCorrupt;

   bool                  m_initialized;
   bool                  m_hasFirstBrick;
   double                m_lastClose;
   ENUM_MKS_BRICK_DIR    m_lastDirection;
   double                m_formingHigh;
   double                m_formingLow;
   double                m_lastMid;       // último mid observado (ADR-021 §5)
   bool                  m_emitForming;   // dispara OnBrickForming a cada tick (ADR-021)

   // Soft recovery de gap estrutural (ADR-011 nota 2026-05-26): N rejeições
   // K consecutivas com mids agrupados disparam reanchor de m_lastClose.
   // Distingue gap legítimo (mids agrupados longe de lastClose) de spike
   // isolado (1 tick outlier seguido de mids perto de lastClose).
   int                   m_kRecoverAfter;       // 0 = desabilitado; N = reanchor após N rejeições
   int                   m_kExceededRun;        // contador de rejeições consecutivas
   double                m_kFirstMid;           // primeiro mid rejeitado da janela atual

   // Próximo limiar de continuação na direção `dir`:
   //   base + sign · (1 - PO) · S
   // Em classic (PO=0), o limiar fica a S do close anterior; em median
   // (PO=0.5), fica a 0.5·S (bricks com 50% de sobreposição).
   double ContinuationThreshold(double base, ENUM_MKS_BRICK_DIR dir, double size) const
   {
      double sign = (dir == MKS_BRICK_BULL) ? 1.0 : -1.0;
      return base + sign * (1.0 - m_geometry.po) * size;
   }

   // Limiar de reversão (sentido oposto a `dir`):
   //   base + sign_oposto · (1 - PRO) · S · revSizeRatio
   // Em classic (PRO=0, revSizeRatio=1), reversão a S do close anterior.
   // O `revSizeRatio` permite presets com brick de reversão de tamanho
   // diferente do de continuação (não usado em produção atualmente).
   double ReversalThreshold(double base, ENUM_MKS_BRICK_DIR dir, double size) const
   {
      double sign = (dir == MKS_BRICK_BULL) ? -1.0 : 1.0;
      return base + sign * (1.0 - m_geometry.pro) * size * m_geometry.revSizeRatio;
   }

   // Soft recovery: decide se deve reanchorar lastClose após M>K e
   // preenche err. Retorna true se recuperou (caller deve emitir warning
   // 105 e seguir vivo), false se foi rejeição 102 padrão.
   bool HandleKExceeded(int M, double mid, ulong seq, double size, MksError &err)
   {
      m_kExceededRun++;
      if(m_kExceededRun == 1)
         m_kFirstMid = mid;

      // Reanchor só se: recovery habilitado, atingiu N consecutivas, e
      // mids estão agrupados (variância ≤ size — gap legítimo, não spike).
      bool gapDetected =
         (m_kRecoverAfter > 0)
         && (m_kExceededRun >= m_kRecoverAfter)
         && (MathAbs(mid - m_kFirstMid) <= size);

      if(gapDetected)
      {
         // Reanchora como se fosse o primeiro tick após init: próximo
         // movimento define direção via primeiro brick (sem reversão).
         m_lastClose = mid;
         m_formingHigh = mid;
         m_formingLow = mid;
         m_hasFirstBrick = false;
         m_kExceededRun = 0;
         MKS_SET_ERROR(err, MKS_ERR_RENKO_RECOVERED_FROM_GAP,
                       "gap estrutural detectado — reanchor de m_lastClose",
                       StringFormat("run=%d M=%d K=%d seq=%I64u mid=%.5f",
                                    m_kRecoverAfter, M, m_thresholdLimit,
                                    seq, mid));
         return true;
      }

      MKS_SET_ERROR(err, MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED,
                    "cruzamento acima do limiar K — não emitido",
                    StringFormat("M=%d K=%d seq=%I64u mid=%.5f run=%d",
                                 M, m_thresholdLimit, seq, mid, m_kExceededRun));
      return false;
   }

   void EmitBrick(double open, double close, ENUM_MKS_BRICK_DIR dir,
                  int M, double triggerPrice, ulong triggerTickId, long closeTimeMsc)
   {
      MksBrick brick;
      brick.open = open;
      brick.close = close;
      brick.direction = dir;
      brick.thresholdsCrossed = M;
      brick.triggerPrice = triggerPrice;
      brick.triggerTickId = triggerTickId;
      brick.closeTimeMsc = closeTimeMsc;
      brick.high = MathMax(MathMax(open, close), m_formingHigh);
      brick.low  = MathMin(MathMin(open, close), m_formingLow);
      brick.volume = 0; // agregação por brick não é tratada nesta fatia
      if(m_sink != NULL)
         m_sink.OnBrickClose(brick);
      // ADR-018 §2: sizer recebe cada brick fechado para atualizar estado
      // (ATR sobre bricks). Sizers constantes implementam como no-op.
      if(m_sizer != NULL)
         m_sizer.OnBrick(brick);
   }

public:
   // L = 10: tolera glitch transiente sem mascarar feed sustentadamente quebrado (ADR-006 §5).
   // K = 20: tolera spikes plausíveis de XAUUSD em baixa liquidez; corta cruzamentos de
   //         magnitude impossível em um único tick (ADR-011 §4).
   // kRecoverAfter = 5: após 5 rejeições K consecutivas com mids agrupados
   //         (variância ≤ S), reconhece gap legítimo e reanchora m_lastClose.
   //         0 desabilita (comportamento legado, builder pode travar em gap
   //         maior que K·(1-PO)·S). Ver ADR-011 nota 2026-05-26.
   CMksRenkoBuilder(const MksRenkoGeometry &geometry,
                    IBrickSizer *sizer,
                    IRenkoSink  *sink,
                    int invalidLimit = 10,
                    int thresholdLimit = 20,
                    int kRecoverAfter = 5)
   {
      m_geometry = geometry;
      m_sizer = sizer;
      m_sink = sink;
      m_invalidLimit = invalidLimit;
      m_thresholdLimit = thresholdLimit;
      m_consecutiveInvalid = 0;
      m_streamCorrupt = false;
      m_initialized = false;
      m_hasFirstBrick = false;
      m_lastClose = 0.0;
      m_lastDirection = MKS_BRICK_BULL; // valor inerte até m_hasFirstBrick = true
      m_formingHigh = 0.0;
      m_formingLow = 0.0;
      m_lastMid = 0.0;
      m_emitForming = true;
      m_kRecoverAfter = kRecoverAfter;
      m_kExceededRun = 0;
      m_kFirstMid = 0.0;
   }

   // Liga/desliga emissão de OnBrickForming a cada tick (ADR-021). Usado
   // pelo composition root para suprimir o broadcast durante fill
   // histórico em massa (evita milhões de CustomRatesUpdate por brick
   // em formação, travando o terminal).
   void SetEmitForming(bool v) { m_emitForming = v; }
   bool EmitForming() const    { return m_emitForming; }

private:
   void EmitFormingIfEnabled()
   {
      if(m_emitForming && m_sink != NULL && m_initialized)
         m_sink.OnBrickForming(GetFormingBrick());
   }

public:

   bool IngestTick(const MksTick &tick, MksError &err)
   {
      if(m_streamCorrupt)
      {
         MKS_SET_ERROR(err, MKS_ERR_RENKO_TICK_STREAM_CORRUPT,
                       "builder interrompido por feed corrupto",
                       StringFormat("invalidLimit=%d", m_invalidLimit));
         return false;
      }

      if(!tick.IsValid())
      {
         m_consecutiveInvalid++;
         if(m_consecutiveInvalid >= m_invalidLimit)
         {
            m_streamCorrupt = true;
            MKS_SET_ERROR(err, MKS_ERR_RENKO_TICK_STREAM_CORRUPT,
                          "L ticks inválidos consecutivos — feed corrupto",
                          StringFormat("invalidLimit=%d seq=%I64u",
                                       m_invalidLimit, tick.seq));
            return false;
         }
         MKS_SET_ERROR(err, MKS_ERR_RENKO_INVALID_TICK,
                       "tick reprovado por IsValid()",
                       StringFormat("seq=%I64u bid=%.5f ask=%.5f",
                                    tick.seq, tick.bid, tick.ask));
         return false;
      }

      m_consecutiveInvalid = 0;
      double mid = (tick.bid + tick.ask) / 2.0; // ADR-010 §4
      m_lastMid = mid;                          // ADR-021 §5

      if(!m_initialized)
      {
         m_initialized = true;
         m_lastClose = mid;
         m_formingHigh = mid;
         m_formingLow = mid;
         EmitFormingIfEnabled();
         return true;
      }

      if(m_sizer == NULL || !m_sizer.IsReady())
      {
         if(mid > m_formingHigh) m_formingHigh = mid;
         if(mid < m_formingLow)  m_formingLow  = mid;
         EmitFormingIfEnabled();
         return true;
      }

      double size = m_sizer.SizePoints();
      if(size <= 0.0)
      {
         if(mid > m_formingHigh) m_formingHigh = mid;
         if(mid < m_formingLow)  m_formingLow  = mid;
         EmitFormingIfEnabled();
         return true;
      }

      // Caminha a escada de thresholds (ADR-011 §3).
      // Igualdade exata (mid == threshold) conta como cruzamento — decisão
      // de implementação determinística (ticks de XAUUSD em pontos
      // raramente caem exatos num threshold; o critério é estável).
      int M = 0;
      double walkClose = m_lastClose;
      ENUM_MKS_BRICK_DIR walkDirection;

      if(!m_hasFirstBrick)
      {
         // Primeiro brick: sem continuação/reversão — direção fixada pelo
         // sinal do movimento de mid relativo a m_lastClose.
         // Ver ADR-011, nota de esclarecimento — geometria do primeiro brick.
         if(mid == m_lastClose)
         {
            if(mid > m_formingHigh) m_formingHigh = mid;
            if(mid < m_formingLow)  m_formingLow  = mid;
            EmitFormingIfEnabled();
            return true;
         }
         walkDirection = (mid > m_lastClose) ? MKS_BRICK_BULL : MKS_BRICK_BEAR;

         while(true)
         {
            double contThr = ContinuationThreshold(walkClose, walkDirection, size);
            bool crossed = (walkDirection == MKS_BRICK_BULL)
                              ? (mid >= contThr)
                              : (mid <= contThr);
            if(!crossed) break;
            M++;
            walkClose = contThr;
            if(M > m_thresholdLimit) // ADR-011 §4
            {
               HandleKExceeded(M, mid, tick.seq, size, err);
               return false;
            }
         }
      }
      else
      {
         walkDirection = m_lastDirection;
         while(true)
         {
            double contThr = ContinuationThreshold(walkClose, walkDirection, size);
            double revThr  = ReversalThreshold(walkClose, walkDirection, size);
            bool crossedCont = false;
            bool crossedRev  = false;
            if(walkDirection == MKS_BRICK_BULL)
            {
               crossedCont = (mid >= contThr);
               crossedRev  = (mid <= revThr);
            }
            else
            {
               crossedCont = (mid <= contThr);
               crossedRev  = (mid >= revThr);
            }

            if(crossedCont)
            {
               M++;
               walkClose = contThr;
            }
            else if(crossedRev)
            {
               M++;
               walkClose = revThr;
               walkDirection = (walkDirection == MKS_BRICK_BULL) ? MKS_BRICK_BEAR : MKS_BRICK_BULL;
            }
            else
            {
               break;
            }

            if(M > m_thresholdLimit) // ADR-011 §4
            {
               HandleKExceeded(M, mid, tick.seq, size, err);
               return false;
            }
         }
      }

      // Reset do run de K-exceeded em qualquer tick aceito (com ou sem
      // brick emitido). Quebra a sequência de rejeições — gap legítimo
      // exige N consecutivas com mids agrupados, intercaladas com
      // sucesso resetam o estado.
      m_kExceededRun = 0;

      if(M >= 1)
      {
         EmitBrick(m_lastClose, walkClose, walkDirection,
                   M, mid, tick.seq, tick.timeMsc);
         m_lastClose = walkClose;
         m_lastDirection = walkDirection;
         m_hasFirstBrick = true;
         // Reset cobre o overshoot: próximo brick abre em walkClose; mid
         // ficou além (ou igual a) walkClose. Garante invariante
         // m_formingLow <= m_lastClose <= m_formingHigh.
         m_formingHigh = MathMax(walkClose, mid);
         m_formingLow  = MathMin(walkClose, mid);
         EmitFormingIfEnabled();
         return true;
      }

      // Nenhum threshold cruzado — atualiza extremos do brick em formação.
      if(mid > m_formingHigh) m_formingHigh = mid;
      if(mid < m_formingLow)  m_formingLow  = mid;
      EmitFormingIfEnabled();
      return true;
   }

   // true após L ticks inválidos consecutivos terem disparado 104.
   // Sink/EA pode consultar para decidir se ainda confia no feed (ADR-006 §5).
   bool IsStreamCorrupt() const { return m_streamCorrupt; }

   // Snapshot do brick em formação (ADR-010 §6). Não emite evento;
   // chamador consulta sob demanda. Antes do primeiro tick válido,
   // o snapshot retorna com hasData = false.
   MksFormingBrick GetFormingBrick() const
   {
      MksFormingBrick fb;
      if(!m_initialized)
         return fb;
      fb.open = m_lastClose;
      fb.high = m_formingHigh;
      fb.low = m_formingLow;
      fb.currentMid = m_lastMid;   // ADR-021 §5
      fb.direction = m_lastDirection;
      fb.hasData = true;
      return fb;
   }
};

#endif // MKS_ULTIMATE_CORE_RENKOBUILDER_CMKSRENKOBUILDER_MQH
