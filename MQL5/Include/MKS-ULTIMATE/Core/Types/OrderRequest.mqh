//+------------------------------------------------------------------+
//| @file           : OrderRequest.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Types
//| @responsibility : Estrutura MksOrderRequest — intenção de ordem
//|                   submetida via IBroker, agnóstica de implementação.
//| @depends_on     : Nenhuma (autocontido)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Types/OrderRequest.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TYPES_ORDERREQUEST_MQH
#define MKS_ULTIMATE_CORE_TYPES_ORDERREQUEST_MQH

enum ENUM_MKS_ORDER_SIDE
{
   MKS_ORDER_BUY,
   MKS_ORDER_SELL
};

struct MksOrderRequest
{
   ENUM_MKS_ORDER_SIDE side;
   double lots;        // tamanho da posição, em lotes
   double slPoints;    // distância do stop loss em pontos a partir da entrada (0 = sem SL)
   double tpPoints;    // distância do take profit em pontos a partir da entrada (0 = sem TP)
   string comment;     // identificação do trade (estratégia/sinal)

   MksOrderRequest()
   {
      side = MKS_ORDER_BUY;
      lots = 0.0;
      slPoints = 0.0;
      tpPoints = 0.0;
      comment = "";
   }

   bool IsValid() const { return lots > 0.0 && slPoints >= 0.0 && tpPoints >= 0.0; }
};

#endif // MKS_ULTIMATE_CORE_TYPES_ORDERREQUEST_MQH
