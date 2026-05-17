//+------------------------------------------------------------------+
//| @file           : IBroker.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Interface IBroker — execução de ordens, agnóstica
//|                   de implementação (MT5 real ou simulada).
//| @depends_on     : MksOrderRequest, MksExecutionResult (Core/Types/)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/IBroker.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_IBROKER_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_IBROKER_MQH

#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>

//--- Interface: execução de ordens no broker (ADR-004).
class IBroker
{
public:
   virtual ~IBroker() {}

   // Abre posição a mercado a partir da intenção da estratégia.
   virtual MksExecutionResult Send(const MksOrderRequest &request) = 0;

   // Fecha 'lots' da posição. lots = volume total -> fecha tudo;
   // lots < volume -> fechamento parcial.
   virtual MksExecutionResult Close(ulong positionId, double lots) = 0;

   // Move SL/TP de posição existente. Preço absoluto.
   virtual bool Modify(ulong positionId, double slPrice, double tpPrice) = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_IBROKER_MQH
