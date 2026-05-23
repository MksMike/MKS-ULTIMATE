//+------------------------------------------------------------------+
//| @file           : Test_CMksStressLabReport.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksStressLabReport — Capture a partir
//|                   de StressMetrics + TradeJournal, ToJsonLine,
//|                   PrintComparison (smoke). Slice 7b ADR-019.
//| @depends_on     : StressLab/CMksStressLabReport.mqh,
//|                   Core/Trade/CMksTradeJournal.mqh,
//|                   Core/Testing/Asserts.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksStressLabReport.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/StressLab/CMksStressLabReport.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksTradeJournal.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>

#define RPT_TOL 1e-9
#define POINT   0.01

//+------------------------------------------------------------------+
//| Helper: monta um journal sintético com N wins/L losses             |
//+------------------------------------------------------------------+
void BuildJournal(CMksTradeJournal &j, int wins, int losses, double winPts, double lossPts)
{
   ulong id = 1;
   for(int i = 0; i < wins; i++)
   {
      j.RecordOpen(id, MKS_ORDER_BUY, 0.1, 2000.0, (long)id);
      j.RecordClose(id, 2000.0 + winPts * POINT, (long)id + 1);
      id++;
   }
   for(int i = 0; i < losses; i++)
   {
      j.RecordOpen(id, MKS_ORDER_BUY, 0.1, 2000.0, (long)id);
      j.RecordClose(id, 2000.0 - lossPts * POINT, (long)id + 1);
      id++;
   }
}

//+------------------------------------------------------------------+
//| Helper: monta CMksStressMetrics inline (não tem setter público)   |
//+------------------------------------------------------------------+
CMksStressMetrics MakeMetrics(long attempts, long filled, long rejPre, long rejReq,
                              long reqEvents, double slipTot, double slipMax)
{
   CMksStressMetrics m;
   m.sendAttempts         = attempts;
   m.sendsFilled          = filled;
   m.sendsRejectedPre     = rejPre;
   m.sendsRejectedRequote = rejReq;
   m.requoteEvents        = reqEvents;
   m.slippageTotalPoints  = slipTot;
   m.slippageMaxPoints    = slipMax;
   return m;
}

//==================================================================
// Capture
//==================================================================

void Test_RPT_CaptureCopiesMetrics()
{
   CMksTradeJournal j(POINT);
   BuildJournal(j, 3, 2, 100.0, 50.0); // 3W de 100pts, 2L de 50pts

   CMksStressMetrics m = MakeMetrics(10, 8, 1, 1, 3, 12.5, 5.0);

   CMksStressLabReport r;
   r.Capture("Light", 42, m, j);

   MKS_ASSERT_EQ_STRING("Light", r.levelName, "levelName");
   MKS_ASSERT_TRUE(r.rngSeed == 42, "rngSeed");

   // Broker metrics
   MKS_ASSERT_EQ_LONG(10, r.sendAttempts,         "sendAttempts");
   MKS_ASSERT_EQ_LONG(8,  r.sendsFilled,          "sendsFilled");
   MKS_ASSERT_EQ_LONG(1,  r.sendsRejectedPre,     "rejPre");
   MKS_ASSERT_EQ_LONG(1,  r.sendsRejectedRequote, "rejReq");
   MKS_ASSERT_EQ_LONG(3,  r.requoteEvents,        "requoteEvents");
   MKS_ASSERT_NEAR_DOUBLE(12.5, r.slippageTotalPoints, RPT_TOL, "slipTot");

   // Journal aggregates
   MKS_ASSERT_EQ_INT(5, r.tradesClosed, "trades 5");
   MKS_ASSERT_EQ_INT(3, r.wins,         "wins 3");
   MKS_ASSERT_EQ_INT(2, r.losses,       "losses 2");
   MKS_ASSERT_NEAR_DOUBLE(0.6, r.winRate, RPT_TOL, "winRate 60%");
   MKS_ASSERT_NEAR_DOUBLE(300.0, r.grossProfitPoints, RPT_TOL, "gross+ 300");
   MKS_ASSERT_NEAR_DOUBLE(100.0, r.grossLossPoints,   RPT_TOL, "gross- 100");
   MKS_ASSERT_NEAR_DOUBLE(3.0,   r.profitFactor,      RPT_TOL, "PF 3.0");
   MKS_ASSERT_NEAR_DOUBLE(200.0, r.netPnLPoints,      RPT_TOL, "net 200");
}

//==================================================================
// ToJsonLine
//==================================================================

void Test_RPT_ToJsonLineHasFields()
{
   CMksTradeJournal j(POINT);
   BuildJournal(j, 2, 1, 100.0, 50.0);
   CMksStressMetrics m = MakeMetrics(5, 3, 1, 1, 1, 3.5, 2.0);

   CMksStressLabReport r;
   r.Capture("High", 7, m, j);

   string line = r.ToJsonLine();
   MKS_ASSERT_TRUE(StringFind(line, "\"level\":\"High\"") >= 0, "level no json");
   MKS_ASSERT_TRUE(StringFind(line, "\"seed\":7") >= 0,         "seed no json");
   MKS_ASSERT_TRUE(StringFind(line, "\"trades\":3") >= 0,       "trades no json");
   MKS_ASSERT_TRUE(StringFind(line, "\"wins\":2") >= 0,         "wins no json");
   MKS_ASSERT_TRUE(StringFind(line, "\"losses\":1") >= 0,       "losses no json");
}

//==================================================================
// PrintComparison smoke
//==================================================================

void Test_RPT_PrintComparisonSmoke()
{
   // 3 reports simulando uma cadeia "None -> Light -> High" com
   // degradacao monotonica de netPnL — apenas verifica que nao crasha.
   CMksStressLabReport reports[];
   ArrayResize(reports, 3);

   {
      CMksTradeJournal j(POINT);
      BuildJournal(j, 5, 1, 100.0, 30.0); // net +470
      CMksStressMetrics m = MakeMetrics(6, 6, 0, 0, 0, 0.0, 0.0);
      reports[0].Capture("None", 1, m, j);
   }
   {
      CMksTradeJournal j(POINT);
      BuildJournal(j, 4, 2, 90.0, 40.0); // net +280
      CMksStressMetrics m = MakeMetrics(8, 6, 1, 1, 2, 8.0, 3.0);
      reports[1].Capture("Light", 2, m, j);
   }
   {
      CMksTradeJournal j(POINT);
      BuildJournal(j, 2, 3, 80.0, 50.0); // net +10
      CMksStressMetrics m = MakeMetrics(10, 5, 3, 2, 5, 25.0, 8.0);
      reports[2].Capture("High", 3, m, j);
   }

   // PrintComparison apenas escreve no Experts tab. Smoke: nao crasha.
   MksStressLabPrintComparison(reports);
   MKS_ASSERT_TRUE(true, "PrintComparison nao crashou");

   // Asserts adicionais: netPnL monotonicamente decrescente
   MKS_ASSERT_TRUE(reports[0].netPnLPoints > reports[1].netPnLPoints,
                   "net None > Light");
   MKS_ASSERT_TRUE(reports[1].netPnLPoints > reports[2].netPnLPoints,
                   "net Light > High");
}

void Test_RPT_PrintComparisonEmptyArray()
{
   CMksStressLabReport empty[];
   MksStressLabPrintComparison(empty);
   MKS_ASSERT_TRUE(true, "PrintComparison([]) nao crashou");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksStressLabReport ===");

   MKS_RUN(Test_RPT_CaptureCopiesMetrics);
   MKS_RUN(Test_RPT_ToJsonLineHasFields);
   MKS_RUN(Test_RPT_PrintComparisonSmoke);
   MKS_RUN(Test_RPT_PrintComparisonEmptyArray);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
