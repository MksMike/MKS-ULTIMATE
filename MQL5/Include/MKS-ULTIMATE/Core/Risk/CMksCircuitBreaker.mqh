//+------------------------------------------------------------------+
//| @file           : CMksCircuitBreaker.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Risk
//| @responsibility : Circuit breaker CORRETIVO (ADR-040). Decorator de
//|                   IBroker, o mais EXTERNO da cadeia. Por tick (OnTick),
//|                   consulta CMksRiskManager.AccountBreached (MESMO predicado
//|                   do gate preventivo — fonte única) e, ao cruzar um limite
//|                   Por Conta (equity/drawdown/daily loss), TRIPA (sticky):
//|                   fecha TODAS as posições abertas (flatten via IPositionBook
//|                   + inner.Close, retry por tick até flat) e passa a REJEITAR
//|                   todo Send. Close/Modify seguem passando (o flatten precisa
//|                   fechar). Complementa o breaker preventivo (que só bloqueia
//|                   a ABERTURA): é a resposta à lição do V5 — a conta quebrou
//|                   com posição ABERTA, e "não abrir novas" não a teria salvo.
//|                   Sticky: uma vez tripado, trava até Reset() — não re-arma no
//|                   rollover diário nem na recuperação de equity.
//| @depends_on     : Core/Interfaces/IBroker.mqh,
//|                   Core/Interfaces/IPositionBook.mqh,
//|                   Core/Interfaces/ILogger.mqh,
//|                   Core/Risk/CMksRiskManager.mqh,
//|                   Core/Types/OrderRequest.mqh,
//|                   Core/Types/ExecutionResult.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Risk/CMksCircuitBreaker.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_RISK_CMKSCIRCUITBREAKER_MQH
#define MKS_ULTIMATE_CORE_RISK_CMKSCIRCUITBREAKER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IPositionBook.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ILogger.mqh>
#include <MKS-ULTIMATE/Core/Risk/CMksRiskManager.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Posição na cadeia (do mais externo ao mais interno):
//   estratégia -> CMksCircuitBreaker -> CMksRiskGatedBroker -> ... -> broker real
// O breaker é OUTERMOST: enxerga o Send da estratégia ANTES do gate preventivo
// e, tripado, o rejeita. O EA/runner dirige OnTick() por tick (após snapshot).
//
// Non-owning: inner/risk/book/logger pertencem ao composition root.
class CMksCircuitBreaker : public IBroker
{
private:
   IBroker         *m_inner;
   CMksRiskManager *m_risk;
   IPositionBook   *m_book;
   ILogger         *m_logger;

   bool   m_tripped;
   int    m_tripCode;      // código do 1º limite violado (MKS_ERR_RISK_REJECTED_*)
   long   m_flattenAttempts;
   long   m_flattenClosed;
   long   m_sendsBlocked;

   MksExecutionResult MakeRejected(int retcode) const
   {
      MksExecutionResult r;
      r.status        = MKS_EXEC_REJECTED;
      r.brokerRetcode = retcode;
      return r;
   }

   void LogCtx(ENUM_MKS_LOG_LEVEL level, const string &msg, const string &ctxJson)
   {
      if(m_logger != NULL)
         m_logger.Log(level, "CircuitBreaker", msg, ctxJson);
   }

   // Fecha TODAS as posições abertas do escopo do book. Tira um snapshot dos
   // ids/lots ANTES (o book é visão viva — muda ao fechar), depois fecha cada
   // um via inner.Close. Um Close que falha deixa a posição aberta; o próximo
   // OnTick re-tenta (o breaker segue tripado).
   void FlattenAll()
   {
      if(m_book == NULL || m_inner == NULL) return;
      int n = m_book.OpenCount();
      if(n <= 0) return;

      ulong  ids[];
      double lots[];
      for(int i = 0; i < n; i++)
      {
         ulong id; ENUM_MKS_ORDER_SIDE side; double lot;
         if(!m_book.PositionAt(i, id, side, lot)) continue;
         int k = ArraySize(ids);
         ArrayResize(ids, k + 1);
         ArrayResize(lots, k + 1);
         ids[k]  = id;
         lots[k] = lot;
      }

      for(int j = 0; j < ArraySize(ids); j++)
      {
         MksExecutionResult r = m_inner.Close(ids[j], lots[j]);
         m_flattenAttempts++;
         if(r.status == MKS_EXEC_FILLED)
         {
            m_flattenClosed++;
            LogCtx(MKS_LOG_WARN, "flatten: posição fechada",
                   StringFormat("\"pid\":%I64u,\"lots\":%.4f,\"price\":%.5f",
                                ids[j], lots[j], r.fillPrice));
         }
         else
         {
            LogCtx(MKS_LOG_ERROR, "flatten: Close FALHOU — re-tenta no próximo tick",
                   StringFormat("\"pid\":%I64u,\"lots\":%.4f,\"status\":%d,\"retcode\":%d",
                                ids[j], lots[j], (int)r.status, r.brokerRetcode));
         }
      }
   }

public:
   CMksCircuitBreaker(IBroker *inner, CMksRiskManager *risk,
                      IPositionBook *book, ILogger *logger = NULL)
   {
      m_inner  = inner;
      m_risk   = risk;
      m_book   = book;
      m_logger = logger;

      m_tripped         = false;
      m_tripCode        = 0;
      m_flattenAttempts = 0;
      m_flattenClosed   = 0;
      m_sendsBlocked    = 0;
   }

   //--- IBroker -----------------------------------------------------+

   // Tripado → rejeita (sticky). Senão delega ao gate preventivo.
   MksExecutionResult Send(const MksOrderRequest &request) override
   {
      if(m_tripped)
      {
         m_sendsBlocked++;
         return MakeRejected(m_tripCode);
      }
      if(m_inner == NULL) return MakeRejected((int)MKS_ERR_BROKER_NOT_INITIALIZED);
      return m_inner.Send(request);
   }

   // Close/Modify sempre delegam — o flatten precisa fechar mesmo tripado.
   MksExecutionResult Close(ulong positionId, double lots) override
   {
      if(m_inner == NULL) return MakeRejected((int)MKS_ERR_BROKER_NOT_INITIALIZED);
      return m_inner.Close(positionId, lots);
   }

   bool Modify(ulong positionId, double slPrice, double tpPrice) override
   {
      if(m_inner == NULL) return false;
      return m_inner.Modify(positionId, slPrice, tpPrice);
   }

   //--- Motor corretivo (dirigido por tick pelo EA/runner) ----------+

   // Detecta breach (sticky trip) + mantém o flatten até estar flat. Chamar
   // por tick, DEPOIS do snapshot.Update do EA (AccountBreached atualiza o
   // snapshot de novo — idempotente).
   void OnTick()
   {
      if(!m_tripped && m_risk != NULL)
      {
         MksError err;
         if(m_risk.AccountBreached(err))
         {
            m_tripped  = true;
            m_tripCode = (int)err.code;
            LogCtx(MKS_LOG_ERROR, "TRIPPED — circuit breaker corretivo disparou",
                   StringFormat("\"code\":%d,\"detail\":\"%s\"",
                                m_tripCode, err.detail));
         }
      }

      if(m_tripped)
         FlattenAll(); // no-op se já flat; re-tenta closes falhos
   }

   //--- Observabilidade / controle ----------------------------------+

   bool IsTripped()        const { return m_tripped; }
   int  TripCode()         const { return m_tripCode; }
   long FlattenAttempts()  const { return m_flattenAttempts; }
   long FlattenClosed()    const { return m_flattenClosed; }
   long SendsBlocked()     const { return m_sendsBlocked; }

   // Re-arma o breaker (nova sessão / decisão do operador). Sticky por design:
   // só isto destrava — nem o rollover diário nem a recuperação de equity.
   void Reset()
   {
      m_tripped  = false;
      m_tripCode = 0;
   }
};

#endif // MKS_ULTIMATE_CORE_RISK_CMKSCIRCUITBREAKER_MQH
