//+------------------------------------------------------------------+
//| @file           : Test_CMksTickFile.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Golden file test do CMksTickFileWriter +
//|                   CMksTickFileReader. Roundtrip campo-a-campo,
//|                   re-write produzindo bytes idênticos, rejeição
//|                   de magic inválido, leitura além de tickCount,
//|                   e golden de 10k ticks sintéticos (ADR-024 §1
//|                   slice 24a critério).
//| @depends_on     : Core/Data/CMksTickFileWriter.mqh,
//|                   Core/Data/CMksTickFileReader.mqh,
//|                   Core/Data/TickFileFormat.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Types/Tick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksTickFile.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Data/CMksTickFileWriter.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksTickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Data/TickFileFormat.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Tolerância apertada — file roundtrip é bit-identical em binário.
#define TICKFILE_DOUBLE_TOL 1e-12

const int SAMPLE_N = 6;

//+------------------------------------------------------------------+
//| Ticks sintéticos com campos variados (flags, last, volume)        |
//+------------------------------------------------------------------+
void BuildSampleTicks(MksTick &out[])
{
   ArrayResize(out, SAMPLE_N);

   // Tick bid-only
   out[0].seq = 1; out[0].timeMsc = 1700000000000;
   out[0].bid = 2050.123; out[0].ask = 2050.456; out[0].last = 0.0;
   out[0].volume = 0; out[0].flags = 2; // TICK_FLAG_BID

   // Tick ask-only
   out[1].seq = 2; out[1].timeMsc = 1700000000150;
   out[1].bid = 2050.123; out[1].ask = 2050.500; out[1].last = 0.0;
   out[1].volume = 0; out[1].flags = 4; // TICK_FLAG_ASK

   // Tick trade (last + volume) com flags compostos
   out[2].seq = 3; out[2].timeMsc = 1700000000400;
   out[2].bid = 2050.150; out[2].ask = 2050.500; out[2].last = 2050.300;
   out[2].volume = 5; out[2].flags = 0x21; // TICK_FLAG_LAST | TICK_FLAG_BUY

   // Tick com volume alto
   out[3].seq = 4; out[3].timeMsc = 1700000000900;
   out[3].bid = 2050.200; out[3].ask = 2050.550; out[3].last = 2050.400;
   out[3].volume = 123456789; out[3].flags = 0x18; // TICK_FLAG_VOLUME | TICK_FLAG_LAST

   // Tick com last == 0 (broker sem trades naquele momento)
   out[4].seq = 5; out[4].timeMsc = 1700000001000;
   out[4].bid = 2050.250; out[4].ask = 2050.600; out[4].last = 0.0;
   out[4].volume = 0; out[4].flags = 6; // TICK_FLAG_BID | TICK_FLAG_ASK

   // Tick com seq grande (validar uint64 round-trip)
   out[5].seq = 18446744073709551000ULL; out[5].timeMsc = 1700000001500;
   out[5].bid = 2050.300; out[5].ask = 2050.650; out[5].last = 2050.500;
   out[5].volume = 1; out[5].flags = 0x3F; // todos os 6 flags ligados
}

//+------------------------------------------------------------------+
//| Helpers de I/O para o golden test                                 |
//+------------------------------------------------------------------+
bool ReadFileBytes(const string &path, uchar &bytes[])
{
   int h = FileOpen(path, FILE_READ | FILE_BIN);
   if(h == INVALID_HANDLE) return false;
   ulong size = FileSize(h);
   ArrayResize(bytes, (int)size);
   FileReadArray(h, bytes, 0, (int)size);
   FileClose(h);
   return true;
}

bool BytesEqual(const uchar &a[], const uchar &b[])
{
   int na = ArraySize(a);
   int nb = ArraySize(b);
   if(na != nb) return false;
   for(int i = 0; i < na; i++)
      if(a[i] != b[i]) return false;
   return true;
}

void DeleteIfExists(const string &path)
{
   if(FileIsExist(path)) FileDelete(path);
}

//+------------------------------------------------------------------+
//| Test 1: write + read roundtrip — proveniência + ticks             |
//+------------------------------------------------------------------+
void Test_RoundtripFields()
{
   const string path = "MKS-ULTIMATE/test_tickfile_a.mkstick";
   DeleteIfExists(path);

   const string broker      = "Exness Technologies Ltd";
   const long   account     = 123456789;
   const string symbol      = "XAUUSDm";
   const int    digits      = 3;
   const double tickSize    = 0.01;
   const double point       = 0.01;
   const double contractSize = 100.0;
   const long   createdAt   = 1700000300000;
   const long   closedAt    = 1700000305000;

   MksTick samples[];
   BuildSampleTicks(samples);

   // Escrita
   CMksTickFileWriter w;
   MksError err;
   MKS_ASSERT_TRUE(w.Open(path, err), "writer.Open");
   MKS_ASSERT_TRUE(w.WriteHeader(broker, account, symbol, digits,
                                 tickSize, point, contractSize, err, createdAt),
                   "writer.WriteHeader");
   for(int i = 0; i < SAMPLE_N; i++)
      MKS_ASSERT_TRUE(w.WriteTick(samples[i], err),
                      StringFormat("writer.WriteTick[%d]", i));
   MKS_ASSERT_TRUE(w.Close(err, closedAt), "writer.Close");
   MKS_ASSERT_EQ_LONG(SAMPLE_N, w.TickCount(), "writer.TickCount");

   // Leitura
   CMksTickFileReader r;
   MKS_ASSERT_TRUE(r.Open(path, err), "reader.Open");

   MKS_ASSERT_EQ_STRING(broker, r.Broker(),                       "reader.Broker");
   MKS_ASSERT_EQ_LONG(account,  r.AccountLogin(),                 "reader.AccountLogin");
   MKS_ASSERT_EQ_STRING(symbol, r.Symbol(),                       "reader.Symbol");
   MKS_ASSERT_EQ_INT(digits,    r.Digits(),                       "reader.Digits");
   MKS_ASSERT_NEAR_DOUBLE(tickSize,     r.TickSize(),     TICKFILE_DOUBLE_TOL, "reader.TickSize");
   MKS_ASSERT_NEAR_DOUBLE(point,        r.Point(),        TICKFILE_DOUBLE_TOL, "reader.Point");
   MKS_ASSERT_NEAR_DOUBLE(contractSize, r.ContractSize(), TICKFILE_DOUBLE_TOL, "reader.ContractSize");
   MKS_ASSERT_EQ_LONG(SAMPLE_N,    r.TickCount(),       "reader.TickCount");
   MKS_ASSERT_EQ_LONG(samples[0].timeMsc,            r.TimeMscFirst(), "reader.TimeMscFirst");
   MKS_ASSERT_EQ_LONG(samples[SAMPLE_N-1].timeMsc,   r.TimeMscLast(),  "reader.TimeMscLast");
   MKS_ASSERT_EQ_LONG(createdAt, r.CreatedAtMsc(), "reader.CreatedAtMsc");
   MKS_ASSERT_EQ_LONG(closedAt,  r.ClosedAtMsc(),  "reader.ClosedAtMsc");

   for(int i = 0; i < SAMPLE_N; i++)
   {
      MksTick t;
      MKS_ASSERT_TRUE(r.ReadNext(t, err), StringFormat("reader.ReadNext[%d]", i));
      MKS_ASSERT_EQ_ULONG(samples[i].seq, t.seq, StringFormat("tick[%d].seq", i));
      MKS_ASSERT_EQ_LONG(samples[i].timeMsc, t.timeMsc, StringFormat("tick[%d].timeMsc", i));
      MKS_ASSERT_NEAR_DOUBLE(samples[i].bid,  t.bid,  TICKFILE_DOUBLE_TOL, StringFormat("tick[%d].bid", i));
      MKS_ASSERT_NEAR_DOUBLE(samples[i].ask,  t.ask,  TICKFILE_DOUBLE_TOL, StringFormat("tick[%d].ask", i));
      MKS_ASSERT_NEAR_DOUBLE(samples[i].last, t.last, TICKFILE_DOUBLE_TOL, StringFormat("tick[%d].last", i));
      MKS_ASSERT_EQ_LONG(samples[i].volume, t.volume, StringFormat("tick[%d].volume", i));
      MKS_ASSERT_EQ_INT((int)samples[i].flags, (int)t.flags, StringFormat("tick[%d].flags", i));
   }
   MKS_ASSERT_FALSE(r.HasMore(), "reader.HasMore após esgotar");
   r.Close();
}

//+------------------------------------------------------------------+
//| Test 2: golden file — write → read → rewrite gera bytes idênticos
//+------------------------------------------------------------------+
void Test_GoldenFileRewrite()
{
   const string pathA = "MKS-ULTIMATE/test_tickfile_golden_a.mkstick";
   const string pathB = "MKS-ULTIMATE/test_tickfile_golden_b.mkstick";
   DeleteIfExists(pathA);
   DeleteIfExists(pathB);

   const string broker  = "Exness Technologies Ltd";
   const long   account = 987654321;
   const string symbol  = "XAUUSDm";
   const int    digits  = 3;
   const double tickSize = 0.01, point = 0.01, contractSize = 100.0;
   const long   createdAt = 1700000400000;
   const long   closedAt  = 1700000405000;

   MksTick samples[];
   BuildSampleTicks(samples);

   // 1) Escreve A
   MksError err;
   CMksTickFileWriter wA;
   MKS_ASSERT_TRUE(wA.Open(pathA, err), "wA.Open");
   MKS_ASSERT_TRUE(wA.WriteHeader(broker, account, symbol, digits,
                                  tickSize, point, contractSize, err, createdAt),
                   "wA.WriteHeader");
   for(int i = 0; i < SAMPLE_N; i++)
      wA.WriteTick(samples[i], err);
   MKS_ASSERT_TRUE(wA.Close(err, closedAt), "wA.Close");

   // 2) Lê A campo-a-campo
   MksTick readTicks[];
   ArrayResize(readTicks, SAMPLE_N);
   CMksTickFileReader r;
   MKS_ASSERT_TRUE(r.Open(pathA, err), "r.Open(A)");
   for(int i = 0; i < SAMPLE_N; i++)
      r.ReadNext(readTicks[i], err);
   r.Close();

   // 3) Reescreve B com os ticks lidos + mesma proveniência + mesmos timestamps
   CMksTickFileWriter wB;
   MKS_ASSERT_TRUE(wB.Open(pathB, err), "wB.Open");
   MKS_ASSERT_TRUE(wB.WriteHeader(broker, account, symbol, digits,
                                  tickSize, point, contractSize, err, createdAt),
                   "wB.WriteHeader");
   for(int i = 0; i < SAMPLE_N; i++)
      wB.WriteTick(readTicks[i], err);
   MKS_ASSERT_TRUE(wB.Close(err, closedAt), "wB.Close");

   // 4) Compara A e B byte-a-byte
   uchar bytesA[], bytesB[];
   MKS_ASSERT_TRUE(ReadFileBytes(pathA, bytesA), "ReadFileBytes(A)");
   MKS_ASSERT_TRUE(ReadFileBytes(pathB, bytesB), "ReadFileBytes(B)");

   int sizeA = ArraySize(bytesA);
   int sizeB = ArraySize(bytesB);
   MKS_ASSERT_EQ_INT(sizeB, sizeA, "tamanho A == B");

   int expectedSize = MKS_TICKFILE_HEADER_SIZE + SAMPLE_N * MKS_TICKFILE_RECORD_SIZE;
   MKS_ASSERT_EQ_INT(expectedSize, sizeA, "tamanho == header + N*record");

   MKS_ASSERT_TRUE(BytesEqual(bytesA, bytesB), "bytes A == B (golden file)");
}

//+------------------------------------------------------------------+
//| Test 3: arquivo com magic inválido é rejeitado                    |
//+------------------------------------------------------------------+
void Test_RejectsInvalidMagic()
{
   const string pathOk  = "MKS-ULTIMATE/test_tickfile_ok.mkstick";
   const string pathBad = "MKS-ULTIMATE/test_tickfile_badmagic.mkstick";
   DeleteIfExists(pathOk);
   DeleteIfExists(pathBad);

   MksTick samples[];
   BuildSampleTicks(samples);
   MksError err;

   // Cria arquivo válido
   CMksTickFileWriter w;
   w.Open(pathOk, err);
   w.WriteHeader("BrokerX", 1, "SYMB", 2, 0.001, 0.001, 1.0, err, 1700000500000);
   for(int i = 0; i < SAMPLE_N; i++) w.WriteTick(samples[i], err);
   w.Close(err, 1700000505000);

   // Copia para pathBad e corrompe o magic
   uchar bytes[];
   MKS_ASSERT_TRUE(ReadFileBytes(pathOk, bytes), "ReadFileBytes(ok)");
   bytes[0] = 'X'; // corrompe primeiro byte do magic
   int hBad = FileOpen(pathBad, FILE_WRITE | FILE_BIN);
   MKS_ASSERT_TRUE(hBad != INVALID_HANDLE, "FileOpen(bad)");
   FileWriteArray(hBad, bytes, 0, ArraySize(bytes));
   FileClose(hBad);

   // Reader deve rejeitar pathBad
   CMksTickFileReader r;
   bool ok = r.Open(pathBad, err);
   MKS_ASSERT_FALSE(ok, "reader.Open(bad) deve falhar");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_DATA_INVALID_MAGIC, (int)err.code, "err.code");
}

//+------------------------------------------------------------------+
//| Test 4: ReadNext além do total devolve erro de truncamento        |
//+------------------------------------------------------------------+
void Test_ReadBeyondTotalFails()
{
   const string path = "MKS-ULTIMATE/test_tickfile_beyond.mkstick";
   DeleteIfExists(path);

   MksTick samples[];
   BuildSampleTicks(samples);
   MksError err;

   CMksTickFileWriter w;
   w.Open(path, err);
   w.WriteHeader("B", 1, "S", 2, 0.001, 0.001, 1.0, err, 1700000600000);
   for(int i = 0; i < SAMPLE_N; i++) w.WriteTick(samples[i], err);
   w.Close(err, 1700000605000);

   CMksTickFileReader r;
   MKS_ASSERT_TRUE(r.Open(path, err), "reader.Open");
   for(int i = 0; i < SAMPLE_N; i++)
   {
      MksTick t;
      r.ReadNext(t, err);
   }
   // Próxima leitura deve falhar
   MksTick t;
   MksError errBeyond;
   bool ok = r.ReadNext(t, errBeyond);
   MKS_ASSERT_FALSE(ok, "ReadNext além de total deve falhar");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_DATA_TRUNCATED, (int)errBeyond.code, "err.code");
   r.Close();
}

//+------------------------------------------------------------------+
//| Test 5: golden 10k — escreve 10k ticks sintéticos, lê, byte-idêntico
//+------------------------------------------------------------------+
void Test_Golden10k()
{
   const string pathA = "MKS-ULTIMATE/test_tickfile_10k_a.mkstick";
   const string pathB = "MKS-ULTIMATE/test_tickfile_10k_b.mkstick";
   DeleteIfExists(pathA);
   DeleteIfExists(pathB);

   const int N = 10000;
   const string broker  = "Exness Technologies Ltd";
   const long   account = 555;
   const string symbol  = "XAUUSDm";
   const int    digits  = 3;
   const double tickSize = 0.01, point = 0.01, contractSize = 100.0;
   const long   createdAt = 1700100000000;
   const long   closedAt  = 1700100036000; // ~10s wall-clock simulado

   // Gera ticks sintéticos determinísticos.
   MksTick ticks[];
   ArrayResize(ticks, N);
   for(int i = 0; i < N; i++)
   {
      ticks[i].seq     = (ulong)(i + 1);
      ticks[i].timeMsc = 1700100000000 + (long)i * 100; // 1 tick / 100ms
      double drift     = 2050.000 + (i % 500) * 0.01;
      ticks[i].bid     = drift;
      ticks[i].ask     = drift + 0.05;
      ticks[i].last    = (i % 7 == 0) ? drift + 0.02 : 0.0;
      ticks[i].volume  = (i % 7 == 0) ? (long)(i % 100 + 1) : 0;
      ticks[i].flags   = (uint)((i & 0x3F));
   }

   MksError err;

   // 1) Escreve A
   CMksTickFileWriter wA;
   MKS_ASSERT_TRUE(wA.Open(pathA, err), "10k.wA.Open");
   MKS_ASSERT_TRUE(wA.WriteHeader(broker, account, symbol, digits,
                                  tickSize, point, contractSize, err, createdAt),
                   "10k.wA.WriteHeader");
   for(int i = 0; i < N; i++)
      wA.WriteTick(ticks[i], err);
   MKS_ASSERT_TRUE(wA.Close(err, closedAt), "10k.wA.Close");
   MKS_ASSERT_EQ_LONG(N, wA.TickCount(), "10k.wA.TickCount");

   // 2) Lê A em buffer
   MksTick readTicks[];
   ArrayResize(readTicks, N);
   CMksTickFileReader r;
   MKS_ASSERT_TRUE(r.Open(pathA, err), "10k.r.Open");
   MKS_ASSERT_EQ_LONG(N, r.TickCount(), "10k.r.TickCount");
   for(int i = 0; i < N; i++)
      MKS_ASSERT_TRUE(r.ReadNext(readTicks[i], err),
                      (i % 1000 == 0) ? StringFormat("10k.r.ReadNext[%d]", i) : "10k.r.ReadNext");
   MKS_ASSERT_FALSE(r.HasMore(), "10k.r.HasMore após esgotar");
   r.Close();

   // 3) Reescreve B com mesmos campos
   CMksTickFileWriter wB;
   MKS_ASSERT_TRUE(wB.Open(pathB, err), "10k.wB.Open");
   MKS_ASSERT_TRUE(wB.WriteHeader(broker, account, symbol, digits,
                                  tickSize, point, contractSize, err, createdAt),
                   "10k.wB.WriteHeader");
   for(int i = 0; i < N; i++)
      wB.WriteTick(readTicks[i], err);
   MKS_ASSERT_TRUE(wB.Close(err, closedAt), "10k.wB.Close");

   // 4) Compara A e B byte-a-byte
   uchar bytesA[], bytesB[];
   MKS_ASSERT_TRUE(ReadFileBytes(pathA, bytesA), "10k.ReadFileBytes(A)");
   MKS_ASSERT_TRUE(ReadFileBytes(pathB, bytesB), "10k.ReadFileBytes(B)");

   int expectedSize = MKS_TICKFILE_HEADER_SIZE + N * MKS_TICKFILE_RECORD_SIZE;
   MKS_ASSERT_EQ_INT(expectedSize, ArraySize(bytesA), "10k.size A == header + N*record");
   MKS_ASSERT_EQ_INT(ArraySize(bytesB), ArraySize(bytesA), "10k.size A == B");
   MKS_ASSERT_TRUE(BytesEqual(bytesA, bytesB), "10k.bytes A == B (golden file)");
}

//+------------------------------------------------------------------+
//| Entry point                                                       |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksTickFile ===");

   // FileOpen do MT5 não cria subpastas — garante a pasta de teste.
   FolderCreate("MKS-ULTIMATE");

   MKS_RUN(Test_RoundtripFields);
   MKS_RUN(Test_GoldenFileRewrite);
   MKS_RUN(Test_RejectsInvalidMagic);
   MKS_RUN(Test_ReadBeyondTotalFails);
   MKS_RUN(Test_Golden10k);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+