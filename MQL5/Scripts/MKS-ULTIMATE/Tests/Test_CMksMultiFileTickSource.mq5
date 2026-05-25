//+------------------------------------------------------------------+
//| @file           : Test_CMksMultiFileTickSource.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksMultiFileTickSource — replay multi-day
//|                   sobre conjunto ordenado de .mkstick. Cenários:
//|                   leitura cross-file contínua, validação de
//|                   proveniência homogênea, descontinuidade de seq
//|                   (810), proveniência divergente (811), EOF natural,
//|                   ReplayClock acompanhando.
//| @depends_on     : Core/Data/CMksMultiFileTickSource.mqh,
//|                   Core/Data/CMksTickFileWriter.mqh,
//|                   Core/Clock/CMksReplayClock.mqh,
//|                   Core/Testing/Asserts.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksMultiFileTickSource.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Data/CMksMultiFileTickSource.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksTickFileWriter.mqh>
#include <MKS-ULTIMATE/Core/Clock/CMksReplayClock.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>

const string EXPECTED_BROKER  = "Exness Technologies Ltd";
const long   EXPECTED_ACCOUNT = 555444333;
const string EXPECTED_SYMBOL  = "XAUUSDm";

//+------------------------------------------------------------------+
//| Helper: cria um .mkstick com N ticks, seq começando em seqStart   |
//| e tempo começando em timeMscStart, espaçado 250 ms.               |
//+------------------------------------------------------------------+
bool CreateFixture(const string &path,
                   const string &broker, long account, const string &symbol,
                   int nTicks, ulong seqStart, long timeMscStart)
{
   if(FileIsExist(path)) FileDelete(path);

   CMksTickFileWriter w;
   MksError err;
   if(!w.Open(path, err)) return false;
   if(!w.WriteHeader(broker, account, symbol, 3,
                     0.01, 0.01, 100.0, err, timeMscStart)) return false;

   for(int i = 0; i < nTicks; i++)
   {
      MksTick t;
      t.seq     = seqStart + (ulong)i;
      t.timeMsc = timeMscStart + (long)i * 250;
      t.bid     = 2050.000 + i * 0.01;
      t.ask     = t.bid + 0.05;
      t.last    = 0.0;
      t.volume  = 0;
      t.flags   = 0;
      if(!w.WriteTick(t, err)) return false;
   }
   return w.Close(err, timeMscStart + (long)nTicks * 250);
}

void DeleteIfExists(const string &path)
{
   if(FileIsExist(path)) FileDelete(path);
}

//+------------------------------------------------------------------+
//| Test 1: 3 arquivos com seq contígua — leitura cross-file completa  |
//+------------------------------------------------------------------+
void Test_ThreeFilesContinuous()
{
   const string p1 = "MKS-ULTIMATE/test_multi_a_20260520.mkstick";
   const string p2 = "MKS-ULTIMATE/test_multi_a_20260521.mkstick";
   const string p3 = "MKS-ULTIMATE/test_multi_a_20260522.mkstick";

   MKS_ASSERT_TRUE(CreateFixture(p1, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL,
                                  5,  1, 1700000000000),  "fixture 1");
   MKS_ASSERT_TRUE(CreateFixture(p2, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL,
                                  4,  6, 1700086400000),  "fixture 2 (seq 6..9)");
   MKS_ASSERT_TRUE(CreateFixture(p3, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL,
                                  3, 10, 1700172800000),  "fixture 3 (seq 10..12)");

   string paths[];
   ArrayResize(paths, 3);
   paths[0] = p1; paths[1] = p2; paths[2] = p3;

   CMksMultiFileTickSource src(paths, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL);
   MksError err;
   MKS_ASSERT_TRUE(src.Open(err), "src.Open multi 3 arquivos");
   MKS_ASSERT_EQ_INT(3, src.FileCount(), "FileCount=3");
   MKS_ASSERT_EQ_INT(0, src.CurrentFileIdx(), "CurrentFileIdx começa em 0");

   MksTick t;
   ulong prevSeq = 0;
   long  prevTime = -1;
   int consumed = 0;
   while(src.Next(t))
   {
      MKS_ASSERT_TRUE(t.seq > prevSeq, StringFormat("seq monotônica cross-file [%d]", consumed));
      MKS_ASSERT_TRUE(prevTime < 0 || t.timeMsc >= prevTime,
                      StringFormat("time monotônica cross-file [%d]", consumed));
      prevSeq  = t.seq;
      prevTime = t.timeMsc;
      consumed++;
   }
   MKS_ASSERT_EQ_INT(12, consumed, "12 ticks consumidos no total");
   MKS_ASSERT_EQ_LONG(12, src.TicksRead(), "TicksRead acumulado=12");
   MKS_ASSERT_FALSE(src.SeqDiscontinuityDetected(), "sem seq discontinuity");

   src.Close();
   DeleteIfExists(p1); DeleteIfExists(p2); DeleteIfExists(p3);
}

//+------------------------------------------------------------------+
//| Test 2: descontinuidade de seq cross-file dispara erro 810         |
//+------------------------------------------------------------------+
void Test_SeqDiscontinuityFatal()
{
   const string p1 = "MKS-ULTIMATE/test_multi_b_20260520.mkstick";
   const string p2 = "MKS-ULTIMATE/test_multi_b_20260521.mkstick";

   // p1 termina em seq=5; p2 começa em seq=3 (volta atrás) — descontinuidade.
   MKS_ASSERT_TRUE(CreateFixture(p1, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL,
                                  5, 1, 1700000000000), "fixture p1 (seq 1..5)");
   MKS_ASSERT_TRUE(CreateFixture(p2, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL,
                                  3, 3, 1700086400000), "fixture p2 (seq 3..5, descontínuo)");

   string paths[];
   ArrayResize(paths, 2);
   paths[0] = p1; paths[1] = p2;

   CMksMultiFileTickSource src(paths, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL);
   MksError err;
   MKS_ASSERT_TRUE(src.Open(err), "src.Open");

   MksTick t;
   int consumed = 0;
   while(src.Next(t)) consumed++;
   MKS_ASSERT_EQ_INT(5, consumed, "consome 5 ticks de p1 antes de detectar discontinuity");
   MKS_ASSERT_TRUE(src.SeqDiscontinuityDetected(), "discontinuity flag true");
   MKS_ASSERT_TRUE(StringLen(src.SeqDiscontinuityMsg()) > 0, "discontinuity msg preenchida");

   src.Close();
   DeleteIfExists(p1); DeleteIfExists(p2);
}

//+------------------------------------------------------------------+
//| Test 3: broker divergente entre arquivos — 811 fatal               |
//+------------------------------------------------------------------+
void Test_BrokerCrossFileDivergent()
{
   const string p1 = "MKS-ULTIMATE/test_multi_c_20260520.mkstick";
   const string p2 = "MKS-ULTIMATE/test_multi_c_20260521.mkstick";

   MKS_ASSERT_TRUE(CreateFixture(p1, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL,
                                  3, 1, 1700000000000), "fixture p1 (Exness)");
   MKS_ASSERT_TRUE(CreateFixture(p2, "ICMarkets EU Ltd", EXPECTED_ACCOUNT, EXPECTED_SYMBOL,
                                  3, 4, 1700086400000), "fixture p2 (ICMarkets) — divergente");

   string paths[];
   ArrayResize(paths, 2);
   paths[0] = p1; paths[1] = p2;

   CMksMultiFileTickSource src(paths, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL);
   MksError err;
   MKS_ASSERT_TRUE(src.Open(err), "src.Open (1º arquivo OK)");

   // Drena p1, depois tenta abrir p2 (que falha por broker divergente).
   MksTick t;
   int consumed = 0;
   while(src.Next(t)) consumed++;
   MKS_ASSERT_EQ_INT(3, consumed, "consome 3 ticks de p1 antes de falhar no advance");
   MKS_ASSERT_TRUE(src.AdvanceFailureDetected(), "advance failure flag true");
   MKS_ASSERT_TRUE(StringFind(src.AdvanceErrorMsg(), "broker") >= 0,
                   "erro menciona broker divergente");

   src.Close();
   DeleteIfExists(p1); DeleteIfExists(p2);
}

//+------------------------------------------------------------------+
//| Test 4: lista de paths vazia — erro state invalid                   |
//+------------------------------------------------------------------+
void Test_EmptyPathListFails()
{
   string paths[];
   CMksMultiFileTickSource src(paths, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL);
   MksError err;
   MKS_ASSERT_FALSE(src.Open(err), "Open com lista vazia deve falhar");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_DATA_STATE_INVALID, (int)err.code,
                      "err.code = STATE_INVALID");
}

//+------------------------------------------------------------------+
//| Test 5: ReplayClock acompanha feed cross-file                       |
//+------------------------------------------------------------------+
void Test_ReplayClockCrossFile()
{
   const string p1 = "MKS-ULTIMATE/test_multi_d_20260520.mkstick";
   const string p2 = "MKS-ULTIMATE/test_multi_d_20260521.mkstick";

   MKS_ASSERT_TRUE(CreateFixture(p1, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL,
                                  2, 1, 1700000000000), "fixture p1");
   MKS_ASSERT_TRUE(CreateFixture(p2, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL,
                                  2, 3, 1700086400000), "fixture p2");

   string paths[];
   ArrayResize(paths, 2);
   paths[0] = p1; paths[1] = p2;

   CMksMultiFileTickSource src(paths, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL);
   CMksReplayClock clock(&src);
   MksError err;
   MKS_ASSERT_TRUE(src.Open(err), "src.Open");

   // Antes de qualquer Next, clock = 0 e não está ready.
   MKS_ASSERT_EQ_LONG(0, clock.NowMsc(), "clock antes do 1º Next = 0");
   MKS_ASSERT_FALSE(clock.IsReady(), "IsReady=false antes do 1º Next");

   MksTick t;
   MKS_ASSERT_TRUE(src.Next(t), "Next 1");
   MKS_ASSERT_EQ_LONG(1700000000000, clock.NowMsc(), "clock = tick 1 (p1)");
   MKS_ASSERT_TRUE(clock.IsReady(), "IsReady=true após 1º Next");

   MKS_ASSERT_TRUE(src.Next(t), "Next 2");
   MKS_ASSERT_TRUE(src.Next(t), "Next 3 (transição p1->p2)");
   MKS_ASSERT_EQ_LONG(1700086400000, clock.NowMsc(), "clock = tick 3 (p2)");
   MKS_ASSERT_EQ_INT(1, src.CurrentFileIdx(), "CurrentFileIdx avançou para 1");

   MKS_ASSERT_TRUE(src.Next(t), "Next 4");
   MKS_ASSERT_FALSE(src.Next(t), "EOF total");

   src.Close();
   DeleteIfExists(p1); DeleteIfExists(p2);
}

//+------------------------------------------------------------------+
//| Test 6: 1 arquivo só (degenera para single-file behavior)          |
//+------------------------------------------------------------------+
void Test_SingleFileViaMulti()
{
   const string p = "MKS-ULTIMATE/test_multi_e_20260520.mkstick";
   MKS_ASSERT_TRUE(CreateFixture(p, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL,
                                  4, 1, 1700000000000), "fixture single");

   string paths[];
   ArrayResize(paths, 1);
   paths[0] = p;

   CMksMultiFileTickSource src(paths, EXPECTED_BROKER, EXPECTED_ACCOUNT, EXPECTED_SYMBOL);
   MksError err;
   MKS_ASSERT_TRUE(src.Open(err), "src.Open single via multi");

   MksTick t;
   int consumed = 0;
   while(src.Next(t)) consumed++;
   MKS_ASSERT_EQ_INT(4, consumed, "4 ticks consumidos");
   MKS_ASSERT_FALSE(src.SeqDiscontinuityDetected(), "sem discontinuity");
   MKS_ASSERT_FALSE(src.AdvanceFailureDetected(),   "sem advance failure");

   src.Close();
   DeleteIfExists(p);
}

//+------------------------------------------------------------------+
//| Entry point                                                       |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksMultiFileTickSource ===");
   FolderCreate("MKS-ULTIMATE");

   MKS_RUN(Test_ThreeFilesContinuous);
   MKS_RUN(Test_SeqDiscontinuityFatal);
   MKS_RUN(Test_BrokerCrossFileDivergent);
   MKS_RUN(Test_EmptyPathListFails);
   MKS_RUN(Test_ReplayClockCrossFile);
   MKS_RUN(Test_SingleFileViaMulti);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
