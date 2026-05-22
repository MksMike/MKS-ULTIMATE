//+------------------------------------------------------------------+
//| @file           : CMksMultiSink.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Output
//| @responsibility : Sink composto que delega OnBrickClose para
//|                   múltiplos IRenkoSink reais em ordem de
//|                   adição. Não possui os sinks — apenas os
//|                   referencia; o composition root é responsável
//|                   por deletar cada sink real.
//| @depends_on     : Core/Interfaces/IRenkoSink.mqh, Core/Types/Brick.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Output/CMksMultiSink.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_OUTPUT_CMKSMULTISINK_MQH
#define MKS_ULTIMATE_CORE_OUTPUT_CMKSMULTISINK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>

class CMksMultiSink : public IRenkoSink
{
public:
   IRenkoSink *sinks[];
   int         count;

   CMksMultiSink()
   {
      count = 0;
   }

   void Add(IRenkoSink *sink)
   {
      if(sink == NULL) return;
      ArrayResize(sinks, count + 1);
      sinks[count] = sink;
      count++;
   }

   void OnBrickClose(const MksBrick &brick) override
   {
      for(int i = 0; i < count; i++)
         if(sinks[i] != NULL)
            sinks[i].OnBrickClose(brick);
   }
};

#endif // MKS_ULTIMATE_CORE_OUTPUT_CMKSMULTISINK_MQH
