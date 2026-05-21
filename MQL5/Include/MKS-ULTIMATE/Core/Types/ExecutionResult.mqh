//+------------------------------------------------------------------+
//| @file           : ExecutionResult.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Types
//| @responsibility : Estrutura MksExecutionResult — desfecho de uma
//|                   submissão ao broker, com preço real preenchido.
//| @depends_on     : Nenhuma (autocontido)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Types/ExecutionResult.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TYPES_EXECUTIONRESULT_MQH
#define MKS_ULTIMATE_CORE_TYPES_EXECUTIONRESULT_MQH

enum ENUM_MKS_EXEC_STATUS
{
   MKS_EXEC_FILLED,      // preenchida integralmente
   MKS_EXEC_PARTIAL,     // preenchida parcialmente (filledLots < lots pedido)
   MKS_EXEC_REJECTED,    // recusada pelo broker
   MKS_EXEC_ERROR        // falha de comunicação / timeout
};

struct MksExecutionResult
{
   ENUM_MKS_EXEC_STATUS status;
   ulong  positionId;      // id da posição resultante (ticket no MT5 real); 0 se não abriu
   ulong  dealId;          // ticket do deal MT5 que originou o fill (ADR-017); 0 em simulado/sem fill
   double fillPrice;       // preço REAL de preenchimento — captura spread + slippage
   double requestedPrice;  // preço de referência observado na submissão
   double filledLots;      // volume efetivamente preenchido
   double commission;      // custo de comissão, magnitude >= 0 (P&L subtrai)
   double swap;            // swap acumulado (ADR-017); 0 na abertura, populado em close ou após overnight
   long   execTimeMsc;     // timestamp da execução, ms desde epoch
   int    brokerRetcode;   // código bruto da camada de execução, para diagnóstico
   int    attempts;        // tentativas que o broker fez (ADR-017); 1 = sucesso na primeira

   MksExecutionResult()
   {
      status = MKS_EXEC_ERROR;
      positionId = 0;
      dealId = 0;
      fillPrice = 0.0;
      requestedPrice = 0.0;
      filledLots = 0.0;
      commission = 0.0;
      swap = 0.0;
      execTimeMsc = 0;
      brokerRetcode = 0;
      attempts = 0;
   }

   bool   IsFilled() const { return status == MKS_EXEC_FILLED; }
   double Slippage() const { return fillPrice - requestedPrice; }
};

#endif // MKS_ULTIMATE_CORE_TYPES_EXECUTIONRESULT_MQH
