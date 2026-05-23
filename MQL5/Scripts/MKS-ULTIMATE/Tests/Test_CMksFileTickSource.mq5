//+------------------------------------------------------------------+
//| @file           : Test_CMksFileTickSource.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksFileTickSource (ITickSource over
//|                   .mkstick), CMksMt5Clock e CMksReplayClock.
//|                   Cenários: open com proveniência exata, broker/
//|                   account WARN-flag, symbol mismatch FATAL,
//|                   ordem dos ticks, EOF, e ReplayClock acompanhando
//|                   o feed.
//| @depends_on     : Core/Data/CMksFileTickSource.mqh,
//|                   Core/Data/CMksTickFileWriter.mqh,
//|                   Core/Clock/CMksMt5Clock.mqh,
//|                   Core/Clock/CMksReplayClock.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Types/Tick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksFileTickSource.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Data/CMksFileTickSource.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksTickFileWriter.mqh>
#include <MKS-ULTIMATE/Core/Clock/CMksMt5Clock.mqh>
#include <MKS-ULTIMATE/Core/Clock/CMksReplayClock.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

#define TICKSRC_DOUBLE_TOL 1e-12

const int FIXTURE_N = 8;
const string EXPECTED_BROKER  = "Exness Technologies Ltd";
const long   EXPECTED_ACCOUNT = 555444333;
const string EXPECTED_SYMBOL  = "XAUUSDm";

//+------------------------------------------------------------------+
//| Helper: cria fixture .mkstick com proveniência configurável        |
//+------------------------------------------------------------------+
bool CreateFixture(const string &path,
                   const string &broker, long account, const string &symbol)
{
   if(FileIsExist(path)) FileDelete(path);

   CMksTickFileWriter w;
   MksError err;
   if(!w.Open(path, err)) return false;
   if(!w.WriteHeader(broker, account, symbol, 3,
                     0.01, 0.01, 100.0, err, 1700000000000)) return false;

   for(int i = 0; i < FIXTURE_N; i++)
   {
      MksTick t;
      t.seq     = (ulong)(i + 1);
      t.timeMsc = 1700000000000 + (long)i * 250; // 1 tick / 250ms
      t.bid     = 2050.000 + i * 0.01;
      t.ask     = t.bid + 0.05;
      t.last    = (i % 3 == 0) ? t.bid + 0.02 : 0.0;
      t.volume  = (i % 3 == 0) ? (long)(i + 1) : 0;
      t.flags   = (uint)(i & 0x07);
      if(!w.WriteTick(t, err)) return false;
   }
   return w.Close(err, 1700000002000);
}

void DeleteIfExists(const string &path)
{
   if(FileIsExist(path)) FileDelete(path);
}

//+------------------------------------------------------------------+
//| Test 1: Open com proveniência exata — sem flags de mismatch       |
//+------------------------------------------------------------------+
void Test_OpenExactProvenance()
{
   const string path = "MKS-ULTIMATE/test_filesrc_exact.mkstick";
   MKS_ASSERT_TRUE(CreateFixture(path, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL),
                   "fixture criada");

   CMksFileTickSource src(path, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL);
   MksError err;
   MKS_ASSERT_TRUE(src.Open(err), "src.Open exato");

   MKS_ASSERT_FALSE(src.BrokerMismatch(),  "src.BrokerMismatch=false");
   MKS_ASSERT_FALSE(src.AccountMismatch(), "src.AccountMismatch=false");

   MKS_ASSERT_EQ_STRING(EXPECTED_BROKER,  src.Broker(),       "src.Broker");
   MKS_ASSERT_EQ_LONG  (EXPECTED_ACCOUNT, src.AccountLogin(), "src.AccountLogin");
   MKS_ASSERT_EQ_STRING(EXPECTED_SYMBOL,  src.Symbol(),       "src.Symbol");
   MKS_ASSERT_EQ_LONG  (FIXTURE_N,        src.TickCount(),    "src.TickCount");

   src.Close();
   DeleteIfExists(path);
}

//+------------------------------------------------------------------+
//| Test 2: broker diferente — WARN-flag, Open ainda sucede           |
//+------------------------------------------------------------------+
void Test_BrokerMismatchIsWarn()
{
   const string path = "MKS-ULTIMATE/test_filesrc_brokerdiff.mkstick";
   MKS_ASSERT_TRUE(CreateFixture(path, "ICMarkets EU Ltd", EXPECTED_ACCOUNT, EXPECTED_SYMBOL),
                   "fixture broker diferente");

   CMksFileTickSource src(path, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL);
   MksError err;
   MKS_ASSERT_TRUE(src.Open(err), "src.Open com broker diferente — sucesso");

   MKS_ASSERT_TRUE (src.BrokerMismatch(),  "src.BrokerMismatch=true");
   MKS_ASSERT_FALSE(src.AccountMismatch(), "src.AccountMismatch=false");
   MKS_ASSERT_TRUE (StringLen(src.BrokerMismatchMsg()) > 0, "msg de broker preenchida");

   src.Close();
   DeleteIfExists(path);
}

//+------------------------------------------------------------------+
//| Test 3: account diferente — WARN-flag                              |
//+------------------------------------------------------------------+
void Test_AccountMismatchIsWarn()
{
   const string path = "MKS-ULTIMATE/test_filesrc_accountdiff.mkstick";
   MKS_ASSERT_TRUE(CreateFixture(path, EXPECTED_BROKER, 999999999, EXPECTED_SYMBOL),
                   "fixture account diferente");

   CMksFileTickSource src(path, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL);
   MksError err;
   MKS_ASSERT_TRUE(src.Open(err), "src.Open com account diferente — sucesso");

   MKS_ASSERT_FALSE(src.BrokerMismatch(),  "src.BrokerMismatch=false");
   MKS_ASSERT_TRUE (src.AccountMismatch(), "src.AccountMismatch=true");
   MKS_ASSERT_TRUE (StringLen(src.AccountMismatchMsg()) > 0, "msg de account preenchida");

   src.Close();
   DeleteIfExists(path);
}

//+------------------------------------------------------------------+
//| Test 4: symbol diferente — FATAL, Open falha                       |
//+------------------------------------------------------------------+
void Test_SymbolMismatchIsFatal()
{
   const string path = "MKS-ULTIMATE/test_filesrc_symboldiff.mkstick";
   MKS_ASSERT_TRUE(CreateFixture(path, EXPECTED_BROKER, EXPECTED_ACCOUNT, "EURUSD"),
                   "fixture symbol diferente");

   CMksFileTickSource src(path, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL);
   MksError err;
   bool ok = src.Open(err);
   MKS_ASSERT_FALSE(ok, "src.Open com symbol diferente deve falhar");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_DATA_SYMBOL_MISMATCH, (int)err.code, "err.code = SYMBOL_MISMATCH (807)");
   MKS_ASSERT_TRUE(StringFind(err.message, "symbol mismatch") >= 0, "err.message menciona symbol mismatch");

   DeleteIfExists(path);
}

//+------------------------------------------------------------------+
//| Test 5: Next() entrega ticks na ordem, sem perdas, e termina      |
//+------------------------------------------------------------------+
void Test_NextOrderAndEOF()
{
   const string path = "MKS-ULTIMATE/test_filesrc_next.mkstick";
   MKS_ASSERT_TRUE(CreateFixture(path, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL),
                   "fixture");

   CMksFileTickSource src(path, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL);
   MksError err;
   MKS_ASSERT_TRUE(src.Open(err), "src.Open");

   long prevTime = -1;
   ulong prevSeq = 0;
   int consumed = 0;
   MksTick t;
   while(src.Next(t))
   {
      MKS_ASSERT_TRUE(prevTime < 0 || t.timeMsc >= prevTime,
                      StringFormat("timeMsc monotônico [%d]", consumed));
      MKS_ASSERT_TRUE(t.seq > prevSeq, StringFormat("seq monotônica [%d]", consumed));
      prevTime = t.timeMsc;
      prevSeq  = t.seq;
      consumed++;
   }

   MKS_ASSERT_EQ_INT(FIXTURE_N, consumed, "ticks consumidos == FIXTURE_N");
   MKS_ASSERT_FALSE(src.Next(t), "Next pós-EOF retorna false");

   src.Close();
   DeleteIfExists(path);
}

//+------------------------------------------------------------------+
//| Test 6: CMksReplayClock acompanha o tick corrente                  |
//+------------------------------------------------------------------+
void Test_ReplayClockTracksFeed()
{
   const string path = "MKS-ULTIMATE/test_filesrc_clock.mkstick";
   MKS_ASSERT_TRUE(CreateFixture(path, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL),
                   "fixture");

   CMksFileTickSource src(path, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL);
   CMksReplayClock    clock(&src);
   MksError err;
   MKS_ASSERT_TRUE(src.Open(err), "src.Open");

   // Antes de qualquer Next, clock retorna 0.
   MKS_ASSERT_EQ_LONG(0, clock.NowMsc(), "clock antes do 1º tick = 0");

   MksTick t;
   for(int i = 0; i < FIXTURE_N; i++)
   {
      MKS_ASSERT_TRUE(src.Next(t), StringFormat("src.Next[%d]", i));
      MKS_ASSERT_EQ_LONG(t.timeMsc, clock.NowMsc(),
                         StringFormat("clock acompanha tick[%d].timeMsc", i));
      MKS_ASSERT_EQ_LONG(t.timeMsc, src.LastTickTimeMsc(),
                         StringFormat("src.LastTickTimeMsc[%d]", i));
   }

   // Pós-EOF: clock fica congelado no último timeMsc.
   MKS_ASSERT_FALSE(src.Next(t), "EOF");
   long lastExpected = 1700000000000 + (long)(FIXTURE_N - 1) * 250;
   MKS_ASSERT_EQ_LONG(lastExpected, clock.NowMsc(), "clock congelado no último tick");

   src.Close();
   DeleteIfExists(path);
}

//+------------------------------------------------------------------+
//| Test 7: CMksMt5Clock smoke — NowMsc > 0 e em ms                    |
//+------------------------------------------------------------------+
void Test_Mt5ClockSmoke()
{
   CMksMt5Clock clock;
   long now = clock.NowMsc();
   MKS_ASSERT_TRUE(now > 0, "Mt5Clock.NowMsc > 0");
   // TimeCurrent retorna segundos > 1.7e9 desde ~2023 → em ms > 1.7e12.
   MKS_ASSERT_TRUE(now > 1700000000000L, "Mt5Clock.NowMsc em ms (> 1.7e12)");
}

//+------------------------------------------------------------------+
//| Test 8: ReplayClock com source NULL — não crasha, retorna 0        |
//+------------------------------------------------------------------+
void Test_ReplayClockNullSafe()
{
   CMksReplayClock clock(NULL);
   MKS_ASSERT_EQ_LONG(0, clock.NowMsc(), "ReplayClock com NULL retorna 0");
}

//+------------------------------------------------------------------+
//| Entry point                                                       |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksFileTickSource ===");

   FolderCreate("MKS-ULTIMATE");

   MKS_RUN(Test_OpenExactProvenance);
   MKS_RUN(Test_BrokerMismatchIsWarn);
   MKS_RUN(Test_AccountMismatchIsWarn);
   MKS_RUN(Test_SymbolMismatchIsFatal);
   MKS_RUN(Test_NextOrderAndEOF);
   MKS_RUN(Test_ReplayClockTracksFeed);
   MKS_RUN(Test_Mt5ClockSmoke);
   MKS_RUN(Test_ReplayClockNullSafe);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+