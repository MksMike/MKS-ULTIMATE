//+------------------------------------------------------------------+
//| @file           : CMksAtrBrickSizer.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / RenkoBuilder
//| @responsibility : Sizer dinâmico — tamanho do brick = ATR(N) *
//|                   multiplier, calculado sobre janela rolante de
//|                   bricks fechados via Wilder's smoothing. Implementa
//|                   IBrickSizer (ADR-010) e ADR-018.
//| @depends_on     : Core/Interfaces/IBrickSizer.mqh, Core/Types/Brick.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/RenkoBuilder/CMksAtrBrickSizer.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_RENKOBUILDER_CMKSATRBRICKSIZER_MQH
#define MKS_ULTIMATE_CORE_RENKOBUILDER_CMKSATRBRICKSIZER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Sizer dinâmico baseado em ATR sobre bricks fechados (ADR-018 §1).
//
// Funcionamento:
//   - SizePoints() retorna defaultSizePoints durante warm-up (primeiros N
//     bricks). Após acumular N bricks, retorna ATR_derived * multiplier,
//     com clamp em [minSizePoints, maxSizePoints].
//   - IsReady() retorna true SEMPRE — durante warm-up o fallback é o
//     default. Retornar false causaria deadlock: o builder não emite
//     enquanto !IsReady (CMksRenkoBuilder.mqh §IngestTick), e sem
//     emissão o sizer nunca acumula bricks. ADR-018 §4.
//   - OnBrick(brick) é chamado pelo builder após cada EmitBrick (ADR-018
//     §2). Atualiza janela e recalcula ATR.
//   - Cadência: por brick (ADR-018 §3). Sem rate-limiting.
//
// Fórmula ATR (Wilder's smoothing, J. Welles Wilder 1978):
//   TR_n = max(high - low,
//              |high - prev_close|,
//              |low  - prev_close|)
//   ATR_n = (ATR_{n-1} * (N-1) + TR_n) / N
//
// Inicialização do ATR: SMA dos N primeiros TRs no fim do warm-up.
// Subsequente: smoothing Wilder.
class CMksAtrBrickSizer : public IBrickSizer
{
private:
   int    m_period;          // N — janela do ATR (ADR-018 §6, default 14)
   double m_multiplier;      // size = ATR * multiplier (default 0.5)
   double m_defaultSize;     // fallback durante warm-up
   double m_minSize;         // clamp inferior (0 = sem limite)
   double m_maxSize;         // clamp superior

   double m_currentSize;     // valor retornado por SizePoints()
   double m_atrValue;        // ATR atual (valor; só significa após warm-up)
   double m_prevClose;       // close do brick anterior — entrada de TR
   bool   m_hasPrevClose;
   int    m_bricksReceived;  // contador para detectar fim do warm-up
   double m_trSum;           // soma dos N primeiros TRs (SMA inicial)

   void UpdateCurrentSize()
   {
      double s = m_atrValue * m_multiplier;
      if(s < m_minSize) s = m_minSize;
      if(s > m_maxSize) s = m_maxSize;
      m_currentSize = s;
   }

public:
   // Defaults sugeridos na ADR-018 §6.
   CMksAtrBrickSizer(int    period       = 14,
                     double multiplier   = 0.5,
                     double defaultSize  = 3.0,
                     double minSize      = 0.0,
                     double maxSize      = 1.0e18)
   {
      m_period         = period;
      m_multiplier     = multiplier;
      m_defaultSize    = defaultSize;
      m_minSize        = minSize;
      m_maxSize        = maxSize;
      m_currentSize    = defaultSize;
      m_atrValue       = 0.0;
      m_prevClose      = 0.0;
      m_hasPrevClose   = false;
      m_bricksReceived = 0;
      m_trSum          = 0.0;
   }

   double SizePoints() const override
   {
      return m_currentSize;
   }

   // ADR-018 §4: sempre ready. Builder espera m_sizer.IsReady() para
   // emitir; retornar false aqui mataria a alimentação.
   bool IsReady() const override { return true; }

   bool Validate(MksError &err) const override
   {
      if(m_period <= 0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RENKO_INVALID_BRICK_SIZE,
                       "atrPeriod deve ser > 0",
                       StringFormat("period=%d", m_period));
         return false;
      }
      if(m_multiplier <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RENKO_INVALID_BRICK_SIZE,
                       "multiplier deve ser > 0",
                       StringFormat("multiplier=%.4f", m_multiplier));
         return false;
      }
      if(m_defaultSize <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RENKO_INVALID_BRICK_SIZE,
                       "defaultSizePoints deve ser > 0",
                       StringFormat("defaultSize=%.4f", m_defaultSize));
         return false;
      }
      if(m_minSize < 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RENKO_INVALID_BRICK_SIZE,
                       "minSizePoints não pode ser negativo",
                       StringFormat("minSize=%.4f", m_minSize));
         return false;
      }
      if(m_minSize > m_maxSize)
      {
         MKS_SET_ERROR(err, MKS_ERR_RENKO_INVALID_BRICK_SIZE,
                       "minSize > maxSize",
                       StringFormat("min=%.4f max=%.4f",
                                    m_minSize, m_maxSize));
         return false;
      }
      return true;
   }

   void OnBrick(const MksBrick &brick) override
   {
      // True Range do brick atual.
      double tr;
      if(!m_hasPrevClose)
         tr = brick.high - brick.low;
      else
      {
         double r1 = brick.high - brick.low;
         double r2 = MathAbs(brick.high - m_prevClose);
         double r3 = MathAbs(brick.low  - m_prevClose);
         tr = MathMax(MathMax(r1, r2), r3);
      }
      m_prevClose    = brick.close;
      m_hasPrevClose = true;
      m_bricksReceived++;

      if(m_bricksReceived <= m_period)
      {
         // Warm-up: soma TRs para a SMA inicial. SizePoints continua
         // retornando defaultSize.
         m_trSum += tr;
         if(m_bricksReceived == m_period)
         {
            m_atrValue = m_trSum / m_period;
            UpdateCurrentSize();
         }
         return;
      }

      // Pós-warm-up: smoothing Wilder.
      m_atrValue = (m_atrValue * (m_period - 1) + tr) / m_period;
      UpdateCurrentSize();
   }

   //--- Observabilidade (testes, diagnóstico). Não fazem parte do
   //--- contrato IBrickSizer.
   double Atr()            const { return m_atrValue; }
   int    BricksReceived() const { return m_bricksReceived; }
   bool   IsWarmedUp()     const { return m_bricksReceived >= m_period; }
};

#endif // MKS_ULTIMATE_CORE_RENKOBUILDER_CMKSATRBRICKSIZER_MQH
