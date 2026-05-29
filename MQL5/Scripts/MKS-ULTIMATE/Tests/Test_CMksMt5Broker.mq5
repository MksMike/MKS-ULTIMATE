//+------------------------------------------------------------------+
//| @file           : Test_CMksMt5Broker.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testa o guard de margin mode do CMksMt5Broker.Init
//|                   (ADR-029): hedging passa, netting/exchange são
//|                   recusados com MKS_ERR_BROKER_NETTING_UNSUPPORTED.
//|                   O guard roda ANTES de qualquer OrderSend, então o
//|                   Init é unit-testável com mocks, sem tocar a API real
//|                   do MT5. Os caminhos Send/Close/Modify (que exigem
//|                   servidor real) continuam cobertos pelo EA de
//|                   integração Test_MksMt5BrokerLive.mq5.
//| @depends_on     : Core/Broker/CMksMt5Broker.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh,
//|                   Core/Testing/Mocks/CMksFakeAccount.mqh,
//|                   Core/Testing/Asserts.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksMt5Broker.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Broker/CMksMt5Broker.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeAccount.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//+------------------------------------------------------------------+
//| Hedging → Init aceita e inicializa.                               |
//+------------------------------------------------------------------+
void Test_Init_AcceptsHedging()
{
   CMksFakeSymbol  sym;
   CMksFakeAccount acc;
   acc.SetMarginMode(ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   CMksMt5Broker broker(GetPointer(sym), GetPointer(acc), 123);
   MksError err;
   bool ok = broker.Init(err);

   MKS_ASSERT_TRUE(ok, "Init aceita conta hedging");
   MKS_ASSERT_TRUE(broker.IsInitialized(), "broker inicializado em hedging");
   MKS_ASSERT_EQ_INT(MKS_ERR_NONE, err.code, "sem erro em hedging");
}

//+------------------------------------------------------------------+
//| Netting → Init recusa com código 204, broker fica não-init.       |
//+------------------------------------------------------------------+
void Test_Init_RefusesNetting()
{
   CMksFakeSymbol  sym;
   CMksFakeAccount acc;
   acc.SetMarginMode(ACCOUNT_MARGIN_MODE_RETAIL_NETTING);

   CMksMt5Broker broker(GetPointer(sym), GetPointer(acc), 123);
   MksError err;
   bool ok = broker.Init(err);

   MKS_ASSERT_FALSE(ok, "Init recusa conta netting");
   MKS_ASSERT_FALSE(broker.IsInitialized(), "broker NAO inicializado em netting");
   MKS_ASSERT_EQ_INT(MKS_ERR_BROKER_NETTING_UNSUPPORTED, err.code,
                     "codigo 204 em netting");
}

//+------------------------------------------------------------------+
//| Exchange (netting de bolsa) → mesma recusa que netting.           |
//+------------------------------------------------------------------+
void Test_Init_RefusesExchange()
{
   CMksFakeSymbol  sym;
   CMksFakeAccount acc;
   acc.SetMarginMode(ACCOUNT_MARGIN_MODE_EXCHANGE);

   CMksMt5Broker broker(GetPointer(sym), GetPointer(acc), 123);
   MksError err;
   bool ok = broker.Init(err);

   MKS_ASSERT_FALSE(ok, "Init recusa conta exchange");
   MKS_ASSERT_FALSE(broker.IsInitialized(), "broker NAO inicializado em exchange");
   MKS_ASSERT_EQ_INT(MKS_ERR_BROKER_NETTING_UNSUPPORTED, err.code,
                     "codigo 204 em exchange");
}

//+------------------------------------------------------------------+
//| Ponteiros nulos → guard de NOT_INITIALIZED tem precedência sobre  |
//| o guard de margin mode (não deref de NULL).                        |
//+------------------------------------------------------------------+
void Test_Init_NullArgsRefusedFirst()
{
   CMksMt5Broker broker(NULL, NULL, 123);
   MksError err;
   bool ok = broker.Init(err);

   MKS_ASSERT_FALSE(ok, "Init recusa ponteiros nulos");
   MKS_ASSERT_EQ_INT(MKS_ERR_BROKER_NOT_INITIALIZED, err.code,
                     "codigo NOT_INITIALIZED com nulos (antes do margin mode)");
}

//+------------------------------------------------------------------+
void OnStart()
{
   MKS_RUN(Test_Init_AcceptsHedging);
   MKS_RUN(Test_Init_RefusesNetting);
   MKS_RUN(Test_Init_RefusesExchange);
   MKS_RUN(Test_Init_NullArgsRefusedFirst);
   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
