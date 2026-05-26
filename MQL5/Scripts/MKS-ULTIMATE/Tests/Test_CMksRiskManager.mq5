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
#include <MKS-ULTIMATE/Core/Account/CMksAccountSnapshot.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakePositionBook.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeAccount.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeClock.mqh>
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
// Camada Por Estratégia (slice 6.2) — Validate
//==================================================================

void Test_Risk_Strat_Validate_OkWithBook()
{
   CMksFakePositionBook book;
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxOpenPositions = 3;
   sp.maxTotalLots     = 1.0;
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_TRUE(risk.Validate(err), "Validate ok com book");
}

void Test_Risk_Strat_Validate_ActiveWithoutBookFails()
{
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxOpenPositions = 3;
   CMksRiskManager risk(p, sp, NULL);
   MksError err;
   MKS_ASSERT_FALSE(risk.Validate(err), "Validate falha — strat ativo sem book");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_INVALID_PARAM, (int)err.code, "code=INVALID_PARAM");
}

void Test_Risk_Strat_Validate_NegativeMaxOpenFails()
{
   CMksFakePositionBook book;
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxOpenPositions = -1;
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_FALSE(risk.Validate(err), "Validate falha — maxOpen<0");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_INVALID_PARAM, (int)err.code, "code=INVALID_PARAM");
}

void Test_Risk_Strat_Validate_NegativeMaxLotsFails()
{
   CMksFakePositionBook book;
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxTotalLots = -0.1;
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_FALSE(risk.Validate(err), "Validate falha — maxTotalLots<0");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_INVALID_PARAM, (int)err.code, "code=INVALID_PARAM");
}

void Test_Risk_Strat_Validate_InactiveWithoutBookOk()
{
   // Sem limites ativos, book pode ser NULL (compatibilidade backward).
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp; // defaults: tudo zero = sem limite
   CMksRiskManager risk(p, sp, NULL);
   MksError err;
   MKS_ASSERT_TRUE(risk.Validate(err), "Validate ok — strat inativo sem book");
}

//==================================================================
// Camada Por Estratégia — maxOpenPositions
//==================================================================

void Test_Risk_Strat_OpenPositions_BelowLimit()
{
   CMksFakePositionBook book;
   book.SetOpenCount(1); // 1 aberta + 1 nova = 2 ≤ 3
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxOpenPositions = 3;
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                   "abrir abaixo do limite passa");
}

void Test_Risk_Strat_OpenPositions_AtBoundary()
{
   CMksFakePositionBook book;
   book.SetOpenCount(2); // 2 + 1 = 3 = limite (passa, não estoura)
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxOpenPositions = 3;
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                   "abrir no boundary (== limite) passa");
}

void Test_Risk_Strat_OpenPositions_Exceeded()
{
   CMksFakePositionBook book;
   book.SetOpenCount(3); // 3 + 1 = 4 > 3 limite
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxOpenPositions = 3;
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                    "abrir excedendo limite falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_OPEN_POSITIONS,
                     (int)err.code, "code=OPEN_POSITIONS");
}

void Test_Risk_Strat_OpenPositions_ZeroMeansNoLimit()
{
   CMksFakePositionBook book;
   book.SetOpenCount(999);
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxOpenPositions = 0; // sem limite
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                   "maxOpenPositions=0 desabilita check");
}

//==================================================================
// Camada Por Estratégia — maxTotalLots
//==================================================================

void Test_Risk_Strat_TotalLots_BelowLimit()
{
   CMksFakePositionBook book;
   book.SetTotalLots(0.5); // 0.5 + 0.3 = 0.8 < 1.0
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxTotalLots = 1.0;
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.3, 100.0), err),
                   "soma abaixo do limite passa");
}

void Test_Risk_Strat_TotalLots_AtBoundary()
{
   CMksFakePositionBook book;
   book.SetTotalLots(0.6); // 0.6 + 0.4 = 1.0 = limite (passa)
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxTotalLots = 1.0;
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.4, 100.0), err),
                   "soma no boundary passa");
}

void Test_Risk_Strat_TotalLots_Exceeded()
{
   CMksFakePositionBook book;
   book.SetTotalLots(0.8); // 0.8 + 0.3 = 1.1 > 1.0
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxTotalLots = 1.0;
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.3, 100.0), err),
                    "soma excedendo limite falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_TOTAL_LOTS,
                     (int)err.code, "code=TOTAL_LOTS");
}

void Test_Risk_Strat_TotalLots_ZeroMeansNoLimit()
{
   CMksFakePositionBook book;
   book.SetTotalLots(999.0);
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxTotalLots = 0.0; // sem limite
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(50.0, 100.0), err),
                   "maxTotalLots=0 desabilita check");
}

//==================================================================
// Camada Por Estratégia — ordem de avaliação
//==================================================================

void Test_Risk_Strat_OpenPositionsBeforeTotalLots()
{
   CMksFakePositionBook book;
   book.SetOpenCount(3);  // estoura openPositions
   book.SetTotalLots(2.0); // estoura totalLots também
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   sp.maxOpenPositions = 3;
   sp.maxTotalLots     = 1.0;
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 100.0), err), "rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_OPEN_POSITIONS,
                     (int)err.code, "open antes de total_lots");
}

void Test_Risk_Strat_TradeBeforeStrategy()
{
   // SL missing (camada trade) deve ser reportado antes de strategy limits.
   CMksFakePositionBook book;
   book.SetOpenCount(99); // estouraria
   CMksRiskTradeParams p;
   p.requireSl = true;
   CMksRiskStrategyParams sp;
   sp.maxOpenPositions = 3;
   CMksRiskManager risk(p, sp, GetPointer(book));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 0.0), err), "rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_SL_MISSING,
                     (int)err.code, "trade antes de strategy");
}

//==================================================================
// Camada Por Conta (slice 6.3) — Validate
//==================================================================

// Helper: monta snapshot com balance/equity configurados.
void SetupSnapshot(CMksFakeAccount &acc, CMksFakeClock &clk,
                   double balance, double equity,
                   CMksAccountSnapshot &outSnap)
{
   acc.SetBalance(balance);
   acc.SetEquity(equity);
   clk.SetNowMsc(1779494400000); // 2026-05-23 00:00 UTC
   outSnap.Init();
}

void Test_Risk_Acct_Validate_OkWithSnapshot()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap;
   ap.maxDailyLossPct = 5.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_TRUE(risk.Validate(err), "Validate ok com snapshot");
}

void Test_Risk_Acct_Validate_ActiveWithoutSnapshotFails()
{
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap;
   ap.maxDrawdownPct = 10.0;
   CMksRiskManager risk(p, sp, ap, NULL, NULL);
   MksError err;
   MKS_ASSERT_FALSE(risk.Validate(err), "Validate falha — acct ativo sem snapshot");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_INVALID_PARAM, (int)err.code, "code=INVALID_PARAM");
}

void Test_Risk_Acct_Validate_NegativeDailyLossFails()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap;
   ap.maxDailyLossPct = -1.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_FALSE(risk.Validate(err), "Validate falha — dailyLoss<0");
}

void Test_Risk_Acct_Validate_NegativeDrawdownFails()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap;
   ap.maxDrawdownPct = -2.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_FALSE(risk.Validate(err), "Validate falha — drawdown<0");
}

void Test_Risk_Acct_Validate_NegativeMinEquityFails()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap;
   ap.minEquityAbs = -100.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_FALSE(risk.Validate(err), "Validate falha — minEquity<0");
}

void Test_Risk_Acct_Validate_InactiveWithoutSnapshotOk()
{
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; // defaults: tudo zero
   CMksRiskManager risk(p, sp, ap, NULL, NULL);
   MksError err;
   MKS_ASSERT_TRUE(risk.Validate(err), "Validate ok — acct inativo sem snapshot");
}

//==================================================================
// Camada Por Conta — maxDailyLossPct
//==================================================================

void Test_Risk_Acct_DailyLoss_BelowLimit()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   // Perda de 3% (não atinge limite de 5%)
   acc.SetEquity(9700.0); snap.Update();

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.maxDailyLossPct = 5.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                   "perda abaixo do limite passa");
}

void Test_Risk_Acct_DailyLoss_AtBoundary()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   // Perda exatamente 5%
   acc.SetEquity(9500.0); snap.Update();

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.maxDailyLossPct = 5.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                    "perda no limite (== max) rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_DAILY_LOSS, (int)err.code, "code=DAILY_LOSS");
}

void Test_Risk_Acct_DailyLoss_Exceeded()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   // Perda de 7%
   acc.SetEquity(9300.0); snap.Update();

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.maxDailyLossPct = 5.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 100.0), err), "rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_DAILY_LOSS, (int)err.code, "code=DAILY_LOSS");
}

void Test_Risk_Acct_DailyLoss_ZeroMeansNoLimit()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   acc.SetEquity(5000.0); snap.Update(); // 50% perda

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.maxDailyLossPct = 0.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                   "dailyLoss=0 desabilita check");
}

//==================================================================
// Camada Por Conta — maxDrawdownPct
//==================================================================

void Test_Risk_Acct_Drawdown_BelowLimit()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   acc.SetEquity(12000.0); snap.Update(); // peak
   acc.SetEquity(11400.0); snap.Update(); // -5%

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.maxDrawdownPct = 10.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                   "drawdown abaixo do limite passa");
}

void Test_Risk_Acct_Drawdown_AtBoundary()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   acc.SetEquity(12000.0); snap.Update();
   acc.SetEquity(10800.0); snap.Update(); // exatamente -10%

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.maxDrawdownPct = 10.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                    "drawdown no limite (== max) rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_DRAWDOWN, (int)err.code, "code=DRAWDOWN");
}

void Test_Risk_Acct_Drawdown_Exceeded()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   acc.SetEquity(12000.0); snap.Update();
   acc.SetEquity(9600.0);  snap.Update(); // -20%

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.maxDrawdownPct = 10.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 100.0), err), "rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_DRAWDOWN, (int)err.code, "code=DRAWDOWN");
}

void Test_Risk_Acct_Drawdown_ZeroMeansNoLimit()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   acc.SetEquity(12000.0); snap.Update();
   acc.SetEquity(2000.0);  snap.Update(); // -83%

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.maxDrawdownPct = 0.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                   "drawdown=0 desabilita check");
}

//==================================================================
// Camada Por Conta — minEquityAbs (circuit breaker)
//==================================================================

void Test_Risk_Acct_MinEquity_Above()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   acc.SetEquity(6000.0); snap.Update();

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.minEquityAbs = 5000.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                   "equity acima do mínimo passa");
}

void Test_Risk_Acct_MinEquity_AtBoundary()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   acc.SetEquity(5000.0); snap.Update();

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.minEquityAbs = 5000.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   // Check é "< minEquity"; equity == minEquity passa.
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                   "equity no boundary (== min) passa");
}

void Test_Risk_Acct_MinEquity_Below()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   acc.SetEquity(4500.0); snap.Update();

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.minEquityAbs = 5000.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                    "equity abaixo do mínimo rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_MIN_EQUITY, (int)err.code, "code=MIN_EQUITY");
}

void Test_Risk_Acct_MinEquity_ZeroMeansNoLimit()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   acc.SetEquity(10.0); snap.Update();

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap; ap.minEquityAbs = 0.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                   "minEquity=0 desabilita check");
}

//==================================================================
// Camada Por Conta — ordem de avaliação
//==================================================================

void Test_Risk_Acct_StrategyBeforeAccount()
{
   CMksFakePositionBook book; book.SetOpenCount(3);
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   acc.SetEquity(8000.0); snap.Update(); // -20% (estouraria daily loss tb)

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp; sp.maxOpenPositions = 3;
   CMksRiskAccountParams ap;  ap.maxDailyLossPct = 5.0;
   CMksRiskManager risk(p, sp, ap, GetPointer(book), GetPointer(snap));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 100.0), err), "rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_OPEN_POSITIONS,
                     (int)err.code, "strategy antes de account");
}

void Test_Risk_Acct_DailyLossBeforeDrawdown()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   acc.SetEquity(12000.0); snap.Update(); // peak
   acc.SetEquity(8000.0);  snap.Update(); // daily loss -20%, drawdown -33%

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap;
   ap.maxDailyLossPct = 5.0;
   ap.maxDrawdownPct  = 10.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 100.0), err), "rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_DAILY_LOSS,
                     (int)err.code, "daily_loss antes de drawdown");
}

void Test_Risk_Acct_DrawdownBeforeMinEquity()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);
   acc.SetEquity(12000.0); snap.Update();
   acc.SetEquity(4000.0);  snap.Update(); // drawdown -66%, equity < 5000

   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap;
   ap.maxDrawdownPct = 10.0;
   ap.minEquityAbs   = 5000.0;
   // dailyLoss desligado pra isolar drawdown vs minEquity
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));
   MksError err;
   MKS_ASSERT_FALSE(risk.CheckOrder(MakeReq(0.1, 100.0), err), "rejeita");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_DRAWDOWN,
                     (int)err.code, "drawdown antes de minEquity");
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

//==================================================================
// CheckOrder refresh proativo do snapshot (Fase 9 prep)
//==================================================================

// Garante que CheckOrder rejeita por daily loss mesmo se o EA esquecer
// de chamar snapshot.Update() entre os ticks. Pré-Fase 9 prep: o EA da
// Fase 9 não deve perder essa proteção por bug de esquecimento.
void Test_Risk_CheckOrder_AutoUpdatesSnapshotForFreshness()
{
   CMksFakeAccount acc; CMksFakeClock clk;
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   SetupSnapshot(acc, clk, 10000.0, 10000.0, snap);

   // 5% de daily loss → -500 USD → equity abaixo de 9500 rejeita.
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap;
   ap.maxDailyLossPct = 5.0;
   CMksRiskManager risk(p, sp, ap, NULL, GetPointer(snap));

   // EA "esquece" de chamar snap.Update() — força equity baixa direto
   // no account fake. snapshot ainda enxerga equity=10000 stale.
   acc.SetEquity(9400.0);

   MksError err;
   bool result = risk.CheckOrder(MakeReq(0.1, 100.0), err);
   MKS_ASSERT_FALSE(result, "CheckOrder rejeita por daily loss usando equity fresca");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_RISK_REJECTED_DAILY_LOSS, (int)err.code,
                     "code = DAILY_LOSS (snapshot foi atualizado pelo CheckOrder)");
}

void Test_Risk_CheckOrder_AutoUpdateNoOpWithoutSnapshot()
{
   // Sem snapshot injetado, CheckOrder não tenta atualizar nada — nenhum
   // crash, comportamento legado preservado.
   CMksRiskTradeParams p;
   CMksRiskStrategyParams sp;
   CMksRiskAccountParams ap;
   // ap inativo (todos os limites em 0)
   CMksRiskManager risk(p, sp, ap, NULL, NULL);

   MksError err;
   MKS_ASSERT_TRUE(risk.CheckOrder(MakeReq(0.1, 100.0), err),
                   "CheckOrder aceita sem snapshot e sem crash");
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

   // Camada Por Estratégia (slice 6.2)
   MKS_RUN(Test_Risk_Strat_Validate_OkWithBook);
   MKS_RUN(Test_Risk_Strat_Validate_ActiveWithoutBookFails);
   MKS_RUN(Test_Risk_Strat_Validate_NegativeMaxOpenFails);
   MKS_RUN(Test_Risk_Strat_Validate_NegativeMaxLotsFails);
   MKS_RUN(Test_Risk_Strat_Validate_InactiveWithoutBookOk);
   MKS_RUN(Test_Risk_Strat_OpenPositions_BelowLimit);
   MKS_RUN(Test_Risk_Strat_OpenPositions_AtBoundary);
   MKS_RUN(Test_Risk_Strat_OpenPositions_Exceeded);
   MKS_RUN(Test_Risk_Strat_OpenPositions_ZeroMeansNoLimit);
   MKS_RUN(Test_Risk_Strat_TotalLots_BelowLimit);
   MKS_RUN(Test_Risk_Strat_TotalLots_AtBoundary);
   MKS_RUN(Test_Risk_Strat_TotalLots_Exceeded);
   MKS_RUN(Test_Risk_Strat_TotalLots_ZeroMeansNoLimit);
   MKS_RUN(Test_Risk_Strat_OpenPositionsBeforeTotalLots);
   MKS_RUN(Test_Risk_Strat_TradeBeforeStrategy);

   // Camada Por Conta (slice 6.3)
   MKS_RUN(Test_Risk_Acct_Validate_OkWithSnapshot);
   MKS_RUN(Test_Risk_Acct_Validate_ActiveWithoutSnapshotFails);
   MKS_RUN(Test_Risk_Acct_Validate_NegativeDailyLossFails);
   MKS_RUN(Test_Risk_Acct_Validate_NegativeDrawdownFails);
   MKS_RUN(Test_Risk_Acct_Validate_NegativeMinEquityFails);
   MKS_RUN(Test_Risk_Acct_Validate_InactiveWithoutSnapshotOk);
   MKS_RUN(Test_Risk_Acct_DailyLoss_BelowLimit);
   MKS_RUN(Test_Risk_Acct_DailyLoss_AtBoundary);
   MKS_RUN(Test_Risk_Acct_DailyLoss_Exceeded);
   MKS_RUN(Test_Risk_Acct_DailyLoss_ZeroMeansNoLimit);
   MKS_RUN(Test_Risk_Acct_Drawdown_BelowLimit);
   MKS_RUN(Test_Risk_Acct_Drawdown_AtBoundary);
   MKS_RUN(Test_Risk_Acct_Drawdown_Exceeded);
   MKS_RUN(Test_Risk_Acct_Drawdown_ZeroMeansNoLimit);
   MKS_RUN(Test_Risk_Acct_MinEquity_Above);
   MKS_RUN(Test_Risk_Acct_MinEquity_AtBoundary);
   MKS_RUN(Test_Risk_Acct_MinEquity_Below);
   MKS_RUN(Test_Risk_Acct_MinEquity_ZeroMeansNoLimit);
   MKS_RUN(Test_Risk_Acct_StrategyBeforeAccount);
   MKS_RUN(Test_Risk_Acct_DailyLossBeforeDrawdown);
   MKS_RUN(Test_Risk_Acct_DrawdownBeforeMinEquity);

   MKS_RUN(Test_Risk_CheckOrder_NoLoggerNoFault);

   MKS_RUN(Test_Risk_CheckOrder_AutoUpdatesSnapshotForFreshness);
   MKS_RUN(Test_Risk_CheckOrder_AutoUpdateNoOpWithoutSnapshot);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
