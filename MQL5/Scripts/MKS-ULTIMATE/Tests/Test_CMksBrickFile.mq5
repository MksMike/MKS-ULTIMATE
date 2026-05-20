//+------------------------------------------------------------------+
//| @file           : Test_CMksBrickFile.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Golden file test do CMksBrickFileWriter +
//|                   CMksBrickFileReader. Write/read roundtrip de
//|                   bricks sintéticos com asserção campo-a-campo,
//|                   re-write produzindo bytes idênticos, e rejeição
//|                   de arquivos com magic inválido.
//| @depends_on     : Core/Data/CMksBrickFileWriter.mqh,
//|                   Core/Data/CMksBrickFileReader.mqh,
//|                   Core/Data/BrickFileFormat.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/RenkoGeometry.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksBrickFile.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Data/CMksBrickFileWriter.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Data/BrickFileFormat.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

int    g_passed = 0;
int    g_failed = 0;
string g_currentTest = "";

void StartTest(const string name) { g_currentTest = name; }

void AssertEqualInt(int expected, int actual, const string what)
{
   if(expected == actual) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=%d actual=%d", g_currentTest, what, expected, actual);
}

void AssertEqualLong(long expected, long actual, const string what)
{
   if(expected == actual) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=%I64d actual=%I64d", g_currentTest, what, expected, actual);
}

void AssertEqualUlong(ulong expected, ulong actual, const string what)
{
   if(expected == actual) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=%I64u actual=%I64u", g_currentTest, what, expected, actual);
}

void AssertEqualDouble(double expected, double actual, const string what)
{
   if(MathAbs(expected - actual) < 1e-12) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=%.12f actual=%.12f", g_currentTest, what, expected, actual);
}

void AssertEqualString(const string expected, const string actual, const string what)
{
   if(StringCompare(expected, actual) == 0) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected='%s' actual='%s'", g_currentTest, what, expected, actual);
}

void AssertTrue(bool cond, const string what)
{
   if(cond) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=true", g_currentTest, what);
}

void AssertFalse(bool cond, const string what)
{
   if(!cond) { g_passed++; return; }
   g_failed++;
   PrintFormat("FAIL [%s] %s: expected=false", g_currentTest, what);
}

//+------------------------------------------------------------------+
//| Bricks sintéticos com campos variados (direção, M, valores)       |
//+------------------------------------------------------------------+
const int SAMPLE_N = 5;

void BuildSampleBricks(MksBrick &out[])
{
   ArrayResize(out, SAMPLE_N);

   out[0].direction = MKS_BRICK_BULL;
   out[0].thresholdsCrossed = 1;
   out[0].open = 4500.000; out[0].close = 4501.500;
   out[0].high = 4501.500; out[0].low = 4500.000;
   out[0].triggerPrice = 4501.510; out[0].triggerTickId = 100;
   out[0].closeTimeMsc = 1700000000000; out[0].volume = 0;

   out[1].direction = MKS_BRICK_BULL;
   out[1].thresholdsCrossed = 2;
   out[1].open = 4501.500; out[1].close = 4504.500;
   out[1].high = 4504.500; out[1].low = 4501.500;
   out[1].triggerPrice = 4504.700; out[1].triggerTickId = 250;
   out[1].closeTimeMsc = 1700000060000; out[1].volume = 0;

   out[2].direction = MKS_BRICK_BEAR;
   out[2].thresholdsCrossed = 1;
   out[2].open = 4504.500; out[2].close = 4503.000;
   out[2].high = 4504.500; out[2].low = 4503.000;
   out[2].triggerPrice = 4502.900; out[2].triggerTickId = 400;
   out[2].closeTimeMsc = 1700000120000; out[2].volume = 0;

   out[3].direction = MKS_BRICK_BEAR;
   out[3].thresholdsCrossed = 5;
   out[3].open = 4503.000; out[3].close = 4495.500;
   out[3].high = 4503.000; out[3].low = 4495.500;
   out[3].triggerPrice = 4495.000; out[3].triggerTickId = 600;
   out[3].closeTimeMsc = 1700000180000; out[3].volume = 0;

   out[4].direction = MKS_BRICK_BULL;
   out[4].thresholdsCrossed = 12;
   out[4].open = 4495.500; out[4].close = 4513.500;
   out[4].high = 4513.500; out[4].low = 4495.500;
   out[4].triggerPrice = 4514.250; out[4].triggerTickId = 950;
   out[4].closeTimeMsc = 1700000240000; out[4].volume = 0;
}

//+------------------------------------------------------------------+
//| Helpers                                                           |
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
//| Test 1: write + read roundtrip — proveniência + bricks campo-a-campo
//+------------------------------------------------------------------+
void Test_RoundtripFields()
{
   StartTest("roundtrip_fields");

   const string path = "MKS-ULTIMATE/test_brickfile_a.mksbk";
   DeleteIfExists(path);

   MksRenkoGeometry geom = MksGeometryMedian();
   const string broker  = "Exness Technologies Ltd";
   const long   account = 123456789;
   const string symbol  = "XAUUSDm";
   const int    digits  = 3;
   const double sizePts = 3.0;
   const long   createdAt = 1700000300000;

   MksBrick samples[];
   BuildSampleBricks(samples);

   // Escrita
   CMksBrickFileWriter w;
   MksError err;
   AssertTrue(w.Open(path, err), "writer.Open");
   AssertTrue(w.WriteHeader(broker, account, symbol, digits, geom, sizePts, err),
              "writer.WriteHeader");
   for(int i = 0; i < SAMPLE_N; i++)
      AssertTrue(w.WriteBrick(samples[i], err), StringFormat("writer.WriteBrick[%d]", i));
   AssertTrue(w.Close(err, createdAt), "writer.Close");
   AssertEqualLong(SAMPLE_N, w.BrickCount(), "writer.BrickCount");

   // Leitura
   CMksBrickFileReader r;
   AssertTrue(r.Open(path, err), "reader.Open");

   AssertEqualString(broker, r.Broker(), "reader.Broker");
   AssertEqualLong(account, r.AccountLogin(), "reader.AccountLogin");
   AssertEqualString(symbol, r.Symbol(), "reader.Symbol");
   AssertEqualInt(digits, r.Digits(), "reader.Digits");
   AssertEqualDouble(geom.po,           r.Geometry().po,           "reader.Geometry.po");
   AssertEqualDouble(geom.pro,          r.Geometry().pro,          "reader.Geometry.pro");
   AssertEqualDouble(geom.revSizeRatio, r.Geometry().revSizeRatio, "reader.Geometry.revRatio");
   AssertEqualDouble(sizePts,   r.BrickSizePoints(),  "reader.BrickSizePoints");
   AssertEqualLong(SAMPLE_N,    r.BrickCount(),       "reader.BrickCount");
   AssertEqualLong(samples[0].closeTimeMsc, r.TimeMscFirst(), "reader.TimeMscFirst");
   AssertEqualLong(samples[SAMPLE_N-1].closeTimeMsc, r.TimeMscLast(), "reader.TimeMscLast");
   AssertEqualLong(createdAt,   r.CreatedAtMsc(),     "reader.CreatedAtMsc");

   for(int i = 0; i < SAMPLE_N; i++)
   {
      MksBrick b;
      AssertTrue(r.ReadNext(b, err), StringFormat("reader.ReadNext[%d]", i));
      AssertEqualInt((int)samples[i].direction, (int)b.direction,    StringFormat("brick[%d].dir", i));
      AssertEqualInt(samples[i].thresholdsCrossed, b.thresholdsCrossed, StringFormat("brick[%d].M", i));
      AssertEqualDouble(samples[i].open,         b.open,         StringFormat("brick[%d].open", i));
      AssertEqualDouble(samples[i].close,        b.close,        StringFormat("brick[%d].close", i));
      AssertEqualDouble(samples[i].high,         b.high,         StringFormat("brick[%d].high", i));
      AssertEqualDouble(samples[i].low,          b.low,          StringFormat("brick[%d].low", i));
      AssertEqualDouble(samples[i].triggerPrice, b.triggerPrice, StringFormat("brick[%d].trig", i));
      AssertEqualUlong(samples[i].triggerTickId, b.triggerTickId, StringFormat("brick[%d].tickId", i));
      AssertEqualLong(samples[i].closeTimeMsc,   b.closeTimeMsc, StringFormat("brick[%d].time", i));
      AssertEqualLong(samples[i].volume,         b.volume,       StringFormat("brick[%d].vol", i));
   }
   AssertFalse(r.HasMore(), "reader.HasMore após esgotar");
   r.Close();
}

//+------------------------------------------------------------------+
//| Test 2: golden file — write → read → rewrite gera bytes idênticos
//+------------------------------------------------------------------+
void Test_GoldenFileRewrite()
{
   StartTest("golden_file_rewrite");

   const string pathA = "MKS-ULTIMATE/test_brickfile_golden_a.mksbk";
   const string pathB = "MKS-ULTIMATE/test_brickfile_golden_b.mksbk";
   DeleteIfExists(pathA);
   DeleteIfExists(pathB);

   MksRenkoGeometry geom = MksGeometryMedian();
   const string broker = "Exness Technologies Ltd";
   const long   account = 987654321;
   const string symbol = "XAUUSDm";
   const int    digits = 3;
   const double sizePts = 3.0;
   const long   createdAt = 1700000400000;

   MksBrick samples[];
   BuildSampleBricks(samples);

   // 1) Escreve A
   MksError err;
   CMksBrickFileWriter wA;
   AssertTrue(wA.Open(pathA, err), "wA.Open");
   AssertTrue(wA.WriteHeader(broker, account, symbol, digits, geom, sizePts, err), "wA.WriteHeader");
   for(int i = 0; i < SAMPLE_N; i++)
      wA.WriteBrick(samples[i], err);
   AssertTrue(wA.Close(err, createdAt), "wA.Close");

   // 2) Lê A campo-a-campo
   MksBrick readBricks[];
   ArrayResize(readBricks, SAMPLE_N);
   CMksBrickFileReader r;
   AssertTrue(r.Open(pathA, err), "r.Open(A)");
   for(int i = 0; i < SAMPLE_N; i++)
      r.ReadNext(readBricks[i], err);
   r.Close();

   // 3) Reescreve B com os bricks lidos + mesma proveniência + mesmo createdAt
   CMksBrickFileWriter wB;
   AssertTrue(wB.Open(pathB, err), "wB.Open");
   AssertTrue(wB.WriteHeader(broker, account, symbol, digits, geom, sizePts, err), "wB.WriteHeader");
   for(int i = 0; i < SAMPLE_N; i++)
      wB.WriteBrick(readBricks[i], err);
   AssertTrue(wB.Close(err, createdAt), "wB.Close");

   // 4) Compara A e B byte-a-byte
   uchar bytesA[], bytesB[];
   AssertTrue(ReadFileBytes(pathA, bytesA), "ReadFileBytes(A)");
   AssertTrue(ReadFileBytes(pathB, bytesB), "ReadFileBytes(B)");

   int sizeA = ArraySize(bytesA);
   int sizeB = ArraySize(bytesB);
   AssertEqualInt(sizeB, sizeA, "tamanho A == B");

   int expectedSize = MKS_BRICKFILE_HEADER_SIZE + SAMPLE_N * MKS_BRICKFILE_RECORD_SIZE;
   AssertEqualInt(expectedSize, sizeA, "tamanho == header + N*record");

   AssertTrue(BytesEqual(bytesA, bytesB), "bytes A == B (golden file)");
}

//+------------------------------------------------------------------+
//| Test 3: arquivo com magic inválido é rejeitado                    |
//+------------------------------------------------------------------+
void Test_RejectsInvalidMagic()
{
   StartTest("rejects_invalid_magic");

   const string pathOk  = "MKS-ULTIMATE/test_brickfile_ok.mksbk";
   const string pathBad = "MKS-ULTIMATE/test_brickfile_badmagic.mksbk";
   DeleteIfExists(pathOk);
   DeleteIfExists(pathBad);

   MksRenkoGeometry geom = MksGeometryMedian();
   MksBrick samples[];
   BuildSampleBricks(samples);
   MksError err;

   // Cria arquivo válido
   CMksBrickFileWriter w;
   w.Open(pathOk, err);
   w.WriteHeader("BrokerX", 1, "SYMB", 2, geom, 1.0, err);
   for(int i = 0; i < SAMPLE_N; i++) w.WriteBrick(samples[i], err);
   w.Close(err, 1700000500000);

   // Copia para pathBad e corrompe o magic
   uchar bytes[];
   AssertTrue(ReadFileBytes(pathOk, bytes), "ReadFileBytes(ok)");
   bytes[0] = 'X'; // corrompe primeiro byte do magic
   int hBad = FileOpen(pathBad, FILE_WRITE | FILE_BIN);
   AssertTrue(hBad != INVALID_HANDLE, "FileOpen(bad)");
   FileWriteArray(hBad, bytes, 0, ArraySize(bytes));
   FileClose(hBad);

   // Reader deve rejeitar pathBad
   CMksBrickFileReader r;
   bool ok = r.Open(pathBad, err);
   AssertFalse(ok, "reader.Open(bad) deve falhar");
   AssertEqualInt((int)MKS_ERR_DATA_INVALID_MAGIC, (int)err.code, "err.code");
}

//+------------------------------------------------------------------+
//| Test 4: ReadNext além do total devolve erro de truncamento        |
//+------------------------------------------------------------------+
void Test_ReadBeyondTotalFails()
{
   StartTest("read_beyond_total_fails");

   const string path = "MKS-ULTIMATE/test_brickfile_beyond.mksbk";
   DeleteIfExists(path);

   MksRenkoGeometry geom = MksGeometryMedian();
   MksBrick samples[];
   BuildSampleBricks(samples);
   MksError err;

   CMksBrickFileWriter w;
   w.Open(path, err);
   w.WriteHeader("B", 1, "S", 2, geom, 1.0, err);
   for(int i = 0; i < SAMPLE_N; i++) w.WriteBrick(samples[i], err);
   w.Close(err, 1700000600000);

   CMksBrickFileReader r;
   AssertTrue(r.Open(path, err), "reader.Open");
   for(int i = 0; i < SAMPLE_N; i++)
   {
      MksBrick b;
      r.ReadNext(b, err);
   }
   // Próxima leitura deve falhar
   MksBrick b;
   MksError errBeyond;
   bool ok = r.ReadNext(b, errBeyond);
   AssertFalse(ok, "ReadNext além de total deve falhar");
   AssertEqualInt((int)MKS_ERR_DATA_TRUNCATED, (int)errBeyond.code, "err.code");
   r.Close();
}

//+------------------------------------------------------------------+
//| Entry point                                                       |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksBrickFile ===");

   // FileOpen do MT5 não cria subpastas — garante a pasta de teste.
   FolderCreate("MKS-ULTIMATE");

   Test_RoundtripFields();
   Test_GoldenFileRewrite();
   Test_RejectsInvalidMagic();
   Test_ReadBeyondTotalFails();

   Print("");
   PrintFormat("RESUMO: passed=%d  failed=%d", g_passed, g_failed);
   if(g_failed == 0) Print("=== TODOS OS TESTES PASSARAM ===");
   else              Print("=== HÁ FALHAS — VEJA ACIMA ===");
}
