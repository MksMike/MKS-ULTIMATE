//+------------------------------------------------------------------+
//| @file           : Test_CMksAccountSnapshot.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksAccountSnapshot — tracking de
//|                   balance de inicio-do-dia-UTC, peak equity,
//|                   rollover diario, DayPnL e Drawdown. Base do
//|                   slice 6.3 (Risk Por Conta). ADR-019.
//| @depends_on     : Core/Account/CMksAccountSnapshot.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksFakeAccount.mqh,
//|                   Core/Testing/Mocks/CMksFakeClock.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksAccountSnapshot.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Account/CMksAccountSnapshot.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeAccount.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeClock.mqh>

#define SNAP_DOUBLE_TOL 1e-9

// Ancora temporal: 2026-05-23 00:00:00 UTC em ms desde epoch.
// Verificado: 1779494400000 % 86400000 == 0 (00:00 UTC redondo).
const long T_2026_05_23_UTC = 1779494400000;

//==================================================================
// Init / first Update
//==================================================================

void Test_Snap_InitCapturesBaseline()
{
   CMksFakeAccount acc;
   acc.SetBalance(10000.0);
   acc.SetEquity(10000.0);
   CMksFakeClock clk;
   clk.SetNowMsc(T_2026_05_23_UTC);

   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   MKS_ASSERT_FALSE(snap.Initialized(), "nao inicializado antes de Init");

   snap.Init();
   MKS_ASSERT_TRUE (snap.Initialized(),                "inicializado");
   MKS_ASSERT_NEAR_DOUBLE(10000.0, snap.DayStartBalance(), SNAP_DOUBLE_TOL, "dayStartBalance");
   MKS_ASSERT_NEAR_DOUBLE(10000.0, snap.PeakEquity(),      SNAP_DOUBLE_TOL, "peakEquity");
   MKS_ASSERT_NEAR_DOUBLE(0.0,     snap.DayPnL(),          SNAP_DOUBLE_TOL, "DayPnL inicial = 0");
   MKS_ASSERT_NEAR_DOUBLE(0.0,     snap.Drawdown(),        SNAP_DOUBLE_TOL, "Drawdown inicial = 0");
}

void Test_Snap_InitIsIdempotent()
{
   CMksFakeAccount acc; acc.SetBalance(10000.0); acc.SetEquity(10000.0);
   CMksFakeClock clk; clk.SetNowMsc(T_2026_05_23_UTC);
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   snap.Init();

   // Mudo o balance e chamo Init de novo — baseline NAO deve mudar.
   acc.SetBalance(20000.0);
   snap.Init();
   MKS_ASSERT_NEAR_DOUBLE(10000.0, snap.DayStartBalance(), SNAP_DOUBLE_TOL,
                          "Init idempotente — baseline preservado");
}

void Test_Snap_UpdateAutoInits()
{
   CMksFakeAccount acc; acc.SetBalance(7500.0); acc.SetEquity(7500.0);
   CMksFakeClock clk; clk.SetNowMsc(T_2026_05_23_UTC);
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));

   snap.Update(); // sem Init explicito
   MKS_ASSERT_TRUE(snap.Initialized(), "Update auto-inicializa");
   MKS_ASSERT_NEAR_DOUBLE(7500.0, snap.DayStartBalance(), SNAP_DOUBLE_TOL,
                          "baseline capturado no 1o Update");
}

//==================================================================
// Peak equity
//==================================================================

void Test_Snap_PeakAdvancesOnNewHigh()
{
   CMksFakeAccount acc; acc.SetBalance(10000.0); acc.SetEquity(10000.0);
   CMksFakeClock clk; clk.SetNowMsc(T_2026_05_23_UTC);
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   snap.Init();

   acc.SetEquity(10500.0); snap.Update();
   MKS_ASSERT_NEAR_DOUBLE(10500.0, snap.PeakEquity(), SNAP_DOUBLE_TOL,
                          "peak avanca com nova alta");

   acc.SetEquity(11200.0); snap.Update();
   MKS_ASSERT_NEAR_DOUBLE(11200.0, snap.PeakEquity(), SNAP_DOUBLE_TOL,
                          "peak avanca com nova alta maior");
}

void Test_Snap_PeakHoldsOnDrop()
{
   CMksFakeAccount acc; acc.SetBalance(10000.0); acc.SetEquity(10000.0);
   CMksFakeClock clk; clk.SetNowMsc(T_2026_05_23_UTC);
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   snap.Init();

   acc.SetEquity(12000.0); snap.Update();
   acc.SetEquity(9000.0);  snap.Update(); // queda
   MKS_ASSERT_NEAR_DOUBLE(12000.0, snap.PeakEquity(), SNAP_DOUBLE_TOL,
                          "peak nao recua em queda");
}

void Test_Snap_PeakSurvivesPartialRecovery()
{
   CMksFakeAccount acc; acc.SetBalance(10000.0); acc.SetEquity(10000.0);
   CMksFakeClock clk; clk.SetNowMsc(T_2026_05_23_UTC);
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   snap.Init();

   acc.SetEquity(12000.0); snap.Update();
   acc.SetEquity(9000.0);  snap.Update();
   acc.SetEquity(11500.0); snap.Update(); // recupera, mas < peak
   MKS_ASSERT_NEAR_DOUBLE(12000.0, snap.PeakEquity(), SNAP_DOUBLE_TOL,
                          "peak preservado em recuperacao parcial");
}

//==================================================================
// DayPnL
//==================================================================

void Test_Snap_DayPnLPositive()
{
   CMksFakeAccount acc; acc.SetBalance(10000.0); acc.SetEquity(10000.0);
   CMksFakeClock clk; clk.SetNowMsc(T_2026_05_23_UTC);
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   snap.Init();

   acc.SetEquity(10300.0); snap.Update();
   MKS_ASSERT_NEAR_DOUBLE(300.0, snap.DayPnL(), SNAP_DOUBLE_TOL, "DayPnL absoluto");
   MKS_ASSERT_NEAR_DOUBLE(3.0,   snap.DayPnLPct(), SNAP_DOUBLE_TOL, "DayPnL %");
}

void Test_Snap_DayPnLNegative()
{
   CMksFakeAccount acc; acc.SetBalance(10000.0); acc.SetEquity(10000.0);
   CMksFakeClock clk; clk.SetNowMsc(T_2026_05_23_UTC);
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   snap.Init();

   acc.SetEquity(9500.0); snap.Update();
   MKS_ASSERT_NEAR_DOUBLE(-500.0, snap.DayPnL(),    SNAP_DOUBLE_TOL, "DayPnL absoluto -500");
   MKS_ASSERT_NEAR_DOUBLE(-5.0,   snap.DayPnLPct(), SNAP_DOUBLE_TOL, "DayPnL % -5");
}

void Test_Snap_DayPnLPctZeroBalanceSafe()
{
   CMksFakeAccount acc; acc.SetBalance(0.0); acc.SetEquity(0.0);
   CMksFakeClock clk; clk.SetNowMsc(T_2026_05_23_UTC);
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   snap.Init();

   MKS_ASSERT_NEAR_DOUBLE(0.0, snap.DayPnLPct(), SNAP_DOUBLE_TOL,
                          "balance=0: DayPnLPct=0 sem div-zero");
}

//==================================================================
// Drawdown
//==================================================================

void Test_Snap_DrawdownZeroAtPeak()
{
   CMksFakeAccount acc; acc.SetBalance(10000.0); acc.SetEquity(10000.0);
   CMksFakeClock clk; clk.SetNowMsc(T_2026_05_23_UTC);
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   snap.Init();

   acc.SetEquity(12000.0); snap.Update();
   MKS_ASSERT_NEAR_DOUBLE(0.0, snap.Drawdown(),    SNAP_DOUBLE_TOL, "drawdown=0 no peak");
   MKS_ASSERT_NEAR_DOUBLE(0.0, snap.DrawdownPct(), SNAP_DOUBLE_TOL, "drawdownPct=0 no peak");
}

void Test_Snap_DrawdownComputed()
{
   CMksFakeAccount acc; acc.SetBalance(10000.0); acc.SetEquity(10000.0);
   CMksFakeClock clk; clk.SetNowMsc(T_2026_05_23_UTC);
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   snap.Init();

   acc.SetEquity(12000.0); snap.Update();
   acc.SetEquity(10800.0); snap.Update(); // 10% de queda do peak
   MKS_ASSERT_NEAR_DOUBLE(1200.0, snap.Drawdown(),    SNAP_DOUBLE_TOL, "drawdown absoluto");
   MKS_ASSERT_NEAR_DOUBLE(10.0,   snap.DrawdownPct(), SNAP_DOUBLE_TOL, "drawdown %");
}

//==================================================================
// Rollover de dia UTC
//==================================================================

void Test_Snap_RolloverResetsDayBaseline()
{
   CMksFakeAccount acc; acc.SetBalance(10000.0); acc.SetEquity(10000.0);
   CMksFakeClock clk; clk.SetNowMsc(T_2026_05_23_UTC + 3600000); // 01:00 UTC
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   snap.Init();

   // Lucro de R$ 500 ainda dentro do dia
   acc.SetEquity(10500.0); acc.SetBalance(10500.0);
   clk.Advance(3600000); // 02:00
   snap.Update();
   MKS_ASSERT_NEAR_DOUBLE(10000.0, snap.DayStartBalance(), SNAP_DOUBLE_TOL,
                          "baseline diario preservado dentro do dia");

   // Rollover — avança 1 dia + 1 hora (ultrapassa meia-noite)
   acc.SetBalance(10500.0); acc.SetEquity(10500.0);
   clk.Advance(86400000);
   snap.Update();
   MKS_ASSERT_NEAR_DOUBLE(10500.0, snap.DayStartBalance(), SNAP_DOUBLE_TOL,
                          "baseline diario RESETA no rollover UTC");
   MKS_ASSERT_NEAR_DOUBLE(0.0, snap.DayPnL(), SNAP_DOUBLE_TOL, "DayPnL zera no novo dia");
}

void Test_Snap_RolloverDoesNotResetPeak()
{
   CMksFakeAccount acc; acc.SetBalance(10000.0); acc.SetEquity(10000.0);
   CMksFakeClock clk; clk.SetNowMsc(T_2026_05_23_UTC);
   CMksAccountSnapshot snap(GetPointer(acc), GetPointer(clk));
   snap.Init();

   acc.SetEquity(13000.0); snap.Update();

   // Rollover de dia
   acc.SetBalance(13000.0); acc.SetEquity(13000.0);
   clk.Advance(86400000);
   snap.Update();
   MKS_ASSERT_NEAR_DOUBLE(13000.0, snap.PeakEquity(), SNAP_DOUBLE_TOL,
                          "peak nao reseta em rollover de dia");

   // Queda no novo dia — drawdown ainda vale (peak conservado)
   acc.SetEquity(11700.0); snap.Update();
   MKS_ASSERT_NEAR_DOUBLE(1300.0, snap.Drawdown(), SNAP_DOUBLE_TOL,
                          "drawdown medido contra peak antigo");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksAccountSnapshot ===");

   MKS_RUN(Test_Snap_InitCapturesBaseline);
   MKS_RUN(Test_Snap_InitIsIdempotent);
   MKS_RUN(Test_Snap_UpdateAutoInits);

   MKS_RUN(Test_Snap_PeakAdvancesOnNewHigh);
   MKS_RUN(Test_Snap_PeakHoldsOnDrop);
   MKS_RUN(Test_Snap_PeakSurvivesPartialRecovery);

   MKS_RUN(Test_Snap_DayPnLPositive);
   MKS_RUN(Test_Snap_DayPnLNegative);
   MKS_RUN(Test_Snap_DayPnLPctZeroBalanceSafe);

   MKS_RUN(Test_Snap_DrawdownZeroAtPeak);
   MKS_RUN(Test_Snap_DrawdownComputed);

   MKS_RUN(Test_Snap_RolloverResetsDayBaseline);
   MKS_RUN(Test_Snap_RolloverDoesNotResetPeak);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
