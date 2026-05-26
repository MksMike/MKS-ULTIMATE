//+------------------------------------------------------------------+
//| @file           : IPositionBook.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Interface IPositionBook — consulta de estado das
//|                   posições abertas no escopo configurado pela
//|                   implementação concreta (por símbolo, por magic,
//|                   por estratégia). Usada pelo CMksRiskManager para
//|                   checagens da camada "Por estratégia" (ADR-019).
//| @depends_on     : Nenhuma (tipos nativos)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/IPositionBook.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_IPOSITIONBOOK_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_IPOSITIONBOOK_MQH

//--- Interface: leitura de estado de posições (ADR-004).
//
// IBroker.Send/Close/Modify executa; IPositionBook consulta. Separação
// proposital: o Risk Manager precisa contar/somar para decidir, sem
// poder executar. Implementações concretas escolhem o escopo
// (símbolo, magic, estratégia) — a interface não fixa filtro.
class IPositionBook
{
public:
   virtual ~IPositionBook() {}

   // Quantidade de posições atualmente abertas no escopo deste book.
   virtual int OpenCount() const = 0;

   // Soma dos lots das posições abertas. Proxy de exposure em volume
   // para o slice 6.2; exposure ponderada por risco (lots × pip × SL)
   // pode ser book futuro sem quebrar este contrato.
   virtual double TotalLots() const = 0;

   // True se `positionId` corresponde a posição ainda aberta no escopo.
   // Usado pelo CMksTradeManager para auto-detach quando o broker
   // fechou a posição externamente (SL/TP hit, manual close, auto-close
   // do CMksSimulatedBroker — ADR-027 §7.3). False se a posição não
   // existe, foi fechada, ou está fora do escopo do book.
   virtual bool IsOpen(ulong positionId) const = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_IPOSITIONBOOK_MQH
