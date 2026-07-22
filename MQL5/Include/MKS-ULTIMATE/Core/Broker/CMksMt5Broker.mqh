//+------------------------------------------------------------------+
//| @file           : CMksMt5Broker.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Broker
//| @responsibility : Implementação real de IBroker via API MT5
//|                   (OrderSend + OnTradeTransaction). Síncrono
//|                   lógico — bloqueia até DEAL_ADD ou timeout.
//|                   Aplica ADR-017.
//| @depends_on     : Core/Interfaces/IBroker.mqh, Core/Interfaces/ISymbol.mqh,
//|                   Core/Interfaces/IAccount.mqh, Core/Types/OrderRequest.mqh,
//|                   Core/Types/ExecutionResult.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Broker/CMksMt5Broker.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_BROKER_CMKSMT5BROKER_MQH
#define MKS_ULTIMATE_CORE_BROKER_CMKSMT5BROKER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IBroker.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IAccount.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Broker real — implementa IBroker via API MT5 (OrderSend + HistoryDeal*).
// Síncrono lógico (ADR-017 §1): Send/Close retornam com preço executado real.
//
// MECÂNICA DE CONFIRMAÇÃO (lição empírica — corrigida em 2026-05-22):
// MQL5 é single-threaded cooperativo. OnTradeTransaction NÃO é processado
// durante uma execução de OnTick — fica em fila até OnTick retornar.
// Logo, esperar via Sleep + flag (m_pendingReady) DEADLOCKA: Send fica
// preso esperando evento que só vem depois que Send retornar.
// SOLUÇÃO: ler MqlTradeResult.deal DIRETO após OrderSend retornar DONE.
// Em Market execution o deal já está populado imediatamente — basta
// HistoryDealSelect(res.deal) + HistoryDealGetDouble(...).
// OnTradeTransactionEvent permanece como fallback para casos edge
// (deal=0 imediato, ordens postergadas), mas o caminho feliz é direto.
//
// Roteamento de OnTradeTransaction: o EA AINDA chama
// g_broker.OnTradeTransactionEvent(transaction, request, result) — usado
// só em fallback. Caminho normal não depende.
//
// Limitações v1:
// - Sem tratamento explícito de DONE_PARTIAL (assume preenchimento
//   total ou falha; partial vira ERROR).
// - Sem cache de posições — Close consulta PositionSelectByTicket
//   a cada chamada.
// - Sem logging interno; caller usa ILogger no composition root.
// - Modify usa TRADE_ACTION_SLTP — não cria deal, não espera evento.
class CMksMt5Broker : public IBroker
{
private:
   //--- Configuração injetada
   ISymbol *m_symbol;
   IAccount *m_account;
   int     m_magic;
   int     m_deviation;
   uint    m_timeoutMs;
   int     m_maxRetries;
   int     m_retryDelayMs;

   //--- Estado pós-Init
   bool                       m_initialized;
   ENUM_ORDER_TYPE_FILLING    m_effectiveFilling;
   bool                       m_fillingFallbackUsed;   // observável: houve fallback de filling nesta sessão (não é gate)
   ENUM_ACCOUNT_MARGIN_MODE   m_marginMode;

   //--- Estado de sincronização com OnTradeTransaction
   ulong  m_pendingOrderTicket;   // ticket da ordem que estamos esperando
   ulong  m_pendingDealTicket;    // ticket do deal recebido via DEAL_ADD
   double m_pendingDealPrice;
   double m_pendingDealVolume;
   double m_pendingDealCommission;
   double m_pendingDealSwap;
   long   m_pendingDealTimeMsc;
   bool   m_pendingReady;

   //--- Helpers internos ---

   void ResetPending()
   {
      m_pendingOrderTicket    = 0;
      m_pendingDealTicket     = 0;
      m_pendingDealPrice      = 0.0;
      m_pendingDealVolume     = 0.0;
      m_pendingDealCommission = 0.0;
      m_pendingDealSwap       = 0.0;
      m_pendingDealTimeMsc    = 0;
      m_pendingReady          = false;
   }

   // Escolhe filling inicial a partir do bitmask do símbolo.
   // Preferência: FOK → IOC → RETURN (RETURN é sempre disponível).
   ENUM_ORDER_TYPE_FILLING PickInitialFilling() const
   {
      int bitmask = m_symbol.FillingMode();
      if((bitmask & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
      if((bitmask & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
      return ORDER_FILLING_RETURN;
   }

   // Regrida no fallback após INVALID_FILL.
   // FOK → IOC → RETURN; RETURN não regrida mais.
   bool TryFillingFallback()
   {
      if(m_effectiveFilling == ORDER_FILLING_FOK)
      {
         m_effectiveFilling = ORDER_FILLING_IOC;
         return true;
      }
      if(m_effectiveFilling == ORDER_FILLING_IOC)
      {
         m_effectiveFilling = ORDER_FILLING_RETURN;
         return true;
      }
      return false; // já está em RETURN
   }

   // Retcode retryable? (REQUOTE, PRICE_CHANGED, PRICE_OFF — ADR-017 §6)
   bool IsRetryable(uint retcode) const
   {
      return retcode == TRADE_RETCODE_REQUOTE
          || retcode == TRADE_RETCODE_PRICE_CHANGED
          || retcode == TRADE_RETCODE_PRICE_OFF;
   }

   // Lê dados do deal direto via HistoryDealGet* e popula m_pending*.
   // Caminho síncrono direto — sem dependência de OnTradeTransaction.
   // Retorna true se deal foi selecionado com sucesso.
   bool ReadDealInto(ulong dealTicket)
   {
      if(dealTicket == 0) return false;
      if(!HistoryDealSelect(dealTicket)) return false;
      m_pendingDealTicket     = dealTicket;
      m_pendingDealPrice      = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      m_pendingDealVolume     = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      m_pendingDealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      m_pendingDealSwap       = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      m_pendingDealTimeMsc    = (long)HistoryDealGetInteger(dealTicket, DEAL_TIME_MSC);
      m_pendingReady          = true;
      return true;
   }

   // Fallback: aguarda OnTradeTransactionEvent setar m_pendingReady.
   // Usado apenas quando res.deal == 0 (caso edge — ordens pendentes,
   // execução postergada). MQL5 single-threaded: Sleep yield ao terminal,
   // e este caminho só é tomado quando o caminho síncrono direto falhou.
   bool WaitForDealAdd()
   {
      uint start = GetTickCount();
      while(!m_pendingReady)
      {
         if(GetTickCount() - start > m_timeoutMs) return false;
         Sleep(10);
      }
      return true;
   }

   // Constrói MksExecutionResult preenchido com dados do deal corrente.
   MksExecutionResult MakeFilledResult(ulong positionId,
                                       double requestedPrice,
                                       double requestedLots,
                                       int attempts) const
   {
      MksExecutionResult r;
      r.status         = MKS_EXEC_FILLED;
      r.positionId     = positionId;
      r.dealId         = m_pendingDealTicket;
      r.fillPrice      = m_pendingDealPrice;
      r.requestedPrice = requestedPrice;
      r.filledLots     = (m_pendingDealVolume > 0.0)
                           ? m_pendingDealVolume : requestedLots;
      r.commission     = MathAbs(m_pendingDealCommission); // ADR convention: magnitude >= 0
      r.swap           = m_pendingDealSwap;
      r.execTimeMsc    = m_pendingDealTimeMsc;
      r.brokerRetcode  = (int)TRADE_RETCODE_DONE;
      r.attempts       = attempts;
      return r;
   }

   MksExecutionResult MakeError(int retcode, int attempts) const
   {
      MksExecutionResult r;
      r.status        = MKS_EXEC_ERROR;
      r.brokerRetcode = retcode;
      r.attempts      = attempts;
      return r;
   }

   MksExecutionResult MakeRejected(int retcode, int attempts) const
   {
      MksExecutionResult r;
      r.status        = MKS_EXEC_REJECTED;
      r.brokerRetcode = retcode;
      r.attempts      = attempts;
      return r;
   }

public:
   CMksMt5Broker(ISymbol *symbol,
                 IAccount *account,
                 int    magic        = 13371337,
                 int    deviation    = 10,
                 uint   timeoutMs    = 5000,
                 int    maxRetries   = 3,
                 int    retryDelayMs = 100)
   {
      m_symbol               = symbol;
      m_account              = account;
      m_magic                = magic;
      m_deviation            = deviation;
      m_timeoutMs            = timeoutMs;
      m_maxRetries           = maxRetries;
      m_retryDelayMs         = retryDelayMs;
      m_initialized          = false;
      m_effectiveFilling     = ORDER_FILLING_RETURN;
      m_fillingFallbackUsed  = false;
      m_marginMode           = ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
      ResetPending();
   }

   // Init detecta filling preferido + margin mode. Chamar antes de
   // Send/Close. Retorna true se ISymbol e IAccount disponíveis.
   bool Init(MksError &err)
   {
      if(m_symbol == NULL || m_account == NULL)
      {
         MKS_SET_ERROR(err, MKS_ERR_BROKER_NOT_INITIALIZED,
                       "ISymbol ou IAccount nulo", "");
         return false;
      }
      m_marginMode = m_account.MarginMode();
      // ADR-029: v1 é hedging-only. Netting/exchange usam posição líquida
      // por símbolo — positionId não mapeia 1:1 para posição, e Close /
      // partial / auto-detach dessincronizariam em silêncio (eixo 2 do V5).
      // Recusa estrutural aqui (camada única que lê o margin mode); o popup
      // é decisão da borda (EA). Suporte a netting fica para fork futuro.
      if(m_marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      {
         MKS_SET_ERROR(err, MKS_ERR_BROKER_NETTING_UNSUPPORTED,
                       "conta não-hedging — framework v1 suporta apenas hedging",
                       StringFormat("marginMode=%d", (int)m_marginMode));
         return false;
      }
      m_effectiveFilling     = PickInitialFilling();
      m_fillingFallbackUsed  = false;
      m_initialized          = true;
      return true;
   }

   // EA chama isto do seu OnTradeTransaction. Filtra por DEAL_ADD do
   // pending order; preenche m_pending* e seta ready.
   void OnTradeTransactionEvent(const MqlTradeTransaction &trans,
                                const MqlTradeRequest     &request,
                                const MqlTradeResult      &result)
   {
      if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
      if(m_pendingOrderTicket == 0) return;
      if(trans.order != m_pendingOrderTicket) return;
      ulong dealTicket = trans.deal;
      if(dealTicket == 0) return;
      if(!HistoryDealSelect(dealTicket)) return;
      m_pendingDealTicket     = dealTicket;
      m_pendingDealPrice      = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      m_pendingDealVolume     = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      m_pendingDealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      m_pendingDealSwap       = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      m_pendingDealTimeMsc    = (long)HistoryDealGetInteger(dealTicket, DEAL_TIME_MSC);
      m_pendingReady          = true;
   }

   MksExecutionResult Send(const MksOrderRequest &request) override
   {
      if(!m_initialized)
         return MakeError(MKS_ERR_BROKER_NOT_INITIALIZED, 0);
      if(!request.IsValid())
         return MakeRejected(MKS_ERR_CORE_INVALID_ARGUMENT, 0);

      string sym  = m_symbol.Name();
      double point = m_symbol.Point();

      // Preço de referência (ASK para BUY, BID para SELL).
      double refPrice = (request.side == MKS_ORDER_BUY)
                         ? SymbolInfoDouble(sym, SYMBOL_ASK)
                         : SymbolInfoDouble(sym, SYMBOL_BID);
      if(refPrice <= 0.0)
         return MakeError(MKS_ERR_CORE_INVALID_ARGUMENT, 0);

      // SL/TP absolutos. BUY: SL abaixo, TP acima; SELL inverso.
      double slPrice = 0.0;
      double tpPrice = 0.0;
      if(request.slPoints > 0.0)
      {
         if(request.side == MKS_ORDER_BUY)
            slPrice = refPrice - request.slPoints * point;
         else
            slPrice = refPrice + request.slPoints * point;
      }
      if(request.tpPoints > 0.0)
      {
         if(request.side == MKS_ORDER_BUY)
            tpPrice = refPrice + request.tpPoints * point;
         else
            tpPrice = refPrice - request.tpPoints * point;
      }

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);

      int attempts = 0;
      uint lastRetcode = 0;
      while(attempts < m_maxRetries)
      {
         attempts++;
         req.action       = TRADE_ACTION_DEAL;
         req.symbol       = sym;
         req.volume       = request.lots;
         req.type         = (request.side == MKS_ORDER_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         req.price        = (request.side == MKS_ORDER_BUY)
                              ? SymbolInfoDouble(sym, SYMBOL_ASK)
                              : SymbolInfoDouble(sym, SYMBOL_BID);
         req.sl           = slPrice;
         req.tp           = tpPrice;
         req.deviation    = m_deviation;
         req.magic        = m_magic;
         req.type_filling = m_effectiveFilling;
         req.comment      = request.comment;

         ResetPending();
         bool ok = OrderSend(req, res);
         lastRetcode = res.retcode;

         if(!ok)
         {
            // OrderSend retornou false — provavelmente validação local.
            if(IsRetryable(lastRetcode))
            {
               Sleep(m_retryDelayMs);
               continue;
            }
            return MakeRejected((int)lastRetcode, attempts);
         }

         // OrderSend aceito; verifica retcode.
         if(lastRetcode == TRADE_RETCODE_DONE
            || lastRetcode == TRADE_RETCODE_DONE_PARTIAL
            || lastRetcode == TRADE_RETCODE_PLACED)
         {
            // Caminho síncrono direto: res.deal já populado em Market.
            if(ReadDealInto(res.deal))
            {
               ulong posId = (ulong)HistoryDealGetInteger(res.deal, DEAL_POSITION_ID);
               if(posId == 0) posId = res.order;
               return MakeFilledResult(posId, refPrice, request.lots, attempts);
            }
            // Fallback (caso edge: deal=0 imediato).
            m_pendingOrderTicket = res.order;
            if(WaitForDealAdd())
            {
               ulong posId = (m_pendingDealTicket != 0)
                  ? (ulong)HistoryDealGetInteger(m_pendingDealTicket, DEAL_POSITION_ID)
                  : 0;
               if(posId == 0) posId = res.order;
               return MakeFilledResult(posId, refPrice, request.lots, attempts);
            }
            return MakeError(MKS_ERR_BROKER_TIMEOUT, attempts);
         }

         // INVALID_FILL: regride o filling na cadeia FOK→IOC→RETURN, um passo
         // por retcode, até um filling aceito ou a cadeia esgotar
         // (TryFillingFallback devolve false em RETURN → MakeRejected). Termina:
         // cadeia finita (máx 2 avanços). m_fillingFallbackUsed é só observável
         // (getter), NÃO trava mais — travar aqui impedia o 2º passo IOC→RETURN.
         if(lastRetcode == TRADE_RETCODE_INVALID_FILL)
         {
            if(TryFillingFallback())
            {
               m_fillingFallbackUsed = true;
               attempts--;          // não consome tentativa real
               continue;
            }
            return MakeRejected(MKS_ERR_BROKER_INVALID_FILL, attempts);
         }

         // Retryable?
         if(IsRetryable(lastRetcode))
         {
            Sleep(m_retryDelayMs);
            continue;
         }

         // Fatal.
         return MakeRejected((int)lastRetcode, attempts);
      }

      return MakeError(MKS_ERR_BROKER_RETRY_EXHAUSTED, attempts);
   }

   MksExecutionResult Close(ulong positionId, double lots) override
   {
      if(!m_initialized)
         return MakeError(MKS_ERR_BROKER_NOT_INITIALIZED, 0);
      if(!PositionSelectByTicket(positionId))
         return MakeRejected(MKS_ERR_CORE_INVALID_ARGUMENT, 0);

      string sym = m_symbol.Name();
      long posType = PositionGetInteger(POSITION_TYPE); // POSITION_TYPE_BUY/SELL
      double posVolume = PositionGetDouble(POSITION_VOLUME);
      if(lots <= 0.0 || lots > posVolume)
         return MakeRejected(MKS_ERR_CORE_INVALID_ARGUMENT, 0);

      // Lado oposto.
      ENUM_ORDER_TYPE closeType = (posType == POSITION_TYPE_BUY)
                                    ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      double closePrice = (closeType == ORDER_TYPE_BUY)
                            ? SymbolInfoDouble(sym, SYMBOL_ASK)
                            : SymbolInfoDouble(sym, SYMBOL_BID);

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);

      int attempts = 0;
      uint lastRetcode = 0;
      while(attempts < m_maxRetries)
      {
         attempts++;
         req.action       = TRADE_ACTION_DEAL;
         req.symbol       = sym;
         req.volume       = lots;
         req.type         = closeType;
         req.price        = (closeType == ORDER_TYPE_BUY)
                              ? SymbolInfoDouble(sym, SYMBOL_ASK)
                              : SymbolInfoDouble(sym, SYMBOL_BID);
         req.deviation    = m_deviation;
         req.magic        = m_magic;
         req.type_filling = m_effectiveFilling;
         // Hedging: especifica position; netting ignora.
         if(m_marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
            req.position = positionId;

         ResetPending();
         bool ok = OrderSend(req, res);
         lastRetcode = res.retcode;

         if(!ok)
         {
            if(IsRetryable(lastRetcode))
            {
               Sleep(m_retryDelayMs);
               continue;
            }
            return MakeRejected((int)lastRetcode, attempts);
         }

         if(lastRetcode == TRADE_RETCODE_DONE
            || lastRetcode == TRADE_RETCODE_DONE_PARTIAL)
         {
            // Caminho síncrono direto: lê deal de res.deal imediatamente.
            if(ReadDealInto(res.deal))
               return MakeFilledResult(positionId, closePrice, lots, attempts);
            // Fallback (edge case).
            m_pendingOrderTicket = res.order;
            if(WaitForDealAdd())
               return MakeFilledResult(positionId, closePrice, lots, attempts);
            return MakeError(MKS_ERR_BROKER_TIMEOUT, attempts);
         }

         // INVALID_FILL: mesma cadeia de fallback do Send() (FOK→IOC→RETURN, um
         // passo por retcode). Twin-path obrigatório: sem isto o FlattenAll do
         // circuit breaker (ADR-040) receberia INVALID_FILL a cada tick e NUNCA
         // fecharia a posição — a defesa central contra a lição do V5 falharia
         // em silêncio. m_effectiveFilling é compartilhado com Send.
         if(lastRetcode == TRADE_RETCODE_INVALID_FILL)
         {
            if(TryFillingFallback())
            {
               m_fillingFallbackUsed = true;
               attempts--;
               continue;
            }
            return MakeRejected(MKS_ERR_BROKER_INVALID_FILL, attempts);
         }

         if(IsRetryable(lastRetcode))
         {
            Sleep(m_retryDelayMs);
            continue;
         }

         return MakeRejected((int)lastRetcode, attempts);
      }

      return MakeError(MKS_ERR_BROKER_RETRY_EXHAUSTED, attempts);
   }

   bool Modify(ulong positionId, double slPrice, double tpPrice) override
   {
      if(!m_initialized) return false;
      if(!PositionSelectByTicket(positionId)) return false;

      MqlTradeRequest req;
      MqlTradeResult  res;
      ZeroMemory(req);
      ZeroMemory(res);

      req.action   = TRADE_ACTION_SLTP;
      req.symbol   = m_symbol.Name();
      req.sl       = slPrice;
      req.tp       = tpPrice;
      req.magic    = m_magic;
      if(m_marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
         req.position = positionId;

      if(!OrderSend(req, res)) return false;
      return res.retcode == TRADE_RETCODE_DONE;
   }

   //--- Observabilidade (testes/diagnóstico) ---
   ENUM_ORDER_TYPE_FILLING EffectiveFilling() const { return m_effectiveFilling; }
   bool                    FillingFallbackUsed() const { return m_fillingFallbackUsed; }
   ENUM_ACCOUNT_MARGIN_MODE MarginMode() const { return m_marginMode; }
   bool                    IsInitialized() const { return m_initialized; }
};

#endif // MKS_ULTIMATE_CORE_BROKER_CMKSMT5BROKER_MQH
