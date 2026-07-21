//+------------------------------------------------------------------+
//| @file           : CMksTradeJournalingBroker.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Trade
//| @responsibility : Decorator de IBroker que, em cada Send/Close FILLED,
//|                   delega ao broker interno e alimenta o CMksTradeJournal
//|                   (agregados money-aware que o CMksStressLabReport lê) E,
//|                   opcionalmente, a CMksSimAccount. É o broker MAIS EXTERNO
//|                   que a estratégia chama (envolve o CMksRiskGatedBroker),
//|                   por isso enxerga o REJECTED do gate. Gêmeo do
//|                   CMksJournalingBroker (que alimenta um journal de DECISÃO);
//|                   este alimenta o journal de TRADE (PnL). Non-owning.
//| @depends_on     : Core/Interfaces/IBroker.mqh,
//|                   Core/Trade/CMksTradeJournal.mqh,
//|                   Core/Account/CMksSimAccount.mqh,
//|                   Core/Types/OrderRequest.mqh,
//|                   Core/Types/ExecutionResult.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Trade/CMksTradeJournalingBroker.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TRADE_CMKSTRADEJOURNALINGBROKER_MQH
#define MKS_ULTIMATE_CORE_TRADE_CMKSTRADEJOURNALINGBROKER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksTradeJournal.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksSimAccount.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Wrapper de IBroker que registra trades (abertura/fechamento) num
// CMksTradeJournal e alimenta o modelo de conta simulado.
//
// Posição na cadeia (do mais externo ao mais interno):
//   estratégia -> CMksTradeJournalingBroker -> CMksRiskGatedBroker
//              -> CMksStressLabBroker -> CMksSimulatedBroker
// A estratégia (CMksColorReversalStrategy) chama Send/Close DENTRO do
// OnBrickClose — encapsulados. É por isso que precisa do decorator: não há
// como o runner "borrifar" RecordOpen/RecordClose de fora. Este objeto vê
// cada Send/Close e alimenta o journal + a conta no fill.
//
// journal: obrigatório. account: opcional (NULL desliga a alimentação).
// Nenhum ownership — o runner cria e destrói inner/journal/account.
//
// O que grava e alimenta:
//   Send  -> se FILLED: journal.RecordOpen(positionId, side, filledLots,
//                                           fillPrice, execTimeMsc, commission);
//            se FILLED e account!=NULL: account.OnOpen(id, side, fillPrice,
//                                                       filledLots, commission).
//   Close -> se FILLED: journal.RecordClose(positionId, fillPrice,
//                                            execTimeMsc, commission);
//            se FILLED e account!=NULL: account.OnClose(id, fillPrice, commission).
//   Modify-> só delega (ColorReversal não usa Modify em v1).
//
// Convenção lots: usa filledLots (a REALIDADE do fill), não request.lots —
// o journal de PnL tem de refletir o que abriu de fato. (Diferente do
// CMksJournalingBroker, cujo journal de DECISÃO registra a intenção.)
//
// PARTIAL: o caminho sim+stress não produz fill parcial (o CMksSimulatedBroker
// só devolve PARTIAL sob injeção one-shot explícita, E5.2, que o runner não
// usa). Por isso o decorator registra só em FILLED — igual ao gêmeo. Se um
// dia o runner injetar PARTIAL, tratar aqui explicitamente.
//
// Auto-close de SL/TP NÃO passa por aqui (o simulador fecha internamente no
// OnTick e enfileira o evento). O runner drena PollAutoCloses e chama
// journal.RecordClose + account.OnClose — cada posição fecha uma vez só
// (explícita via decorator OU auto via poll), logo não há dupla contagem.
class CMksTradeJournalingBroker : public IBroker
{
private:
   IBroker         *m_inner;    // obrigatório (o gated/stress broker)
   CMksTradeJournal *m_journal; // obrigatório
   CMksSimAccount  *m_account;  // opcional (NULL = não alimenta)

   MksExecutionResult MakeWiringError() const
   {
      MksExecutionResult r;
      r.status        = MKS_EXEC_ERROR;
      r.brokerRetcode = (int)MKS_ERR_BROKER_NOT_INITIALIZED;
      return r;
   }

public:
   CMksTradeJournalingBroker(IBroker *inner, CMksTradeJournal *journal,
                             CMksSimAccount *account = NULL)
   {
      m_inner   = inner;
      m_journal = journal;
      m_account = account;
   }

   MksExecutionResult Send(const MksOrderRequest &request) override
   {
      if(m_inner == NULL || m_journal == NULL)
         return MakeWiringError();

      MksExecutionResult r = m_inner.Send(request);

      // Só registra trade quando abriu de fato — REJECTED do gate/broker
      // não é um trade (fica no rastro do stress broker / risk manager).
      if(r.status == MKS_EXEC_FILLED)
      {
         m_journal.RecordOpen(r.positionId, request.side, r.filledLots,
                              r.fillPrice, r.execTimeMsc, r.commission);
         if(m_account != NULL)
            m_account.OnOpen(r.positionId, request.side, r.fillPrice,
                             r.filledLots, r.commission);
      }

      return r;
   }

   MksExecutionResult Close(ulong positionId, double lots) override
   {
      if(m_inner == NULL || m_journal == NULL)
         return MakeWiringError();

      MksExecutionResult r = m_inner.Close(positionId, lots);

      if(r.status == MKS_EXEC_FILLED)
      {
         m_journal.RecordClose(positionId, r.fillPrice, r.execTimeMsc,
                               r.commission);
         if(m_account != NULL)
            m_account.OnClose(positionId, r.fillPrice, r.commission);
      }

      return r;
   }

   bool Modify(ulong positionId, double slPrice, double tpPrice) override
   {
      if(m_inner == NULL) return false;
      return m_inner.Modify(positionId, slPrice, tpPrice);
   }
};

#endif // MKS_ULTIMATE_CORE_TRADE_CMKSTRADEJOURNALINGBROKER_MQH
