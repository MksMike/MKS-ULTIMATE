//+------------------------------------------------------------------+
//| @file           : Brick.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Types
//| @responsibility : Estrutura MksBrick — brick Renko fechado, carregando
//|                   triggerPrice e triggerTickId para paridade.
//| @depends_on     : Nenhuma (autocontido)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Types/Brick.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TYPES_BRICK_MQH
#define MKS_ULTIMATE_CORE_TYPES_BRICK_MQH

enum ENUM_MKS_BRICK_DIR
{
   MKS_BRICK_BEAR = -1,
   MKS_BRICK_BULL =  1
};

struct MksBrick
{
   double open;
   double high;
   double low;
   double close;          // VALOR MATEMÁTICO (open ± brickSize).
                          // NÃO usar para decisão de preço — usar triggerPrice.

   ENUM_MKS_BRICK_DIR direction;

   double triggerPrice;   // mid do tick disparador (ADR-010 §5)
   ulong  triggerTickId;  // seq do MksTick disparador

   long   closeTimeMsc;   // timeMsc do tick disparador
   long   volume;         // volume agregado dos ticks; 0 é legítimo (ADR-006)
   int    thresholdsCrossed; // nº de thresholds cruzados; 1 = normal,
                             // >1 = brick multi-threshold (ADR-011)

   MksBrick()
   {
      open = 0.0; high = 0.0; low = 0.0; close = 0.0;
      direction = MKS_BRICK_BULL;
      triggerPrice = 0.0;
      triggerTickId = 0;
      closeTimeMsc = 0;
      volume = 0;
      thresholdsCrossed = 1;   // um brick cruza no mínimo um threshold
   }

   bool   IsBull()    const { return direction == MKS_BRICK_BULL; }
   bool   IsBear()    const { return direction == MKS_BRICK_BEAR; }
   double BodySize()  const { return MathAbs(close - open); }
   double Overshoot() const { return MathAbs(triggerPrice - close); }
};

#endif // MKS_ULTIMATE_CORE_TYPES_BRICK_MQH
