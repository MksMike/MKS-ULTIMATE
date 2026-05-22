//+------------------------------------------------------------------+
//| @file           : Test_CMksRiskManager.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksRiskManager — camada "Por trade"
//|                   (slice 6.1). Validate e CheckOrder cobrindo SL/TP
//|                   obrigatórios, maxLotsPerTrade absoluto, integração
//|                   com IPositionSizer. ADR-019.
//| @depends_on     : Core/Risk/CMksRiskManager.mqh,
//|                   Core/Trade/CMksFixedLotSizer.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh,
//|                   Core/Testing/Mocks/CMksFakeAccount.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksRiskManager.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Risk/CMksRiskManager.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksFixedLotSizer.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//+------------------------------------------------------------------+
//| Helper: monta uma MksOrderRequest com defaults razoáveis            |
//+------------------------------------------------------------------+
MksOrderRequest MakeReq(double lots, double slPoints, double tpPoints = 0.0,
                        ENUM_MKS_ORDER_SIDE side = MKS_ORDER_BUY)
{
   MksOrderRequest r;
   r.side     = side;
   r.lots     = lots;
   r.slPoints = slPoints;
   r.tpPoints = tpPoints;
   r.comment  = "test";
   return r;
}

//==================================================================
// Validate
//==================================================================

void Test_Risk_Validate_OkDefaults()
{
   CMksRiskTradeParams p;
   CMksRiskManager risk(p);
   MksError err;
   MKS_ASSERT_TRUE(risk.Validate(err), "validate ok defaults");
   MKS_ASSERT_FALSE(err.HasError(), "sem erro");
}

void Test_Risk_Validate_NegativeMaxLots()
{
   CMksRiskTradeParams p;
   p.maxLotsPerTrade = -0.5;
   CMksRiskManager risk(p);
   MksError err;
   MKS_ASSERT_FALSE(risk.Validate(err), "validate falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_INVALID_PARAM, (int)err.code,
                     "code=INVALID_PARAM");
}

void Test_Risk_Validate_SizerInvalidPropagates()
{
   CMksFakeSymbol sym;
   // Sizer com config inválida: fixedLots=0 dispara o Validate do sizer.
   CMksFixedLotSizer sizer(GetPointer(sym), 0.0);
   CMksRiskTradeParams p;
   CMksRiskManager risk(p, GetPointer(sizer));
   MksError err;
   MKS_ASSERT_FALSE(risk.Validate(err), "validate falha pelo sizer");
}

//==================================================================
// CheckOrder — SL obrigatório
//==================================================================

void Test_Risk_CheckOrder_SlPresent()
{
   CMksRiskTradeParams p; // requireSl=true por default
   CMksRiskManager risk(p);
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                   "check ok com SL");
   MKS_ASSERT_FALSE(err.HasError(), "sem erro");
}

void Test_Risk_CheckOrder_SlMissing()
{
   CMksRiskTradeParams p;
   CMksRiskManager risk(p);
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 0.0), err),
                    "check falha sem SL");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_SL_MISSING,
                     (int)err.code, "code=SL_MISSING");
}

void Test_Risk_CheckOrder_SlMissingButRequireSlFalse()
{
   CMksRiskTradeParams p;
   p.requireSl = false;
   CMksRiskManager risk(p);
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 0.0), err),
                   "check passa sem SL quando requireSl=false");
}

//==================================================================
// CheckOrder — TP opcional / obrigatório
//==================================================================

void Test_Risk_CheckOrder_TpDefaultNotRequired()
{
   CMksRiskTradeParams p; // requireTp=false por default
   CMksRiskManager risk(p);
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0, 0.0), err),
                   "check ok sem TP por default");
}

void Test_Risk_CheckOrder_TpRequiredAndMissing()
{
   CMksRiskTradeParams p;
   p.requireTp = true;
   CMksRiskManager risk(p);
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 100.0, 0.0), err),
                    "check falha sem TP");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_TP_MISSING,
                     (int)err.code, "code=TP_MISSING");
}

void Test_Risk_CheckOrder_TpRequiredAndPresent()
{
   CMksRiskTradeParams p;
   p.requireTp = true;
   CMksRiskManager risk(p);
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0, 150.0), err),
                   "check ok com TP");
}

//==================================================================
// CheckOrder — maxLotsPerTrade
//==================================================================

void Test_Risk_CheckOrder_MaxLotsExceeded()
{
   CMksRiskTradeParams p;
   p.maxLotsPerTrade = 1.0;
   CMksRiskManager risk(p);
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(2.0, 100.0), err),
                    "check falha quando lots > max");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_LOTS_EXCEEDED,
                     (int)err.code, "code=LOTS_EXCEEDED");
}

void Test_Risk_CheckOrder_MaxLotsAtBoundary()
{
   CMksRiskTradeParams p;
   p.maxLotsPerTrade = 1.0;
   CMksRiskManager risk(p);
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(1.0, 100.0), err),
                   "check passa quando lots == max");
}

void Test_Risk_CheckOrder_MaxLotsZeroMeansNoLimit()
{
   CMksRiskTradeParams p;
   p.maxLotsPerTrade = 0.0;
   CMksRiskManager risk(p);
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(1000.0, 100.0), err),
                   "lots gigante passa quando max=0");
}

//==================================================================
// CheckOrder — sizer
//==================================================================

void Test_Risk_CheckOrder_NoSizerNoCheck()
{
   CMksRiskTradeParams p;
   CMksRiskManager risk(p); // sem sizer
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(100.0, 100.0), err),
                   "lots grande passa sem sizer");
}

void Test_Risk_CheckOrder_SizerOk()
{
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), 1.0); // max=1.0
   CMksRiskTradeParams p;
   CMksRiskManager risk(p, GetPointer(sizer));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.5, 100.0), err),
                   "lots abaixo do sizer max passa");
}

void Test_Risk_CheckOrder_SizerAtBoundary()
{
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), 1.0);
   CMksRiskTradeParams p;
   CMksRiskManager risk(p, GetPointer(sizer));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(1.0, 100.0), err),
                   "lots = sizer max passa");
}

void Test_Risk_CheckOrder_SizerExceeded()
{
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), 0.5);
   CMksRiskTradeParams p;
   CMksRiskManager risk(p, GetPointer(sizer));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(1.0, 100.0), err),
                    "lots > sizer max falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_LOTS_VS_SIZER,
                     (int)err.code, "code=LOTS_VS_SIZER");
}

void Test_Risk_CheckOrder_SizerErrorBecomesRiskError()
{
   CMksFakeSymbol sym;
   // Sizer com config inválida: fixedLots não múltiplo do step
   sym.SetVolumeStep(0.10);
   sym.SetVolumeMin(0.10);
   CMksFixedLotSizer sizer(GetPointer(sym), 0.13);
   CMksRiskTradeParams p;
   CMksRiskManager risk(p, GetPointer(sizer));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.10, 100.0), err),
                    "sizer falhando vira erro do risk");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_INVALID_PARAM,
                     (int)err.code, "code=INVALID_PARAM");
}

//==================================================================
// CheckOrder — ordem de avaliação (SL antes de TP antes de lots antes
// de sizer). Garante que primeiro motivo de rejeição é registrado.
//==================================================================

void Test_Risk_CheckOrder_SlRejectedBeforeTp()
{
   CMksRiskTradeParams p;
   p.requireSl = true;
   p.requireTp = true;
   CMksRiskManager risk(p);
   MksError err;
   // Ambos faltam — espera SL_MISSING (avaliado primeiro)
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 0.0, 0.0), err),
                    "rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_SL_MISSING,
                     (int)err.code, "SL antes de TP");
}

void Test_Risk_CheckOrder_TpRejectedBeforeMaxLots()
{
   CMksRiskTradeParams p;
   p.requireTp = true;
   p.maxLotsPerTrade = 1.0;
   CMksRiskManager risk(p);
   MksError err;
   // TP falta + lots gigante — espera TP_MISSING (avaliado primeiro)
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(10.0, 100.0, 0.0), err),
                    "rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_TP_MISSING,
                     (int)err.code, "TP antes de lots");
}

void Test_Risk_CheckOrder_MaxLotsRejectedBeforeSizer()
{
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), 5.0); // sizer permite 5.0
   CMksRiskTradeParams p;
   p.maxLotsPerTrade = 1.0; // mas max absoluto é 1.0
   CMksRiskManager risk(p, GetPointer(sizer));
   MksError err;
   // lots=2.0: passa pelo sizer (<=5) mas excede maxLotsPerTrade
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(2.0, 100.0), err),
                    "rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_LOTS_EXCEEDED,
                     (int)err.code, "lots antes de sizer");
}

//==================================================================
// CheckOrder — sem logger não causa crash
//==================================================================

void Test_Risk_CheckOrder_NoLoggerNoFault()
{
   CMksRiskTradeParams p;
   CMksRiskManager risk(p); // logger=NULL
   MksError err;
   // Força uma rejeição — não deve crashar mesmo sem logger
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 0.0), err),
                    "rejeita sem logger sem crash");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_SL_MISSING,
                     (int)err.code, "code correto");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksRiskManager ===");

   MKS_RUN(Test_Risk_Validate_OkDefaults);
   MKS_RUN(Test_Risk_Validate_NegativeMaxLots);
   MKS_RUN(Test_Risk_Validate_SizerInvalidPropagates);

   MKS_RUN(Test_Risk_CheckOrder_SlPresent);
   MKS_RUN(Test_Risk_CheckOrder_SlMissing);
   MKS_RUN(Test_Risk_CheckOrder_SlMissingButRequireSlFalse);

   MKS_RUN(Test_Risk_CheckOrder_TpDefaultNotRequired);
   MKS_RUN(Test_Risk_CheckOrder_TpRequiredAndMissing);
   MKS_RUN(Test_Risk_CheckOrder_TpRequiredAndPresent);

   MKS_RUN(Test_Risk_CheckOrder_MaxLotsExceeded);
   MKS_RUN(Test_Risk_CheckOrder_MaxLotsAtBoundary);
   MKS_RUN(Test_Risk_CheckOrder_MaxLotsZeroMeansNoLimit);

   MKS_RUN(Test_Risk_CheckOrder_NoSizerNoCheck);
   MKS_RUN(Test_Risk_CheckOrder_SizerOk);
   MKS_RUN(Test_Risk_CheckOrder_SizerAtBoundary);
   MKS_RUN(Test_Risk_CheckOrder_SizerExceeded);
   MKS_RUN(Test_Risk_CheckOrder_SizerErrorBecomesRiskError);

   MKS_RUN(Test_Risk_CheckOrder_SlRejectedBeforeTp);
   MKS_RUN(Test_Risk_CheckOrder_TpRejectedBeforeMaxLots);
   MKS_RUN(Test_Risk_CheckOrder_MaxLotsRejectedBeforeSizer);

   MKS_RUN(Test_Risk_CheckOrder_NoLoggerNoFault);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
