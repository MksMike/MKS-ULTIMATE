//+------------------------------------------------------------------+
//| @file           : Test_CMksPositionSizer.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksFixedLotSizer e CMksPercentRiskSizer
//|                   — Validate (configuração) e ComputeLots (runtime).
//|                   Cobre out-of-range, floor para VolumeStep, e
//|                   correção Point/TickSize. ADR-019.
//| @depends_on     : Core/Trade/CMksFixedLotSizer.mqh,
//|                   Core/Trade/CMksPercentRiskSizer.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh,
//|                   Core/Testing/Mocks/CMksFakeAccount.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksPositionSizer.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Trade/CMksFixedLotSizer.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksPercentRiskSizer.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeAccount.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//==================================================================
// CMksFixedLotSizer
//==================================================================

//+------------------------------------------------------------------+
//| 1. Validate passa com config padrão                               |
//+------------------------------------------------------------------+
void Test_FixedLot_Validate_Ok()
{
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), 0.10);
   MksError err;
   MKS_ASSERT_TRUE(sizer.Validate(err), "validate ok");
   MKS_ASSERT_FALSE(err.HasError(), "sem erro");
}

//+------------------------------------------------------------------+
//| 2. Validate falha com symbol NULL                                 |
//+------------------------------------------------------------------+
void Test_FixedLot_Validate_NullSymbol()
{
   CMksFixedLotSizer sizer(NULL, 0.10);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                     (int)err.code, "code=INVALID_PARAM");
}

//+------------------------------------------------------------------+
//| 3. Validate falha com fixedLots <= 0                              |
//+------------------------------------------------------------------+
void Test_FixedLot_Validate_FixedLotsZero()
{
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), 0.0);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                     (int)err.code, "code=INVALID_PARAM");
}

void Test_FixedLot_Validate_FixedLotsNegative()
{
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), -0.5);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                     (int)err.code, "code=INVALID_PARAM");
}

//+------------------------------------------------------------------+
//| 4. Validate falha com volume step inválido                        |
//+------------------------------------------------------------------+
void Test_FixedLot_Validate_VolumeStepInvalid()
{
   CMksFakeSymbol sym;
   sym.SetVolumeStep(0.0);
   CMksFixedLotSizer sizer(GetPointer(sym), 0.10);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                     (int)err.code, "code=INVALID_PARAM");
}

//+------------------------------------------------------------------+
//| 5. Validate falha quando max < min                                |
//+------------------------------------------------------------------+
void Test_FixedLot_Validate_VolumeMaxLessThanMin()
{
   CMksFakeSymbol sym;
   sym.SetVolumeMin(1.0);
   sym.SetVolumeMax(0.5);
   CMksFixedLotSizer sizer(GetPointer(sym), 0.10);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
}

//+------------------------------------------------------------------+
//| 6. Validate falha quando fixedLots não é múltiplo de step         |
//+------------------------------------------------------------------+
void Test_FixedLot_Validate_NotMultipleOfStep()
{
   CMksFakeSymbol sym;
   sym.SetVolumeStep(0.10);
   sym.SetVolumeMin(0.10);
   CMksFixedLotSizer sizer(GetPointer(sym), 0.13);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                     (int)err.code, "code=INVALID_PARAM");
}

//+------------------------------------------------------------------+
//| 7. Validate falha quando fixedLots < VolumeMin                    |
//+------------------------------------------------------------------+
void Test_FixedLot_Validate_BelowVolumeMin()
{
   CMksFakeSymbol sym;
   sym.SetVolumeMin(0.50);
   CMksFixedLotSizer sizer(GetPointer(sym), 0.10);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_OUT_OF_RANGE,
                     (int)err.code, "code=OUT_OF_RANGE");
}

//+------------------------------------------------------------------+
//| 8. Validate falha quando fixedLots > VolumeMax                    |
//+------------------------------------------------------------------+
void Test_FixedLot_Validate_AboveVolumeMax()
{
   CMksFakeSymbol sym;
   sym.SetVolumeMax(0.50);
   CMksFixedLotSizer sizer(GetPointer(sym), 1.00);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_OUT_OF_RANGE,
                     (int)err.code, "code=OUT_OF_RANGE");
}

//+------------------------------------------------------------------+
//| 9. ComputeLots OK e ignora slDistance                             |
//+------------------------------------------------------------------+
void Test_FixedLot_ComputeLots_Ok()
{
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), 0.25);
   MksError err;
   double lots = 0.0;
   MKS_ASSERT_TRUE(sizer.ComputeLots(100.0, lots, err), "compute ok");
   MKS_ASSERT_NEAR_DOUBLE(0.25, lots, 1e-9, "lots = fixed");
}

void Test_FixedLot_ComputeLots_IgnoresSlDistance()
{
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), 0.42);
   MksError err;
   double lotsA = 0.0, lotsB = 0.0;
   MKS_ASSERT_TRUE(sizer.ComputeLots(10.0, lotsA, err), "compute A");
   MKS_ASSERT_TRUE(sizer.ComputeLots(1000.0, lotsB, err), "compute B");
   MKS_ASSERT_NEAR_DOUBLE(lotsA, lotsB, 1e-9, "mesmo lots para slDist diferentes");
   MKS_ASSERT_NEAR_DOUBLE(0.42, lotsA, 1e-9, "lots = fixed");
}

//+------------------------------------------------------------------+
//| 10. ComputeLots falha com slDistance <= 0                         |
//+------------------------------------------------------------------+
void Test_FixedLot_ComputeLots_SlDistanceZero()
{
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), 0.10);
   MksError err;
   double lots = 0.0;
   MKS_ASSERT_FALSE(sizer.ComputeLots(0.0, lots, err), "compute falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_INVALID_INPUT,
                     (int)err.code, "code=INVALID_INPUT");
}

void Test_FixedLot_ComputeLots_SlDistanceNegative()
{
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), 0.10);
   MksError err;
   double lots = 0.0;
   MKS_ASSERT_FALSE(sizer.ComputeLots(-1.0, lots, err), "compute falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_INVALID_INPUT,
                     (int)err.code, "code=INVALID_INPUT");
}

//==================================================================
// CMksPercentRiskSizer
//==================================================================

//+------------------------------------------------------------------+
//| 11. Validate passa com config padrão                              |
//+------------------------------------------------------------------+
void Test_PercentRisk_Validate_Ok()
{
   CMksFakeSymbol sym;
   CMksFakeAccount acc;
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 1.0);
   MksError err;
   MKS_ASSERT_TRUE(sizer.Validate(err), "validate ok");
   MKS_ASSERT_FALSE(err.HasError(), "sem erro");
}

void Test_PercentRisk_Validate_NullSymbol()
{
   CMksFakeAccount acc;
   CMksPercentRiskSizer sizer(NULL, GetPointer(acc), 1.0);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                     (int)err.code, "code=INVALID_PARAM");
}

void Test_PercentRisk_Validate_NullAccount()
{
   CMksFakeSymbol sym;
   CMksPercentRiskSizer sizer(GetPointer(sym), NULL, 1.0);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
}

void Test_PercentRisk_Validate_RiskPctZero()
{
   CMksFakeSymbol sym;
   CMksFakeAccount acc;
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 0.0);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_INVALID_PARAM,
                     (int)err.code, "code=INVALID_PARAM");
}

void Test_PercentRisk_Validate_RiskPctNegative()
{
   CMksFakeSymbol sym;
   CMksFakeAccount acc;
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), -1.0);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
}

void Test_PercentRisk_Validate_RiskPctAboveHundred()
{
   CMksFakeSymbol sym;
   CMksFakeAccount acc;
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 150.0);
   MksError err;
   MKS_ASSERT_FALSE(sizer.Validate(err), "validate falha");
}

//+------------------------------------------------------------------+
//| 12. ComputeLots — caso base                                       |
//| balance=10000, risk=1%, slDist=100, mppl=1.0 → lots=1.0           |
//+------------------------------------------------------------------+
void Test_PercentRisk_ComputeLots_BasicCase()
{
   CMksFakeSymbol sym;   // defaults: point=0.01, tickSize=0.01, tickValue=1
   CMksFakeAccount acc;  // default: balance=10000
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 1.0);
   MksError err;
   double lots = 0.0;
   MKS_ASSERT_TRUE(sizer.ComputeLots(100.0, lots, err), "compute ok");
   // risk=100, mppl=1, lotsRaw=100/(100*1)=1.0
   MKS_ASSERT_NEAR_DOUBLE(1.0, lots, 1e-9, "lots=1.0");
}

//+------------------------------------------------------------------+
//| 13. ComputeLots floor para step                                   |
//+------------------------------------------------------------------+
void Test_PercentRisk_ComputeLots_FloorToStep()
{
   CMksFakeSymbol sym;
   sym.SetVolumeStep(0.10);
   sym.SetVolumeMin(0.10);
   CMksFakeAccount acc;
   acc.SetBalance(1570.0); // gera lotsRaw=0.157 com risk=1%/sl=100
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 1.0);
   MksError err;
   double lots = 0.0;
   MKS_ASSERT_TRUE(sizer.ComputeLots(100.0, lots, err), "compute ok");
   // lotsRaw=15.7/(100*1)=0.157, step=0.10 → floor para 0.10
   MKS_ASSERT_NEAR_DOUBLE(0.10, lots, 1e-9, "floor 0.157 step 0.10 = 0.10");
}

//+------------------------------------------------------------------+
//| 14. ComputeLots out-of-range below min                            |
//+------------------------------------------------------------------+
void Test_PercentRisk_ComputeLots_BelowVolumeMin()
{
   CMksFakeSymbol sym;          // step=0.01, min=0.01
   CMksFakeAccount acc;
   acc.SetBalance(0.5);         // risk 1% = 0.005 → lotsRaw=0.00005, floor=0.0
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 1.0);
   MksError err;
   double lots = -1.0;
   MKS_ASSERT_FALSE(sizer.ComputeLots(100.0, lots, err), "compute falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_OUT_OF_RANGE,
                     (int)err.code, "code=OUT_OF_RANGE");
   MKS_ASSERT_NEAR_DOUBLE(0.0, lots, 1e-9, "lots zerado em erro");
}

//+------------------------------------------------------------------+
//| 15. ComputeLots out-of-range above max                            |
//+------------------------------------------------------------------+
void Test_PercentRisk_ComputeLots_AboveVolumeMax()
{
   CMksFakeSymbol sym;          // max=100 default
   sym.SetVolumeMax(50.0);
   CMksFakeAccount acc;
   acc.SetBalance(10000000.0);  // balance enorme
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 1.0);
   MksError err;
   double lots = -1.0;
   MKS_ASSERT_FALSE(sizer.ComputeLots(100.0, lots, err), "compute falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_OUT_OF_RANGE,
                     (int)err.code, "code=OUT_OF_RANGE");
}

//+------------------------------------------------------------------+
//| 16. ComputeLots falha com slDist=0                                |
//+------------------------------------------------------------------+
void Test_PercentRisk_ComputeLots_SlDistanceZero()
{
   CMksFakeSymbol sym;
   CMksFakeAccount acc;
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 1.0);
   MksError err;
   double lots = 0.0;
   MKS_ASSERT_FALSE(sizer.ComputeLots(0.0, lots, err), "compute falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_INVALID_INPUT,
                     (int)err.code, "code=INVALID_INPUT");
}

//+------------------------------------------------------------------+
//| 17. ComputeLots falha com balance <= 0                            |
//+------------------------------------------------------------------+
void Test_PercentRisk_ComputeLots_BalanceZero()
{
   CMksFakeSymbol sym;
   CMksFakeAccount acc;
   acc.SetBalance(0.0);
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 1.0);
   MksError err;
   double lots = 0.0;
   MKS_ASSERT_FALSE(sizer.ComputeLots(100.0, lots, err), "compute falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_INVALID_INPUT,
                     (int)err.code, "code=INVALID_INPUT");
}

void Test_PercentRisk_ComputeLots_BalanceNegative()
{
   CMksFakeSymbol sym;
   CMksFakeAccount acc;
   acc.SetBalance(-100.0);
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 1.0);
   MksError err;
   double lots = 0.0;
   MKS_ASSERT_FALSE(sizer.ComputeLots(100.0, lots, err), "compute falha");
}

//+------------------------------------------------------------------+
//| 18. ComputeLots falha com TickValue inválido                      |
//+------------------------------------------------------------------+
void Test_PercentRisk_ComputeLots_TickValueZero()
{
   CMksFakeSymbol sym;
   sym.SetTickValue(0.0);
   CMksFakeAccount acc;
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 1.0);
   MksError err;
   double lots = 0.0;
   MKS_ASSERT_FALSE(sizer.ComputeLots(100.0, lots, err), "compute falha");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_TRADE_SIZER_INVALID_INPUT,
                     (int)err.code, "code=INVALID_INPUT");
}

//+------------------------------------------------------------------+
//| 19. ComputeLots quando Point != TickSize (ativo com tick discreto)|
//| Ex: futuro com Point=0.01, TickSize=0.25 (tick size > point)      |
//| mppl = TickValue * Point / TickSize = 1 * 0.01 / 0.25 = 0.04      |
//| balance=10000, risk=1%, slDist=100                                |
//| riskAmount=100, lotsRaw = 100/(100*0.04) = 25.0                   |
//+------------------------------------------------------------------+
void Test_PercentRisk_ComputeLots_PointDifferentFromTickSize()
{
   CMksFakeSymbol sym;
   sym.SetPoint(0.01);
   sym.SetTickSize(0.25);
   sym.SetTickValue(1.0);
   sym.SetVolumeMax(100.0);
   CMksFakeAccount acc;  // balance=10000
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 1.0);
   MksError err;
   double lots = 0.0;
   MKS_ASSERT_TRUE(sizer.ComputeLots(100.0, lots, err), "compute ok");
   MKS_ASSERT_NEAR_DOUBLE(25.0, lots, 1e-9,
                          "lots com point/tickSize diferentes");
}

//+------------------------------------------------------------------+
//| 20. Sanity: SL maior → lots menor                                 |
//+------------------------------------------------------------------+
void Test_PercentRisk_ComputeLots_BiggerSlMeansSmallerLots()
{
   CMksFakeSymbol sym;
   CMksFakeAccount acc;
   CMksPercentRiskSizer sizer(GetPointer(sym), GetPointer(acc), 1.0);
   MksError err;
   double lotsA = 0.0, lotsB = 0.0;
   MKS_ASSERT_TRUE(sizer.ComputeLots(100.0, lotsA, err), "compute A");
   MKS_ASSERT_TRUE(sizer.ComputeLots(200.0, lotsB, err), "compute B");
   MKS_ASSERT_TRUE(lotsB < lotsA, "SL maior → lots menor");
}

//+------------------------------------------------------------------+
//| 21. Sanity: risk% maior → lots maior                              |
//+------------------------------------------------------------------+
void Test_PercentRisk_ComputeLots_BiggerRiskMeansBiggerLots()
{
   CMksFakeSymbol sym;
   CMksFakeAccount acc;
   CMksPercentRiskSizer s1(GetPointer(sym), GetPointer(acc), 1.0);
   CMksPercentRiskSizer s2(GetPointer(sym), GetPointer(acc), 2.0);
   MksError err;
   double lotsA = 0.0, lotsB = 0.0;
   MKS_ASSERT_TRUE(s1.ComputeLots(100.0, lotsA, err), "compute A");
   MKS_ASSERT_TRUE(s2.ComputeLots(100.0, lotsB, err), "compute B");
   MKS_ASSERT_TRUE(lotsB > lotsA, "risk maior → lots maior");
   MKS_ASSERT_NEAR_DOUBLE(2.0 * lotsA, lotsB, 1e-9, "lotsB == 2*lotsA");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksPositionSizer ===");

   //--- FixedLotSizer
   MKS_RUN(Test_FixedLot_Validate_Ok);
   MKS_RUN(Test_FixedLot_Validate_NullSymbol);
   MKS_RUN(Test_FixedLot_Validate_FixedLotsZero);
   MKS_RUN(Test_FixedLot_Validate_FixedLotsNegative);
   MKS_RUN(Test_FixedLot_Validate_VolumeStepInvalid);
   MKS_RUN(Test_FixedLot_Validate_VolumeMaxLessThanMin);
   MKS_RUN(Test_FixedLot_Validate_NotMultipleOfStep);
   MKS_RUN(Test_FixedLot_Validate_BelowVolumeMin);
   MKS_RUN(Test_FixedLot_Validate_AboveVolumeMax);
   MKS_RUN(Test_FixedLot_ComputeLots_Ok);
   MKS_RUN(Test_FixedLot_ComputeLots_IgnoresSlDistance);
   MKS_RUN(Test_FixedLot_ComputeLots_SlDistanceZero);
   MKS_RUN(Test_FixedLot_ComputeLots_SlDistanceNegative);

   //--- PercentRiskSizer
   MKS_RUN(Test_PercentRisk_Validate_Ok);
   MKS_RUN(Test_PercentRisk_Validate_NullSymbol);
   MKS_RUN(Test_PercentRisk_Validate_NullAccount);
   MKS_RUN(Test_PercentRisk_Validate_RiskPctZero);
   MKS_RUN(Test_PercentRisk_Validate_RiskPctNegative);
   MKS_RUN(Test_PercentRisk_Validate_RiskPctAboveHundred);
   MKS_RUN(Test_PercentRisk_ComputeLots_BasicCase);
   MKS_RUN(Test_PercentRisk_ComputeLots_FloorToStep);
   MKS_RUN(Test_PercentRisk_ComputeLots_BelowVolumeMin);
   MKS_RUN(Test_PercentRisk_ComputeLots_AboveVolumeMax);
   MKS_RUN(Test_PercentRisk_ComputeLots_SlDistanceZero);
   MKS_RUN(Test_PercentRisk_ComputeLots_BalanceZero);
   MKS_RUN(Test_PercentRisk_ComputeLots_BalanceNegative);
   MKS_RUN(Test_PercentRisk_ComputeLots_TickValueZero);
   MKS_RUN(Test_PercentRisk_ComputeLots_PointDifferentFromTickSize);
   MKS_RUN(Test_PercentRisk_ComputeLots_BiggerSlMeansSmallerLots);
   MKS_RUN(Test_PercentRisk_ComputeLots_BiggerRiskMeansBiggerLots);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
