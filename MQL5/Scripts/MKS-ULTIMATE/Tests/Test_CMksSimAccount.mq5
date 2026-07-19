//+------------------------------------------------------------------+
//| @file           : Test_CMksSimAccount.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksSimAccount (E2.0) — equity/balance a
//|                   partir de P&L realizado + MTM não-realizado, na
//|                   convenção de dinheiro do sizer. Round-trip fecha ao
//|                   centavo; MTM move equity mas não balance; sinal de
//|                   BUY/SELL; múltiplas posições; close reduz open;
//|                   fechamento desconhecido é no-op; sem mid → só
//|                   realizado. Fecha o eixo 3 (custo→equity) no runner.
//| @depends_on     : Core/Account/CMksSimAccount.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh,
//|                   Core/Types/OrderRequest.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksSimAccount.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Account/CMksSimAccount.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>

#define ACC_TOL 1e-6
const double START = 10000.0;
// FakeSymbol: tickSize=0.01, tickValue=1.0 → money = priceDiff*100*lots.

//==================================================================
// Estado inicial e comissão
//==================================================================

void Test_Acc_InitialState()
{
   CMksFakeSymbol sym;
   CMksSimAccount acc(GetPointer(sym), START);
   MKS_ASSERT_NEAR_DOUBLE(START, acc.Balance(), ACC_TOL, "balance inicial = start");
   MKS_ASSERT_NEAR_DOUBLE(START, acc.Equity(),  ACC_TOL, "equity inicial = start");
   MKS_ASSERT_EQ_INT(0, acc.OpenCount(), "sem posições abertas");
}

void Test_Acc_OpenSubtractsCommission()
{
   CMksFakeSymbol sym;
   CMksSimAccount acc(GetPointer(sym), START);
   acc.SetMid(2000.0);
   acc.OnOpen(1, MKS_ORDER_BUY, 2000.0, 0.1, 0.5); // comissão de abertura 0.5
   MKS_ASSERT_NEAR_DOUBLE(START - 0.5, acc.Balance(), ACC_TOL, "comissão sai do balance");
   MKS_ASSERT_NEAR_DOUBLE(START - 0.5, acc.Equity(), ACC_TOL, "equity=balance no mid=open");
   MKS_ASSERT_EQ_INT(1, acc.OpenCount(), "1 posição aberta");
}

//==================================================================
// MTM: move equity, não balance
//==================================================================

void Test_Acc_MtmMovesEquityNotBalance_Buy()
{
   CMksFakeSymbol sym;
   CMksSimAccount acc(GetPointer(sym), START);
   acc.SetMid(2000.0);
   acc.OnOpen(1, MKS_ORDER_BUY, 2000.0, 0.1, 0.0);
   acc.SetMid(2010.0); // +10 preço, 0.1 lot → +10*100*0.1 = +100
   MKS_ASSERT_NEAR_DOUBLE(START, acc.Balance(), ACC_TOL, "balance intacto (não realizado)");
   MKS_ASSERT_NEAR_DOUBLE(START + 100.0, acc.Equity(), ACC_TOL, "equity += MTM (+100)");
   acc.SetMid(1990.0); // -10 preço → -100
   MKS_ASSERT_NEAR_DOUBLE(START - 100.0, acc.Equity(), ACC_TOL, "equity move com o mid");
}

void Test_Acc_MtmSign_Sell()
{
   CMksFakeSymbol sym;
   CMksSimAccount acc(GetPointer(sym), START);
   acc.SetMid(2000.0);
   acc.OnOpen(2, MKS_ORDER_SELL, 2000.0, 0.2, 0.0);
   acc.SetMid(1990.0); // SELL lucra quando cai: (1990-2000)*100*0.2*(-1) = +200
   MKS_ASSERT_NEAR_DOUBLE(START + 200.0, acc.Equity(), ACC_TOL, "SELL: equity sobe quando preço cai");
   acc.SetMid(2010.0); // SELL perde quando sobe: -200
   MKS_ASSERT_NEAR_DOUBLE(START - 200.0, acc.Equity(), ACC_TOL, "SELL: equity cai quando preço sobe");
}

//==================================================================
// Round-trip: realiza P&L, balance reflete
//==================================================================

void Test_Acc_RoundTripBuyClosesToCent()
{
   CMksFakeSymbol sym;
   CMksSimAccount acc(GetPointer(sym), START);
   acc.SetMid(2000.0);
   acc.OnOpen(1, MKS_ORDER_BUY, 2000.0, 0.1, 0.5);
   acc.OnClose(1, 2010.0, 0.5); // pnl=(2010-2000)*100*0.1=100; -0.5-0.5 comissão
   MKS_ASSERT_NEAR_DOUBLE(START + 100.0 - 1.0, acc.Balance(), ACC_TOL, "balance = start + pnl - comissões");
   MKS_ASSERT_NEAR_DOUBLE(START + 99.0, acc.Equity(), ACC_TOL, "equity = balance (sem aberta)");
   MKS_ASSERT_EQ_INT(0, acc.OpenCount(), "posição fechada");
   MKS_ASSERT_NEAR_DOUBLE(99.0, acc.RealizedPnL(), ACC_TOL, "realizado = +99");
}

void Test_Acc_RoundTripSell()
{
   CMksFakeSymbol sym;
   CMksSimAccount acc(GetPointer(sym), START);
   acc.SetMid(2000.0);
   acc.OnOpen(2, MKS_ORDER_SELL, 2000.0, 0.2, 0.0);
   acc.OnClose(2, 1990.0, 0.0); // SELL fecha em queda: (1990-2000)*100*0.2*(-1)=+200
   MKS_ASSERT_NEAR_DOUBLE(START + 200.0, acc.Balance(), ACC_TOL, "SELL lucrativo realizado");
   MKS_ASSERT_EQ_INT(0, acc.OpenCount(), "fechada");
}

//==================================================================
// Múltiplas posições, close reduz open, no-op, defensivos
//==================================================================

void Test_Acc_MultiplePositionsMtmSums()
{
   CMksFakeSymbol sym;
   CMksSimAccount acc(GetPointer(sym), START);
   acc.SetMid(2000.0);
   acc.OnOpen(1, MKS_ORDER_BUY,  2000.0, 0.1, 0.0);
   acc.OnOpen(2, MKS_ORDER_SELL, 2000.0, 0.1, 0.0);
   MKS_ASSERT_EQ_INT(2, acc.OpenCount(), "2 abertas");
   acc.SetMid(2010.0); // BUY +100, SELL -100 → soma 0 (hedge)
   MKS_ASSERT_NEAR_DOUBLE(START, acc.Equity(), ACC_TOL, "MTM soma das duas = 0 no hedge");
   acc.OnClose(1, 2010.0, 0.0); // realiza +100
   MKS_ASSERT_EQ_INT(1, acc.OpenCount(), "close reduz open para 1");
   MKS_ASSERT_NEAR_DOUBLE(START + 100.0, acc.Balance(), ACC_TOL, "BUY realizado +100");
   MKS_ASSERT_NEAR_DOUBLE(START, acc.Equity(), ACC_TOL, "equity = balance + SELL MTM(-100)");
}

void Test_Acc_CloseUnknownIsNoop()
{
   CMksFakeSymbol sym;
   CMksSimAccount acc(GetPointer(sym), START);
   acc.SetMid(2000.0);
   acc.OnOpen(1, MKS_ORDER_BUY, 2000.0, 0.1, 0.0);
   acc.OnClose(999, 2010.0, 1.0); // id inexistente → no-op
   MKS_ASSERT_NEAR_DOUBLE(START, acc.Balance(), ACC_TOL, "balance intacto após close desconhecido");
   MKS_ASSERT_EQ_INT(1, acc.OpenCount(), "posição real segue aberta");
}

void Test_Acc_EquityWithoutMidIsBalance()
{
   CMksFakeSymbol sym;
   CMksSimAccount acc(GetPointer(sym), START);
   // Sem SetMid: MTM indefinido → Equity()=Balance() (defensivo).
   acc.OnOpen(1, MKS_ORDER_BUY, 2000.0, 0.1, 0.5);
   MKS_ASSERT_NEAR_DOUBLE(START - 0.5, acc.Balance(), ACC_TOL, "balance = start - comissão");
   MKS_ASSERT_NEAR_DOUBLE(acc.Balance(), acc.Equity(), ACC_TOL, "sem mid: equity = balance");
}

void Test_Acc_SwapFlagDefaultsOff()
{
   CMksFakeSymbol sym;
   CMksSimAccount acc(GetPointer(sym), START);
   MKS_ASSERT_FALSE(acc.ApplySwap(), "swap OFF por default (v1; journal marca)");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksSimAccount ===");

   MKS_RUN(Test_Acc_InitialState);
   MKS_RUN(Test_Acc_OpenSubtractsCommission);
   MKS_RUN(Test_Acc_MtmMovesEquityNotBalance_Buy);
   MKS_RUN(Test_Acc_MtmSign_Sell);
   MKS_RUN(Test_Acc_RoundTripBuyClosesToCent);
   MKS_RUN(Test_Acc_RoundTripSell);
   MKS_RUN(Test_Acc_MultiplePositionsMtmSums);
   MKS_RUN(Test_Acc_CloseUnknownIsNoop);
   MKS_RUN(Test_Acc_EquityWithoutMidIsBalance);
   MKS_RUN(Test_Acc_SwapFlagDefaultsOff);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
