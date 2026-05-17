//+------------------------------------------------------------------+
//| @file           : IRenkoSink.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Interface IRenkoSink — consome eventos de brick
//|                   fechado emitidos pelo RenkoBuilder.
//| @depends_on     : MksBrick (Core/Types/Brick.mqh)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_IRENKOSINK_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_IRENKOSINK_MQH

#include <MKS-ULTIMATE/Core/Types/Brick.mqh>

//--- Interface: consumidor de bricks fechados (ADR-004).
class IRenkoSink
{
public:
   virtual ~IRenkoSink() {}

   // Chamado pelo RenkoBuilder quando um brick fecha.
   virtual void OnBrickClose(const MksBrick &brick) = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_IRENKOSINK_MQH
