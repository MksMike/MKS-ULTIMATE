//+------------------------------------------------------------------+
//| @file           : Test_CMksBrickFile.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Golden file test do CMksBrickFileWriter +
//|                   CMksBrickFileReader. Write/read roundtrip de
//|                   bricks sintéticos com asserção campo-a-campo,
//|                   re-write produzindo bytes idênticos, e rejeição
//|                   de arquivos com magic inválido.
//|                   Migrado para o framework Core/Testing (ADR-005).
//| @depends_on     : Core/Data/CMksBrickFileWriter.mqh,
//|                   Core/Data/CMksBrickFileReader.mqh,
//|                   Core/Data/BrickFileFormat.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/RenkoGeometry.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksBrickFile.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Data/CMksBrickFileWriter.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksBrickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Data/BrickFileFormat.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Tolerância apertada do teste original (1e-12). File roundtrip é
// bit-identical em binário, mas mantemos a semântica do teste antigo.
#define BRICKFILE_DOUBLE_TOL 1e-12

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
//| Test 1: write + read roundtrip — proveniência + bricks campo-a-campo
//+------------------------------------------------------------------+
void Test_RoundtripFields()
{
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
   MKS_ASSERT_TRUE(w.Open(path, err), "writer.Open");
   MKS_ASSERT_TRUE(w.WriteHeader(broker, account, symbol, digits, geom, sizePts, err),
                   "writer.WriteHeader");
   for(int i = 0; i < SAMPLE_N; i++)
      MKS_ASSERT_TRUE(w.WriteBrick(samples[i], err), StringFormat("writer.WriteBrick[%d]", i));
   MKS_ASSERT_TRUE(w.Close(err, createdAt), "writer.Close");
   MKS_ASSERT_EQ_LONG(SAMPLE_N, w.BrickCount(), "writer.BrickCount");

   // Leitura
   CMksBrickFileReader r;
   MKS_ASSERT_TRUE(r.Open(path, err), "reader.Open");

   MKS_ASSERT_EQ_STRING(broker, r.Broker(),                       "reader.Broker");
   MKS_ASSERT_EQ_LONG(account,  r.AccountLogin(),                 "reader.AccountLogin");
   MKS_ASSERT_EQ_STRING(symbol, r.Symbol(),                       "reader.Symbol");
   MKS_ASSERT_EQ_INT(digits,    r.Digits(),                       "reader.Digits");
   MKS_ASSERT_NEAR_DOUBLE(geom.po,           r.Geometry().po,           BRICKFILE_DOUBLE_TOL, "reader.Geometry.po");
   MKS_ASSERT_NEAR_DOUBLE(geom.pro,          r.Geometry().pro,          BRICKFILE_DOUBLE_TOL, "reader.Geometry.pro");
   MKS_ASSERT_NEAR_DOUBLE(geom.revSizeRatio, r.Geometry().revSizeRatio, BRICKFILE_DOUBLE_TOL, "reader.Geometry.revRatio");
   MKS_ASSERT_NEAR_DOUBLE(sizePts, r.BrickSizePoints(),  BRICKFILE_DOUBLE_TOL, "reader.BrickSizePoints");
   MKS_ASSERT_EQ_LONG(SAMPLE_N,    r.BrickCount(),       "reader.BrickCount");
   MKS_ASSERT_EQ_LONG(samples[0].closeTimeMsc,            r.TimeMscFirst(), "reader.TimeMscFirst");
   MKS_ASSERT_EQ_LONG(samples[SAMPLE_N-1].closeTimeMsc,   r.TimeMscLast(),  "reader.TimeMscLast");
   MKS_ASSERT_EQ_LONG(createdAt,   r.CreatedAtMsc(),     "reader.CreatedAtMsc");

   for(int i = 0; i < SAMPLE_N; i++)
   {
      MksBrick b;
      MKS_ASSERT_TRUE(r.ReadNext(b, err), StringFormat("reader.ReadNext[%d]", i));
      MKS_ASSERT_EQ_INT((int)samples[i].direction, (int)b.direction,                       StringFormat("brick[%d].dir", i));
      MKS_ASSERT_EQ_INT(samples[i].thresholdsCrossed, b.thresholdsCrossed,                 StringFormat("brick[%d].M", i));
      MKS_ASSERT_NEAR_DOUBLE(samples[i].open,         b.open,         BRICKFILE_DOUBLE_TOL, StringFormat("brick[%d].open", i));
      MKS_ASSERT_NEAR_DOUBLE(samples[i].close,        b.close,        BRICKFILE_DOUBLE_TOL, StringFormat("brick[%d].close", i));
      MKS_ASSERT_NEAR_DOUBLE(samples[i].high,         b.high,         BRICKFILE_DOUBLE_TOL, StringFormat("brick[%d].high", i));
      MKS_ASSERT_NEAR_DOUBLE(samples[i].low,          b.low,          BRICKFILE_DOUBLE_TOL, StringFormat("brick[%d].low", i));
      MKS_ASSERT_NEAR_DOUBLE(samples[i].triggerPrice, b.triggerPrice, BRICKFILE_DOUBLE_TOL, StringFormat("brick[%d].trig", i));
      MKS_ASSERT_EQ_ULONG(samples[i].triggerTickId,   b.triggerTickId,                     StringFormat("brick[%d].tickId", i));
      MKS_ASSERT_EQ_LONG(samples[i].closeTimeMsc,     b.closeTimeMsc,                      StringFormat("brick[%d].time", i));
      MKS_ASSERT_EQ_LONG(samples[i].volume,           b.volume,                            StringFormat("brick[%d].vol", i));
   }
   MKS_ASSERT_FALSE(r.HasMore(), "reader.HasMore após esgotar");
   r.Close();
}

//+------------------------------------------------------------------+
//| Test 2: golden file — write → read → rewrite gera bytes idênticos
//+------------------------------------------------------------------+
void Test_GoldenFileRewrite()
{
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
   MKS_ASSERT_TRUE(wA.Open(pathA, err), "wA.Open");
   MKS_ASSERT_TRUE(wA.WriteHeader(broker, account, symbol, digits, geom, sizePts, err), "wA.WriteHeader");
   for(int i = 0; i < SAMPLE_N; i++)
      wA.WriteBrick(samples[i], err);
   MKS_ASSERT_TRUE(wA.Close(err, createdAt), "wA.Close");

   // 2) Lê A campo-a-campo
   MksBrick readBricks[];
   ArrayResize(readBricks, SAMPLE_N);
   CMksBrickFileReader r;
   MKS_ASSERT_TRUE(r.Open(pathA, err), "r.Open(A)");
   for(int i = 0; i < SAMPLE_N; i++)
      r.ReadNext(readBricks[i], err);
   r.Close();

   // 3) Reescreve B com os bricks lidos + mesma proveniência + mesmo createdAt
   CMksBrickFileWriter wB;
   MKS_ASSERT_TRUE(wB.Open(pathB, err), "wB.Open");
   MKS_ASSERT_TRUE(wB.WriteHeader(broker, account, symbol, digits, geom, sizePts, err), "wB.WriteHeader");
   for(int i = 0; i < SAMPLE_N; i++)
      wB.WriteBrick(readBricks[i], err);
   MKS_ASSERT_TRUE(wB.Close(err, createdAt), "wB.Close");

   // 4) Compara A e B byte-a-byte
   uchar bytesA[], bytesB[];
   MKS_ASSERT_TRUE(ReadFileBytes(pathA, bytesA), "ReadFileBytes(A)");
   MKS_ASSERT_TRUE(ReadFileBytes(pathB, bytesB), "ReadFileBytes(B)");

   int sizeA = ArraySize(bytesA);
   int sizeB = ArraySize(bytesB);
   MKS_ASSERT_EQ_INT(sizeB, sizeA, "tamanho A == B");

   int expectedSize = MKS_BRICKFILE_HEADER_SIZE + SAMPLE_N * MKS_BRICKFILE_RECORD_SIZE;
   MKS_ASSERT_EQ_INT(expectedSize, sizeA, "tamanho == header + N*record");

   MKS_ASSERT_TRUE(BytesEqual(bytesA, bytesB), "bytes A == B (golden file)");
}

//+------------------------------------------------------------------+
//| Test 3: arquivo com magic inválido é rejeitado                    |
//+------------------------------------------------------------------+
void Test_RejectsInvalidMagic()
{
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
   MKS_ASSERT_TRUE(ReadFileBytes(pathOk, bytes), "ReadFileBytes(ok)");
   bytes[0] = 'X'; // corrompe primeiro byte do magic
   int hBad = FileOpen(pathBad, FILE_WRITE | FILE_BIN);
   MKS_ASSERT_TRUE(hBad != INVALID_HANDLE, "FileOpen(bad)");
   FileWriteArray(hBad, bytes, 0, ArraySize(bytes));
   FileClose(hBad);

   // Reader deve rejeitar pathBad
   CMksBrickFileReader r;
   bool ok = r.Open(pathBad, err);
   MKS_ASSERT_FALSE(ok, "reader.Open(bad) deve falhar");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_DATA_INVALID_MAGIC, (int)err.code, "err.code");
}

//+------------------------------------------------------------------+
//| Test 4: ReadNext além do total devolve erro de truncamento        |
//+------------------------------------------------------------------+
void Test_ReadBeyondTotalFails()
{
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
   MKS_ASSERT_TRUE(r.Open(path, err), "reader.Open");
   for(int i = 0; i < SAMPLE_N; i++)
   {
      MksBrick b;
      r.ReadNext(b, err);
   }
   // Próxima leitura deve falhar
   MksBrick b;
   MksError errBeyond;
   bool ok = r.ReadNext(b, errBeyond);
   MKS_ASSERT_FALSE(ok, "ReadNext além de total deve falhar");
   MKS_ASSERT_EQ_INT((int)MKS_ERR_DATA_TRUNCATED, (int)errBeyond.code, "err.code");
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

   MKS_RUN(Test_RoundtripFields);
   MKS_RUN(Test_GoldenFileRewrite);
   MKS_RUN(Test_RejectsInvalidMagic);
   MKS_RUN(Test_ReadBeyondTotalFails);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
