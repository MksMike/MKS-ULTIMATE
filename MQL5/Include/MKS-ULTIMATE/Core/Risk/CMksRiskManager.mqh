//+------------------------------------------------------------------+
//| @file           : CMksRiskManager.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Risk
//| @responsibility : Middleware que valida MksOrderRequest antes da
//|                   execução. Camada "Por trade" (slice 6.1): SL/TP
//|                   obrigatórios, max lots configurado, limite via
//|                   IPositionSizer opcional. Camadas "Por estratégia"
//|                   (6.2) e "Por conta" (6.3) virão em slices futuros.
//|                   ADR-019.
//| @depends_on     : Core/Types/OrderRequest.mqh, Core/Types/Error.mqh,
//|                   Core/Interfaces/IPositionSizer.mqh,
//|                   Core/Interfaces/ILogger.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Risk/CMksRiskManager.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_RISK_CMKSRISKMANAGER_MQH
#define MKS_ULTIMATE_CORE_RISK_CMKSRISKMANAGER_MQH

#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IPositionSizer.mqh>
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

class CMksRiskManager
{
private:
   CMksRiskTradeParams m_params;
   IPositionSizer     *m_sizer;
   ILogger            *m_logger;

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
   // sizer e logger são opcionais.
   // sizer NULL: pula a checagem "lots vs sizer".
   // logger NULL: pula o log de rejeição (caller fica responsável).
   CMksRiskManager(const CMksRiskTradeParams &p,
                   IPositionSizer *sizer  = NULL,
                   ILogger        *logger = NULL)
   {
      m_params = p;
      m_sizer  = sizer;
      m_logger = logger;
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

      return true;
   }
};

#endif // MKS_ULTIMATE_CORE_RISK_CMKSRISKMANAGER_MQH
