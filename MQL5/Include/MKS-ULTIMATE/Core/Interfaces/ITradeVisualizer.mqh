//+------------------------------------------------------------------+
//| @file           : ITradeVisualizer.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Interface ITradeVisualizer — canal de eventos de
//|                   trade para a camada de visualização (ADR-028).
//|                   A estratégia chama MarkEntry/MarkExit do próprio
//|                   fluxo de decisão, passando o tempo do brick que
//|                   disparou o trade. Implementações desenham chart
//|                   objects (setas, linhas). PURO OUTPUT — nunca lê
//|                   chart/CS, nunca alimenta decisão. Injeção opcional;
//|                   NULL = sem visualização, zero mudança de comportamento.
//| @depends_on     : Core/Types/OrderRequest.mqh (ENUM_MKS_ORDER_SIDE)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/ITradeVisualizer.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_ITRADEVISUALIZER_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_ITRADEVISUALIZER_MQH

#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>

//--- Interface: visualização de entradas/saídas de trade (ADR-004, ADR-028).
//
// Contrato de borda/output. A estratégia, ao abrir/fechar posição, chama
// estes métodos passando o `timeMsc` do brick que disparou o trade
// (`brick.closeTimeMsc` — já disponível no MksBrick). A implementação
// ancora os objetos visuais nesse tempo; com timeline híbrida (ADR-023),
// o MT5 encaixa na barra do brick correto.
//
// Paridade (ADR-028 §7): a visualização é observador passivo. Injetar
// NULL ou uma implementação real NÃO muda nenhuma decisão da estratégia
// — mesmo .mksbk byte-a-byte. Esta interface nunca retorna valor que a
// estratégia consuma.
class ITradeVisualizer
{
public:
   virtual ~ITradeVisualizer() {}

   // Posição aberta: desenha marcador de entrada em (timeMsc, price).
   // side = direção da posição. positionId identifica o trade para
   // ligar a saída correspondente.
   virtual void MarkEntry(long timeMsc, ENUM_MKS_ORDER_SIDE side,
                          double price, ulong positionId) = 0;

   // Posição fechada: desenha marcador de saída em (timeMsc, price) e,
   // se houver entrada registrada para positionId, a linha conectora
   // colorida por P&L.
   virtual void MarkExit(long timeMsc, double price, ulong positionId) = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_ITRADEVISUALIZER_MQH
