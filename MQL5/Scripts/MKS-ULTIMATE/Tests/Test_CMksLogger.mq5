//+------------------------------------------------------------------+
//| @file           : Test_CMksLogger.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksLogger — schema JSON-line (ADR-007),
//|                   escape de module/msg, e precisão de timestamp nos
//|                   dois caminhos: "agora" (.000Z) e timeMsc explícito
//|                   (ms real). Cobre o fix do TODO de precisão de ms.
//| @depends_on     : Core/Log/CMksLogger.mqh,
//|                   Core/Testing/Asserts.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksLogger.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Log/CMksLogger.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>

// Arquivo plano na raiz de MQL5/Files — evita FolderCreate no teste.
#define LOG_TEST_PATH "mks_test_logger.log"

//==================================================================
// Helpers
//==================================================================

// Lê a n-ésima linha (0-based) do arquivo de log recém-escrito.
// Retorna "" se a linha não existe.
string ReadLine(const string path, int lineIdx)
{
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return "";
   string line = "";
   int idx = 0;
   bool found = false;
   while(!FileIsEnding(h))
   {
      string cur = FileReadString(h);
      if(idx == lineIdx)
      {
         line  = cur;
         found = true;
         break;
      }
      idx++;
   }
   FileClose(h);
   return found ? line : "";
}

void CleanFile()
{
   if(FileIsExist(LOG_TEST_PATH))
      FileDelete(LOG_TEST_PATH);
}

//==================================================================
// Timestamp: precisão de ms via timeMsc explícito (fix do TODO)
//==================================================================

void Test_Log_MscTimestampHasRealMillis()
{
   CleanFile();
   // 2026.05.21 15:30:42.123 — round-trip puro por TimeToStruct; o valor
   // absoluto de fuso é irrelevante pois a formatação não aplica offset.
   long baseSec = (long)StringToTime("2026.05.21 15:30:42");
   long timeMsc = baseSec * 1000 + 123;

   CMksLogger lg;
   MksError err;
   MKS_ASSERT_TRUE(lg.Open(LOG_TEST_PATH, MKS_LOG_INFO, false, true, err),
                   "Open");
   lg.Log(MKS_LOG_INFO, "T", "m", "", timeMsc);
   lg.Close();

   string line = ReadLine(LOG_TEST_PATH, 0);
   MKS_ASSERT_TRUE(
      StringFind(line, "\"ts\":\"2026-05-21T15:30:42.123Z\"") >= 0,
      StringFormat("ts com ms real (linha='%s')", line));
   CleanFile();
}

void Test_Log_MscTimestampZeroPadsMillis()
{
   CleanFile();
   long baseSec = (long)StringToTime("2026.05.21 15:30:42");
   long timeMsc = baseSec * 1000 + 7; // ms=7 deve virar ".007Z"

   CMksLogger lg;
   MksError err;
   MKS_ASSERT_TRUE(lg.Open(LOG_TEST_PATH, MKS_LOG_INFO, false, true, err),
                   "Open");
   lg.Info("T", "m", "", timeMsc); // exercita o helper overload
   lg.Close();

   string line = ReadLine(LOG_TEST_PATH, 0);
   MKS_ASSERT_TRUE(StringFind(line, ".007Z\"") >= 0,
                   StringFormat("ms zero-padded (linha='%s')", line));
   CleanFile();
}

void Test_Log_NoMscFallsBackToZeroMillis()
{
   CleanFile();
   CMksLogger lg;
   MksError err;
   MKS_ASSERT_TRUE(lg.Open(LOG_TEST_PATH, MKS_LOG_INFO, false, true, err),
                   "Open");
   lg.Log(MKS_LOG_INFO, "T", "m", ""); // overload de contrato, sem timeMsc
   lg.Close();

   string line = ReadLine(LOG_TEST_PATH, 0);
   MKS_ASSERT_TRUE(StringFind(line, ".000Z\"") >= 0,
                   StringFormat("fallback .000Z (linha='%s')", line));
   CleanFile();
}

//==================================================================
// Schema JSON-line e escape
//==================================================================

void Test_Log_LineCarriesSchemaFields()
{
   CleanFile();
   long timeMsc = (long)StringToTime("2026.05.21 00:00:00") * 1000;

   CMksLogger lg;
   MksError err;
   MKS_ASSERT_TRUE(lg.Open(LOG_TEST_PATH, MKS_LOG_INFO, false, true, err),
                   "Open");
   lg.Log(MKS_LOG_WARN, "RenkoBuilder", "brick emitted",
          "\"brickIdx\":9883", timeMsc);
   lg.Close();

   string line = ReadLine(LOG_TEST_PATH, 0);
   MKS_ASSERT_TRUE(StringFind(line, "\"level\":\"WARN\"") >= 0,
                   "level presente");
   MKS_ASSERT_TRUE(StringFind(line, "\"module\":\"RenkoBuilder\"") >= 0,
                   "module presente");
   MKS_ASSERT_TRUE(StringFind(line, "\"msg\":\"brick emitted\"") >= 0,
                   "msg presente");
   MKS_ASSERT_TRUE(StringFind(line, "\"brickIdx\":9883") >= 0,
                   "ctxJson presente");
   CleanFile();
}

void Test_Log_EscapesQuotesInMsg()
{
   CleanFile();
   CMksLogger lg;
   MksError err;
   MKS_ASSERT_TRUE(lg.Open(LOG_TEST_PATH, MKS_LOG_INFO, false, true, err),
                   "Open");
   lg.Log(MKS_LOG_INFO, "T", "he\"llo", "");
   lg.Close();

   string line = ReadLine(LOG_TEST_PATH, 0);
   MKS_ASSERT_TRUE(StringFind(line, "he\\\"llo") >= 0,
                   StringFormat("aspas escapadas (linha='%s')", line));
   CleanFile();
}

void Test_Log_LevelFilterDropsBelowMin()
{
   CleanFile();
   CMksLogger lg;
   MksError err;
   // Nível mínimo WARN — INFO deve ser descartado.
   MKS_ASSERT_TRUE(lg.Open(LOG_TEST_PATH, MKS_LOG_WARN, false, true, err),
                   "Open");
   lg.Log(MKS_LOG_INFO, "T", "dropped", "");
   lg.Close();

   string line = ReadLine(LOG_TEST_PATH, 0);
   MKS_ASSERT_TRUE(StringLen(line) == 0,
                   StringFormat("INFO filtrado (linha='%s')", line));
   CleanFile();
}

void Test_Log_HeaderWritesMetaProvenance()
{
   CleanFile();
   CMksLogger lg;
   MksError err;
   MKS_ASSERT_TRUE(lg.Open(LOG_TEST_PATH, MKS_LOG_INFO, false, true, err),
                   "Open");
   lg.WriteHeader("BrokerX", 12345, "XAUUSD", 2, "EA-Test", 1700000000000);
   lg.Close();

   string line = ReadLine(LOG_TEST_PATH, 0);
   MKS_ASSERT_TRUE(StringFind(line, "\"level\":\"META\"") >= 0,
                   "header é META");
   MKS_ASSERT_TRUE(StringFind(line, "\"broker\":\"BrokerX\"") >= 0,
                   "broker no header");
   MKS_ASSERT_TRUE(StringFind(line, "\"symbol\":\"XAUUSD\"") >= 0,
                   "symbol no header");
   CleanFile();
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksLogger ===");

   MKS_RUN(Test_Log_MscTimestampHasRealMillis);
   MKS_RUN(Test_Log_MscTimestampZeroPadsMillis);
   MKS_RUN(Test_Log_NoMscFallsBackToZeroMillis);

   MKS_RUN(Test_Log_LineCarriesSchemaFields);
   MKS_RUN(Test_Log_EscapesQuotesInMsg);
   MKS_RUN(Test_Log_LevelFilterDropsBelowMin);
   MKS_RUN(Test_Log_HeaderWritesMetaProvenance);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
