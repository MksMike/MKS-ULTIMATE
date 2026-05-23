//+------------------------------------------------------------------+
//| @file           : CMksRiskManager.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Risk
//| @responsibility : Middleware que valida MksOrderRequest antes da
//|                   execução. Camadas:
//|                     "Por trade"      (slice 6.1) — SL/TP, max lots,
//|                                                    limite vs Sizer.
//|                     "Por estratégia" (slice 6.2) — max posições
//|                                                    simultâneas,
//|                                                    max lots totais.
//|                     "Por conta"      (slice 6.3) — daily loss,
//|                                                    drawdown, circuit
//|                                                    breaker (pendente).
//|                   ADR-019.
//| @depends_on     : Core/Types/OrderRequest.mqh, Core/Types/Error.mqh,
//|                   Core/Interfaces/IPositionSizer.mqh,
//|                   Core/Interfaces/IPositionBook.mqh,
//|                   Core/Interfaces/ILogger.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Risk/CMksRiskManager.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_RISK_CMKSRISKMANAGER_MQH
#define MKS_ULTIMATE_CORE_RISK_CMKSRISKMANAGER_MQH

#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IPositionSizer.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IPositionBook.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ILogger.mqh>

// Parâmetros da camada "Por trade".
//
// requireSl: default true — lição V5 #7. Em raríssimos cenários
//            (martingale legítimo, posição protegida por hedge externo)
//            pode-se desligar, mas a decisão fica explícita no config.
// requireTp: default false — TP é frequentemente gerenciado por
//            trailing/manage e nem sempre tem valor fixo na entrada.
// maxLotsPerTrade: 0 = sem limite. Quando >0, qualquer req.lots acima
//                  é rejeitada antes mesmo de o sizer ser consultado.
struct CMksRiskTradeParams
{
   bool   requireSl;
   bool   requireTp;
   double maxLotsPerTrade;

   CMksRiskTradeParams()
   {
      requireSl       = true;
      requireTp       = false;
      maxLotsPerTrade = 0.0;
   }
};

// Parâmetros da camada "Por estratégia" (slice 6.2).
//
// maxOpenPositions: 0 = sem limite. Quando >0, rejeita se uma nova
//                   posição estouraria o teto (book.OpenCount + 1).
// maxTotalLots:     0.0 = sem limite. Quando >0, rejeita se a soma
//                   book.TotalLots + req.lots passaria do teto.
//                   Proxy de exposure em volume — exposure ponderada
//                   por risco fica para slice futuro se necessária.
struct CMksRiskStrategyParams
{
   int    maxOpenPositions;
   double maxTotalLots;

   CMksRiskStrategyParams()
   {
      maxOpenPositions = 0;
      maxTotalLots     = 0.0;
   }
};

class CMksRiskManager
{
private:
   CMksRiskTradeParams    m_params;
   CMksRiskStrategyParams m_stratParams;
   IPositionSizer        *m_sizer;
   IPositionBook         *m_book;
   ILogger               *m_logger;

   void LogRejection(const string &reason,
                     const MksOrderRequest &req,
                     const MksError &err)
   {
      if(m_logger == NULL) return;
      string ctxJson = StringFormat(
         "\"reason\":\"%s\",\"errCode\":%d,\"side\":\"%s\","
         "\"lots\":%.8f,\"slPoints\":%.4f,\"tpPoints\":%.4f,"
         "\"comment\":\"%s\"",
         reason, (int)err.code,
         req.side == MKS_ORDER_BUY ? "BUY" : "SELL",
         req.lots, req.slPoints, req.tpPoints,
         req.comment);
      m_logger.Log(MKS_LOG_WARN, "RiskManager", "order rejected", ctxJson);
   }

public:
   // sizer, book e logger são opcionais.
   // sizer NULL:  pula a checagem "lots vs sizer".
   // book  NULL:  pula as checagens da camada "Por estratégia".
   // logger NULL: pula o log de rejeição (caller fica responsável).
   CMksRiskManager(const CMksRiskTradeParams &p,
                   IPositionSizer *sizer  = NULL,
                   ILogger        *logger = NULL)
   {
      m_params       = p;
      m_sizer        = sizer;
      m_book         = NULL;
      m_logger       = logger;
      // m_stratParams via default constructor (sem limites).
   }

   // Construtor completo com camada "Por estratégia" (slice 6.2).
   CMksRiskManager(const CMksRiskTradeParams    &p,
                   const CMksRiskStrategyParams &sp,
                   IPositionBook  *book,
                   IPositionSizer *sizer  = NULL,
                   ILogger        *logger = NULL)
   {
      m_params      = p;
      m_stratParams = sp;
      m_sizer       = sizer;
      m_book        = book;
      m_logger      = logger;
   }

   bool Validate(MksError &err) const
   {
      if(m_params.maxLotsPerTrade < 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RISK_INVALID_PARAM,
                       "maxLotsPerTrade < 0",
                       StringFormat("maxLotsPerTrade=%.8f",
                                    m_params.maxLotsPerTrade));
         return false;
      }
      if(m_stratParams.maxOpenPositions < 0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RISK_INVALID_PARAM,
                       "maxOpenPositions < 0",
                       StringFormat("maxOpenPositions=%d",
                                    m_stratParams.maxOpenPositions));
         return false;
      }
      if(m_stratParams.maxTotalLots < 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RISK_INVALID_PARAM,
                       "maxTotalLots < 0",
                       StringFormat("maxTotalLots=%.8f",
                                    m_stratParams.maxTotalLots));
         return false;
      }
      // Camada estratégia ativa (algum limite > 0) sem book = erro de wiring.
      bool stratActive = (m_stratParams.maxOpenPositions > 0
                          || m_stratParams.maxTotalLots > 0.0);
      if(stratActive && m_book == NULL)
      {
         MKS_SET_ERROR(err, MKS_ERR_RISK_INVALID_PARAM,
                       "camada estratégia ativa sem IPositionBook injetado",
                       "");
         return false;
      }
      if(m_sizer != NULL && !m_sizer.Validate(err))
         return false;
      return true;
   }

   // Retorna true se a request passa em todas as checagens da
   // camada "Por trade". Em false, &err é preenchido com a primeira
   // rejeição encontrada e (se logger != NULL) o evento é logado
   // como WARN.
   bool CheckOrder(const MksOrderRequest &req, MksError &err)
   {
      // 1. SL obrigatório
      if(m_params.requireSl && req.slPoints <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RISK_REJECTED_SL_MISSING,
                       "SL obrigatório não informado",
                       StringFormat("slPoints=%.4f", req.slPoints));
         LogRejection("sl_missing", req, err);
         return false;
      }

      // 2. TP obrigatório
      if(m_params.requireTp && req.tpPoints <= 0.0)
      {
         MKS_SET_ERROR(err, MKS_ERR_RISK_REJECTED_TP_MISSING,
                       "TP obrigatório não informado",
                       StringFormat("tpPoints=%.4f", req.tpPoints));
         LogRejection("tp_missing", req, err);
         return false;
      }

      // 3. maxLotsPerTrade absoluto
      if(m_params.maxLotsPerTrade > 0.0 &&
         req.lots > m_params.maxLotsPerTrade)
      {
         MKS_SET_ERROR(err, MKS_ERR_RISK_REJECTED_LOTS_EXCEEDED,
                       "req.lots excede maxLotsPerTrade",
                       StringFormat("reqLots=%.8f maxLots=%.8f",
                                    req.lots, m_params.maxLotsPerTrade));
         LogRejection("lots_exceeded", req, err);
         return false;
      }

      // 4. Lots vs Sizer (opcional)
      if(m_sizer != NULL && req.slPoints > 0.0)
      {
         double maxFromSizer = 0.0;
         MksError sizerErr;
         if(!m_sizer.ComputeLots(req.slPoints, maxFromSizer, sizerErr))
         {
            // Sizer falhou: tratamos como erro de config do Risk
            // (Risk operando com sizer não-validável é estado
            // inválido). Propaga o erro do sizer com código próprio.
            // ToString() em variável local — MQL5 não passa rvalue por
            // referência mesmo const.
            string sizerErrStr = sizerErr.ToString();
            MKS_SET_ERROR(err, MKS_ERR_RISK_INVALID_PARAM,
                          "sizer interno falhou em ComputeLots",
                          sizerErrStr);
            LogRejection("sizer_error", req, err);
            return false;
         }
         if(req.lots > maxFromSizer + 1e-12)
         {
            MKS_SET_ERROR(err, MKS_ERR_RISK_REJECTED_LOTS_VS_SIZER,
                          "req.lots excede limite calculado pelo sizer",
                          StringFormat("reqLots=%.8f sizerMax=%.8f slPts=%.4f",
                                       req.lots, maxFromSizer, req.slPoints));
            LogRejection("lots_vs_sizer", req, err);
            return false;
         }
      }

      // 5. Camada Por Estratégia: max posições simultâneas
      if(m_book != NULL && m_stratParams.maxOpenPositions > 0)
      {
         int afterOpen = m_book.OpenCount() + 1;
         if(afterOpen > m_stratParams.maxOpenPositions)
         {
            MKS_SET_ERROR(err, MKS_ERR_RISK_REJECTED_OPEN_POSITIONS,
                          "abertura estouraria maxOpenPositions",
                          StringFormat("currentOpen=%d max=%d",
                                       m_book.OpenCount(),
                                       m_stratParams.maxOpenPositions));
            LogRejection("open_positions_exceeded", req, err);
            return false;
         }
      }

      // 6. Camada Por Estratégia: lots totais
      if(m_book != NULL && m_stratParams.maxTotalLots > 0.0)
      {
         double afterLots = m_book.TotalLots() + req.lots;
         if(afterLots > m_stratParams.maxTotalLots + 1e-12)
         {
            MKS_SET_ERROR(err, MKS_ERR_RISK_REJECTED_TOTAL_LOTS,
                          "abertura estouraria maxTotalLots",
                          StringFormat("currentLots=%.8f reqLots=%.8f max=%.8f",
                                       m_book.TotalLots(), req.lots,
                                       m_stratParams.maxTotalLots));
            LogRejection("total_lots_exceeded", req, err);
            return false;
         }
      }

      return true;
   }
};

#endif // MKS_ULTIMATE_CORE_RISK_CMKSRISKMANAGER_MQH
