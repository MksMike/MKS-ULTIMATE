//+------------------------------------------------------------------+
//| @file           : IRenkoSink.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Interface IRenkoSink — consome eventos de brick
//|                   fechado (OnBrickClose) e, opcionalmente, eventos
//|                   de brick em formação a cada tick (OnBrickForming,
//|                   ADR-021).
//| @depends_on     : MksBrick (Core/Types/Brick.mqh),
//|                   MksFormingBrick (Core/Types/FormingBrick.mqh)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_IRENKOSINK_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_IRENKOSINK_MQH

#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/FormingBrick.mqh>

//--- Interface: consumidor de bricks (ADR-004).
class IRenkoSink
{
public:
   virtual ~IRenkoSink() {}

   // Chamado pelo RenkoBuilder quando um brick fecha (obrigatório).
   virtual void OnBrickClose(const MksBrick &brick) = 0;

   // Chamado pelo RenkoBuilder a cada tick válido após o processamento,
   // com o estado do brick atualmente em formação (ADR-021). Default
   // vazio: sinks que não precisam de render por tick ignoram. Apenas
   // sinks de visualização (CMksCustomSymbolSink) implementam.
   virtual void OnBrickForming(const MksFormingBrick &fb) {}
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_IRENKOSINK_MQH
