//+------------------------------------------------------------------+
//| @file           : FormingBrick.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Types
//| @responsibility : Struct MksFormingBrick — estado do brick em
//|                   formação exposto pelo CMksRenkoBuilder (ADR-010 §6).
//| @depends_on     : Core/Types/Brick.mqh (ENUM_MKS_BRICK_DIR)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Types/FormingBrick.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TYPES_FORMINGBRICK_MQH
#define MKS_ULTIMATE_CORE_TYPES_FORMINGBRICK_MQH

#include <MKS-ULTIMATE/Core/Types/Brick.mqh>

// Estado do brick em formação. Tipo próprio (ADR-010 §6) — não reusa
// MksBrick, que é exclusivo de brick fechado por decisão da Fase 1.
// Obtido por getter do builder, ou propagado via IRenkoSink::OnBrickForming
// (ADR-021) para sinks que queiram render de bar parcial.
struct MksFormingBrick
{
   double open;          // = close do último brick fechado (ou mid inicial)
   double high;          // máximo mid observado desde a abertura
   double low;           // mínimo mid observado desde a abertura
   double currentMid;    // mid do último tick processado (ADR-021 §5)
   ENUM_MKS_BRICK_DIR direction;  // direção do último brick fechado
   bool   hasData;       // false antes da primeira ingestão pós-init

   MksFormingBrick()
   {
      open = 0.0; high = 0.0; low = 0.0; currentMid = 0.0;
      direction = MKS_BRICK_BULL;
      hasData = false;
   }
};

#endif // MKS_ULTIMATE_CORE_TYPES_FORMINGBRICK_MQH
