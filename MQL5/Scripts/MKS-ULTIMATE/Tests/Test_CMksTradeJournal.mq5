//+------------------------------------------------------------------+
//| @file           : Test_CMksTradeJournal.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksTradeJournal — RecordOpen/Close,
//|                   pnlPoints BUY/SELL, agregados (WinRate, PF,
//|                   gross/avg/largest), sequencias consecutivas,
//|                   estado open/closed. Slice 7b.
//| @depends_on     : Core/Trade/CMksTradeJournal.mqh,
//|                   Core/Testing/Asserts.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksTradeJournal.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Trade/CMksTradeJournal.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>

#define TJ_TOL 1e-9
#define POINT  0.01

//==================================================================
// Open / Close basicos
//==================================================================

void Test_TJ_RecordOpenAddsToOpen()
{
   CMksTradeJournal j(POINT);
   j.RecordOpen(1001, MKS_ORDER_BUY, 0.1, 2000.0, 1700000000000);
   MKS_ASSERT_EQ_INT(1, j.OpenCount(),   "1 open");
   MKS_ASSERT_EQ_INT(0, j.ClosedCount(), "0 closed");
}

void Test_TJ_RecordCloseMovesToClosed()
{
   CMksTradeJournal j(POINT);
   j.RecordOpen (1001, MKS_ORDER_BUY, 0.1, 2000.0, 1700000000000);
   bool ok = j.RecordClose(1001, 2002.0, 1700000060000);
   MKS_ASSERT_TRUE(ok, "RecordClose true");
   MKS_ASSERT_EQ_INT(0, j.OpenCount(),   "0 open");
   MKS_ASSERT_EQ_INT(1, j.ClosedCount(), "1 closed");
}

void Test_TJ_RecordCloseUnknownPositionFails()
{
   CMksTradeJournal j(POINT);
   bool ok = j.RecordClose(999, 2000.0, 0);
   MKS_ASSERT_FALSE(ok, "RecordClose desconhecida = false");
}

//==================================================================
// pnlPoints BUY / SELL
//==================================================================

void Test_TJ_PnlBuyWinner()
{
   CMksTradeJournal j(POINT);
   j.RecordOpen (1, MKS_ORDER_BUY, 0.1, 2000.00, 0);
   j.RecordClose(1, 2003.50, 1);
   MksClosedTrade t = j.ClosedAt(0);
   // (2003.50 - 2000.00) / 0.01 = 350 points
   MKS_ASSERT_NEAR_DOUBLE(350.0, t.pnlPoints, TJ_TOL, "BUY +350pts");
}

void Test_TJ_PnlBuyLoser()
{
   CMksTradeJournal j(POINT);
   j.RecordOpen (1, MKS_ORDER_BUY, 0.1, 2000.00, 0);
   j.RecordClose(1, 1998.00, 1);
   MksClosedTrade t = j.ClosedAt(0);
   MKS_ASSERT_NEAR_DOUBLE(-200.0, t.pnlPoints, TJ_TOL, "BUY -200pts");
}

void Test_TJ_PnlSellWinner()
{
   CMksTradeJournal j(POINT);
   j.RecordOpen (2, MKS_ORDER_SELL, 0.1, 2000.00, 0);
   j.RecordClose(2, 1995.00, 1);
   MksClosedTrade t = j.ClosedAt(0);
   // (2000.00 - 1995.00) / 0.01 = 500 points
   MKS_ASSERT_NEAR_DOUBLE(500.0, t.pnlPoints, TJ_TOL, "SELL +500pts");
}

void Test_TJ_PnlSellLoser()
{
   CMksTradeJournal j(POINT);
   j.RecordOpen (2, MKS_ORDER_SELL, 0.1, 2000.00, 0);
   j.RecordClose(2, 2003.00, 1);
   MksClosedTrade t = j.ClosedAt(0);
   MKS_ASSERT_NEAR_DOUBLE(-300.0, t.pnlPoints, TJ_TOL, "SELL -300pts");
}

//==================================================================
// Agregados — win/loss counts e win rate
//==================================================================

void Test_TJ_WinLossCounts()
{
   CMksTradeJournal j(POINT);
   // 3 wins, 2 losses
   j.RecordOpen(1, MKS_ORDER_BUY, 0.1, 2000.0, 0); j.RecordClose(1, 2001.0, 1);
   j.RecordOpen(2, MKS_ORDER_BUY, 0.1, 2000.0, 2); j.RecordClose(2, 2001.0, 3);
   j.RecordOpen(3, MKS_ORDER_BUY, 0.1, 2000.0, 4); j.RecordClose(3, 1999.0, 5);
   j.RecordOpen(4, MKS_ORDER_BUY, 0.1, 2000.0, 6); j.RecordClose(4, 2001.0, 7);
   j.RecordOpen(5, MKS_ORDER_BUY, 0.1, 2000.0, 8); j.RecordClose(5, 1999.0, 9);

   MKS_ASSERT_EQ_INT(3, j.WinCount(),         "3 wins");
   MKS_ASSERT_EQ_INT(2, j.LossCount(),        "2 losses");
   MKS_ASSERT_EQ_INT(0, j.BreakevenCount(),   "0 breakevens");
   MKS_ASSERT_NEAR_DOUBLE(0.6, j.WinRate(), TJ_TOL, "winRate 60%");
}

void Test_TJ_BreakevenIgnoredInWinRate()
{
   CMksTradeJournal j(POINT);
   j.RecordOpen(1, MKS_ORDER_BUY, 0.1, 2000.0, 0); j.RecordClose(1, 2000.0, 1); // BE
   j.RecordOpen(2, MKS_ORDER_BUY, 0.1, 2000.0, 2); j.RecordClose(2, 2001.0, 3); // W
   j.RecordOpen(3, MKS_ORDER_BUY, 0.1, 2000.0, 4); j.RecordClose(3, 1999.0, 5); // L

   MKS_ASSERT_EQ_INT(1, j.BreakevenCount(), "1 BE");
   MKS_ASSERT_NEAR_DOUBLE(0.5, j.WinRate(), TJ_TOL, "winRate 50% (BE ignorado)");
}

//==================================================================
// Profit factor e gross
//==================================================================

void Test_TJ_GrossProfitLoss()
{
   CMksTradeJournal j(POINT);
   j.RecordOpen(1, MKS_ORDER_BUY, 0.1, 2000.0, 0); j.RecordClose(1, 2003.0, 1); // +300
   j.RecordOpen(2, MKS_ORDER_BUY, 0.1, 2000.0, 2); j.RecordClose(2, 2002.0, 3); // +200
   j.RecordOpen(3, MKS_ORDER_BUY, 0.1, 2000.0, 4); j.RecordClose(3, 1998.5, 5); // -150

   MKS_ASSERT_NEAR_DOUBLE(500.0, j.GrossProfitPoints(), TJ_TOL, "gross+ 500");
   MKS_ASSERT_NEAR_DOUBLE(150.0, j.GrossLossPoints(),   TJ_TOL, "gross- 150");
   MKS_ASSERT_NEAR_DOUBLE(350.0, j.NetPnLPoints(),      TJ_TOL, "net 350");
}

void Test_TJ_ProfitFactor()
{
   CMksTradeJournal j(POINT);
   j.RecordOpen(1, MKS_ORDER_BUY, 0.1, 2000.0, 0); j.RecordClose(1, 2002.0, 1); // +200
   j.RecordOpen(2, MKS_ORDER_BUY, 0.1, 2000.0, 2); j.RecordClose(2, 1999.0, 3); // -100
   // PF = 200/100 = 2.0
   MKS_ASSERT_NEAR_DOUBLE(2.0, j.ProfitFactor(), TJ_TOL, "PF 2.0");
}

void Test_TJ_ProfitFactorInfWhenNoLoss()
{
   CMksTradeJournal j(POINT);
   j.RecordOpen(1, MKS_ORDER_BUY, 0.1, 2000.0, 0); j.RecordClose(1, 2002.0, 1); // +200
   j.RecordOpen(2, MKS_ORDER_BUY, 0.1, 2000.0, 2); j.RecordClose(2, 2003.0, 3); // +300
   MKS_ASSERT_TRUE(j.ProfitFactor() >= 1e17, "PF representado como ~INF sem loss");
}

void Test_TJ_ProfitFactorZeroWhenNothing()
{
   CMksTradeJournal j(POINT);
   MKS_ASSERT_NEAR_DOUBLE(0.0, j.ProfitFactor(), TJ_TOL, "PF=0 sem trades");
}

//==================================================================
// Avg, largest
//==================================================================

void Test_TJ_AvgAndLargest()
{
   CMksTradeJournal j(POINT);
   j.RecordOpen(1, MKS_ORDER_BUY, 0.1, 2000.0, 0); j.RecordClose(1, 2002.0, 1); // +200
   j.RecordOpen(2, MKS_ORDER_BUY, 0.1, 2000.0, 2); j.RecordClose(2, 2005.0, 3); // +500 maior win
   j.RecordOpen(3, MKS_ORDER_BUY, 0.1, 2000.0, 4); j.RecordClose(3, 1999.5, 5); // -50
   j.RecordOpen(4, MKS_ORDER_BUY, 0.1, 2000.0, 6); j.RecordClose(4, 1997.0, 7); // -300 maior loss

   MKS_ASSERT_NEAR_DOUBLE(350.0, j.AvgWinPoints(),     TJ_TOL, "avg win 350");
   MKS_ASSERT_NEAR_DOUBLE(175.0, j.AvgLossPoints(),    TJ_TOL, "avg loss 175");
   MKS_ASSERT_NEAR_DOUBLE(500.0, j.LargestWinPoints(), TJ_TOL, "largest win 500");
   MKS_ASSERT_NEAR_DOUBLE(300.0, j.LargestLossPoints(),TJ_TOL, "largest loss 300");
}

//==================================================================
// Sequencias consecutivas
//==================================================================

void Test_TJ_MaxConsecutiveWins()
{
   CMksTradeJournal j(POINT);
   // Sequencia W W L W W W L (max 3 wins)
   double prices[]   = {2001, 2001, 1999, 2001, 2001, 2001, 1999};
   for(int i = 0; i < 7; i++)
   {
      j.RecordOpen((ulong)(i+1), MKS_ORDER_BUY, 0.1, 2000.0, i*2);
      j.RecordClose((ulong)(i+1), prices[i], i*2 + 1);
   }
   MKS_ASSERT_EQ_INT(3, j.MaxConsecutiveWins(),   "max wins streak = 3");
   MKS_ASSERT_EQ_INT(1, j.MaxConsecutiveLosses(), "max losses streak = 1");
}

void Test_TJ_MaxConsecutiveLosses()
{
   CMksTradeJournal j(POINT);
   double prices[] = {1999, 1999, 1999, 1999, 2001, 1999, 1999};
   for(int i = 0; i < 7; i++)
   {
      j.RecordOpen((ulong)(i+1), MKS_ORDER_BUY, 0.1, 2000.0, i*2);
      j.RecordClose((ulong)(i+1), prices[i], i*2 + 1);
   }
   MKS_ASSERT_EQ_INT(4, j.MaxConsecutiveLosses(), "max losses streak = 4");
}

//==================================================================
// Reset
//==================================================================

void Test_TJ_Reset()
{
   CMksTradeJournal j(POINT);
   j.RecordOpen(1, MKS_ORDER_BUY, 0.1, 2000.0, 0); j.RecordClose(1, 2001.0, 1);
   j.RecordOpen(2, MKS_ORDER_BUY, 0.1, 2000.0, 2); // ainda aberta
   j.Reset();
   MKS_ASSERT_EQ_INT(0, j.OpenCount(),   "open zerado");
   MKS_ASSERT_EQ_INT(0, j.ClosedCount(), "closed zerado");
}

//==================================================================
// Eixo 3 — comissão e resultado em MOEDA (E4.1/E4.2/ADR-034)
// tickSize=0.01, tickValue=1.0 (XAU-like: 0.01 de preço = 1 USD/lote).
//==================================================================

void Test_TJ_CommissionAndNetCurrency()
{
   CMksTradeJournal j(POINT);
   j.SetMoneyConversion(0.01, 1.0);
   MKS_ASSERT_TRUE(j.HasMoneyConversion(), "conversão de moeda ativa");

   j.RecordOpen(1, MKS_ORDER_BUY, 0.1, 2000.0, 0, 2.0);  // commissionOpen = 2
   j.RecordClose(1, 2003.0, 1, 3.0);                     // commissionClose = 3

   MksClosedTrade t = j.ClosedAt(0);
   MKS_ASSERT_NEAR_DOUBLE(300.0, t.pnlPoints,  TJ_TOL, "pnl 300 pts");
   MKS_ASSERT_NEAR_DOUBLE(5.0,   t.commission, TJ_TOL, "commission = open+close = 5");
   // PnlCurrency bruto = (3.0/0.01)*1.0*0.1 = 30
   MKS_ASSERT_NEAR_DOUBLE(30.0,  j.GrossProfitCurrency(), TJ_TOL, "bruto em moeda = 30");
   MKS_ASSERT_NEAR_DOUBLE(5.0,   j.TotalCommission(),     TJ_TOL, "comissão total 5");
   MKS_ASSERT_NEAR_DOUBLE(25.0,  j.NetPnLCurrency(),      TJ_TOL, "líquido = 30 - 5 = 25");
}

void Test_TJ_CommissionReducesNetCurrency()
{
   // [M1]/[M8]: dois journals idênticos exceto a comissão → net em moeda
   // DIFERE. Antes do E4 seriam iguais (comissão descartada) — o sintoma
   // exato do eixo 3 do V5.
   CMksTradeJournal jFree(POINT); jFree.SetMoneyConversion(0.01, 1.0);
   CMksTradeJournal jComm(POINT); jComm.SetMoneyConversion(0.01, 1.0);

   jFree.RecordOpen(1, MKS_ORDER_BUY, 0.1, 2000.0, 0, 0.0);
   jFree.RecordClose(1, 2003.0, 1, 0.0);
   jComm.RecordOpen(1, MKS_ORDER_BUY, 0.1, 2000.0, 0, 0.0);
   jComm.RecordClose(1, 2003.0, 1, 7.0);                  // única diferença: comissão 7

   MKS_ASSERT_NEAR_DOUBLE(30.0, jFree.NetPnLCurrency(), TJ_TOL, "sem comissão: líquido 30");
   MKS_ASSERT_NEAR_DOUBLE(23.0, jComm.NetPnLCurrency(), TJ_TOL, "comissão 7: líquido 23");
   MKS_ASSERT_TRUE(jFree.NetPnLCurrency() > jComm.NetPnLCurrency(),
                   "comissão reduz estritamente o líquido (eixo 3 fechado)");
}

void Test_TJ_CurrencyMixedWinLoss()
{
   // Win + loss em moeda + comissão nos dois. Cobre GrossProfit/LossCurrency.
   CMksTradeJournal j(POINT);
   j.SetMoneyConversion(0.01, 1.0);
   j.RecordOpen(1, MKS_ORDER_BUY, 0.1, 2000.0, 0, 1.0);
   j.RecordClose(1, 2003.0, 1, 1.0);                      // +30 moeda, comm 2
   j.RecordOpen(2, MKS_ORDER_BUY, 0.1, 2000.0, 2, 1.0);
   j.RecordClose(2, 1998.0, 3, 1.0);                      // -20 moeda, comm 2

   MKS_ASSERT_NEAR_DOUBLE(30.0, j.GrossProfitCurrency(), TJ_TOL, "gross+ moeda 30");
   MKS_ASSERT_NEAR_DOUBLE(20.0, j.GrossLossCurrency(),   TJ_TOL, "gross- moeda 20");
   MKS_ASSERT_NEAR_DOUBLE(4.0,  j.TotalCommission(),     TJ_TOL, "comissão total 4");
   // líquido = (30 - 20) - 4 = 6
   MKS_ASSERT_NEAR_DOUBLE(6.0,  j.NetPnLCurrency(),      TJ_TOL, "líquido = grossnet 10 - comm 4 = 6");
}

void Test_TJ_NoMoneyConversionZeroCurrency()
{
   // Sem SetMoneyConversion: agregados em moeda ficam 0 (mas comissão, que é
   // dado bruto já em moeda, ainda é somada). RecordOpen/Close com comissão
   // continuam compilando (params default) — não quebra callers antigos.
   CMksTradeJournal j(POINT);
   j.RecordOpen(1, MKS_ORDER_BUY, 0.1, 2000.0, 0, 2.0);
   j.RecordClose(1, 2003.0, 1, 3.0);

   MKS_ASSERT_FALSE(j.HasMoneyConversion(), "conversão de moeda desligada");
   MKS_ASSERT_NEAR_DOUBLE(0.0, j.GrossProfitCurrency(), TJ_TOL, "gross moeda 0 sem conversão");
   MKS_ASSERT_NEAR_DOUBLE(0.0, j.NetPnLCurrency(),      TJ_TOL, "líquido 0 sem conversão");
   MKS_ASSERT_NEAR_DOUBLE(5.0, j.TotalCommission(),     TJ_TOL, "comissão somada = 5");
   // pnlPoints intacto (não depende da conversão de moeda)
   MKS_ASSERT_NEAR_DOUBLE(300.0, j.ClosedAt(0).pnlPoints, TJ_TOL, "pnlPoints 300 preservado");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksTradeJournal ===");

   MKS_RUN(Test_TJ_RecordOpenAddsToOpen);
   MKS_RUN(Test_TJ_RecordCloseMovesToClosed);
   MKS_RUN(Test_TJ_RecordCloseUnknownPositionFails);

   MKS_RUN(Test_TJ_PnlBuyWinner);
   MKS_RUN(Test_TJ_PnlBuyLoser);
   MKS_RUN(Test_TJ_PnlSellWinner);
   MKS_RUN(Test_TJ_PnlSellLoser);

   MKS_RUN(Test_TJ_WinLossCounts);
   MKS_RUN(Test_TJ_BreakevenIgnoredInWinRate);

   MKS_RUN(Test_TJ_GrossProfitLoss);
   MKS_RUN(Test_TJ_ProfitFactor);
   MKS_RUN(Test_TJ_ProfitFactorInfWhenNoLoss);
   MKS_RUN(Test_TJ_ProfitFactorZeroWhenNothing);

   MKS_RUN(Test_TJ_AvgAndLargest);

   MKS_RUN(Test_TJ_MaxConsecutiveWins);
   MKS_RUN(Test_TJ_MaxConsecutiveLosses);

   MKS_RUN(Test_TJ_Reset);

   // Eixo 3 — comissão e moeda (E4.1/E4.2/ADR-034)
   MKS_RUN(Test_TJ_CommissionAndNetCurrency);
   MKS_RUN(Test_TJ_CommissionReducesNetCurrency);
   MKS_RUN(Test_TJ_CurrencyMixedWinLoss);
   MKS_RUN(Test_TJ_NoMoneyConversionZeroCurrency);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
