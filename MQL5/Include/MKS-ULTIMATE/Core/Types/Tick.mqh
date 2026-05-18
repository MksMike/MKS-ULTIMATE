//+------------------------------------------------------------------+
//| @file           : Tick.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Types
//| @responsibility : Estrutura MksTick — uma cotação bruta com seq como
//|                   fonte de verdade do determinismo do feed.
//| @depends_on     : Nenhuma (autocontido)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Types/Tick.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TYPES_TICK_MQH
#define MKS_ULTIMATE_CORE_TYPES_TICK_MQH

struct MksTick
{
   ulong  seq;        // ordem de chegada — fonte de verdade do determinismo
   long   timeMsc;    // timestamp do broker, ms desde epoch
   double bid;
   double ask;
   double last;       // 0 se o broker não popular; guardado fiel ao recebido
   long   volume;     // volume do tick — metadado, agregado no MksBrick (ADR-006)

   MksTick()
   {
      seq = 0; timeMsc = 0;
      bid = 0.0; ask = 0.0; last = 0.0;
      volume = 0;
   }

   datetime Time()    const { return (datetime)(timeMsc / 1000); }
   double   Spread()  const { return ask - bid; }
   bool     IsValid() const { return bid > 0.0 && ask > 0.0 && ask >= bid; }
};

#endif // MKS_ULTIMATE_CORE_TYPES_TICK_MQH
