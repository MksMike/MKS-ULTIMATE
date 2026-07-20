//+------------------------------------------------------------------+
//| @file           : CMksJournalingBroker.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Trade
//| @responsibility : Decorator de IBroker que, em cada Send/Close,
//|                   delega ao broker interno, grava a DECISÃO no
//|                   CMksDecisionJournal (SEND/CLOSE com o brokerRetcode
//|                   do resultado) E alimenta o modelo de conta
//|                   (CMksSimAccount) no fill. É o broker MAIS EXTERNO
//|                   que a estratégia chama — envolve o CMksRiskGatedBroker,
//|                   logo enxerga o REJECTED do gate (que nunca chega ao
//|                   broker interno) e o registra no journal. Fora do
//|                   gate por construção. Non-owning: journal, conta e
//|                   inner pertencem ao composition root/runner (E2.0).
//| @depends_on     : Core/Interfaces/IBroker.mqh,
//|                   Core/Trade/CMksDecisionJournal.mqh,
//|                   Core/Account/CMksSimAccount.mqh,
//|                   Core/Types/OrderRequest.mqh,
//|                   Core/Types/ExecutionResult.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Trade/CMksJournalingBroker.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TRADE_CMKSJOURNALINGBROKER_MQH
#define MKS_ULTIMATE_CORE_TRADE_CMKSJOURNALINGBROKER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksDecisionJournal.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksSimAccount.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Wrapper de IBroker que registra decisões e alimenta a conta sim.
//
// Posição na cadeia (do mais externo ao mais interno):
//   estratégia -> CMksJournalingBroker -> CMksRiskGatedBroker -> CMksSimulatedBroker
// Por ser o mais externo, o retorno REJECTED do gate (que o inner nunca
// vê) passa por aqui e é registrado — o journal contém SEND-vs-REJECT,
// que é onde equity->gate acopla a decisão.
//
// journal: obrigatório. account: opcional (NULL desliga a alimentação).
// Nenhum ownership — o runner cria e destrói inner/journal/account.
//
// O que grava e alimenta:
//   Send  -> journal.RecordSend(status, side, positionId, request.lots,
//                               request.slPoints, request.tpPoints, retcode);
//            se FILLED e account!=NULL: account.OnOpen(id, side, fillPrice,
//                                                      filledLots, commission).
//   Close -> journal.RecordClose(status, positionId, lots, retcode);
//            se FILLED e account!=NULL: account.OnClose(id, fillPrice, commission).
//   Modify-> só delega (ColorReversal não usa Modify em v1; trailing é E5).
//
// Convenção lots: o journal registra a INTENÇÃO (request.lots / lots
// pedido) — função pura da decisão do sizer, mais estável que filledLots
// para o diff de paridade. A conta usa a REALIDADE (filledLots) — o
// modelo de dinheiro tem de refletir o que abriu de fato.
//
// Auto-close de SL/TP NÃO passa por aqui (o simulador fecha internamente
// no OnTick e enfileira o evento). O runner drena PollAutoCloses e chama
// journal.RecordAutoClose + account.OnClose — por isso não há risco de
// alimentação dupla da conta.
class CMksJournalingBroker : public IBroker
{
private:
   IBroker             *m_inner;    // obrigatório (o gated broker)
   CMksDecisionJournal *m_journal;  // obrigatório
   CMksSimAccount      *m_account;  // opcional (NULL = não alimenta)

   MksExecutionResult MakeWiringError() const
   {
      MksExecutionResult r;
      r.status        = MKS_EXEC_ERROR;
      r.brokerRetcode = (int)MKS_ERR_BROKER_NOT_INITIALIZED;
      return r;
   }

public:
   CMksJournalingBroker(IBroker *inner, CMksDecisionJournal *journal,
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

      // Registra a decisão de abertura com o status/retcode reais (inclui
      // REJECTED do gate). posOrdinal é atribuído pelo journal no 1º FILLED.
      m_journal.RecordSend(r.status, request.side, r.positionId,
                           request.lots, request.slPoints, request.tpPoints,
                           r.brokerRetcode);

      // Alimenta a conta só no fill, com os números reais do resultado.
      if(r.status == MKS_EXEC_FILLED && m_account != NULL)
         m_account.OnOpen(r.positionId, request.side, r.fillPrice,
                          r.filledLots, r.commission);

      return r;
   }

   MksExecutionResult Close(ulong positionId, double lots) override
   {
      if(m_inner == NULL || m_journal == NULL)
         return MakeWiringError();

      MksExecutionResult r = m_inner.Close(positionId, lots);

      m_journal.RecordClose(r.status, positionId, lots, r.brokerRetcode);

      if(r.status == MKS_EXEC_FILLED && m_account != NULL)
         m_account.OnClose(positionId, r.fillPrice, r.commission);

      return r;
   }

   bool Modify(ulong positionId, double slPrice, double tpPrice) override
   {
      if(m_inner == NULL) return false;
      return m_inner.Modify(positionId, slPrice, tpPrice);
   }
};

#endif // MKS_ULTIMATE_CORE_TRADE_CMKSJOURNALINGBROKER_MQH
