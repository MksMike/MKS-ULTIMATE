//+------------------------------------------------------------------+
//| @file           : CMksRenkoBuilder.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / RenkoBuilder
//| @responsibility : Motor de construção de bricks Renko a partir de
//|                   ticks. Fatia 1: esqueleto + guarda de ingestão
//|                   (ADR-006). Formação de brick em fatias futuras.
//| @depends_on     : Core/Interfaces/IBrickSizer.mqh,
//|                   Core/Types/RenkoGeometry.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/RenkoBuilder/CMksRenkoBuilder.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_RENKOBUILDER_CMKSRENKOBUILDER_MQH
#define MKS_ULTIMATE_CORE_RENKOBUILDER_CMKSRENKOBUILDER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Motor de construção de bricks Renko (ADR-010). Esta fatia (1 de 4)
// entrega o esqueleto da classe e a guarda de validade do tick na
// ingestão (ADR-006). Formação de brick, cruzamento multi-threshold
// (ADR-011) e despacho a IRenkoSink ficam para as fatias seguintes.
class CMksRenkoBuilder
{
private:
   MksRenkoGeometry m_geometry;
   IBrickSizer     *m_sizer;
   int              m_invalidLimit;        // L da ADR-006 §5
   int              m_consecutiveInvalid;
   bool             m_streamCorrupt;

public:
   // L default = 10: tolera glitch transiente sem mascarar feed sustentadamente quebrado.
   CMksRenkoBuilder(const MksRenkoGeometry &geometry,
                    IBrickSizer *sizer,
                    int invalidLimit = 10)
   {
      m_geometry = geometry;
      m_sizer = sizer;
      m_invalidLimit = invalidLimit;
      m_consecutiveInvalid = 0;
      m_streamCorrupt = false;
   }

   // Ingere um tick (ADR-006). Tick válido: contador zera, retorna true
   // (formação de brick é fatia 2). Tick inválido: descartado, contador
   // incrementa, retorna false com MKS_ERR_RENKO_INVALID_TICK. L inválidos
   // consecutivos: builder entra em estado interrompido e retorna false
   // com MKS_ERR_RENKO_TICK_STREAM_CORRUPT em toda chamada subsequente.
   bool IngestTick(const MksTick &tick, MksError &err)
   {
      if(m_streamCorrupt)
      {
         MKS_SET_ERROR(err, MKS_ERR_RENKO_TICK_STREAM_CORRUPT,
                       "builder interrompido por feed corrupto",
                       StringFormat("invalidLimit=%d", m_invalidLimit));
         return false;
      }

      if(tick.IsValid())
      {
         m_consecutiveInvalid = 0;
         return true;
      }

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
};

#endif // MKS_ULTIMATE_CORE_RENKOBUILDER_CMKSRENKOBUILDER_MQH
