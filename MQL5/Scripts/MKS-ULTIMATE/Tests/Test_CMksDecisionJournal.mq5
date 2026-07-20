//+------------------------------------------------------------------+
//| @file           : Test_CMksDecisionJournal.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksDecisionJournal (E2.0) — o oráculo
//|                   de paridade da camada de decisão. Prova: (1)
//|                   DETERMINISMO — duas execuções idênticas da mesma
//|                   sequência produzem arquivos BYTE-A-BYTE idênticos
//|                   (sem wall-clock no header nem nos dados); (2)
//|                   correção — posOrdinal normalizado 1,2,…; REJECT
//|                   carrega retcode; contagem de eventos.
//| @depends_on     : Core/Trade/CMksDecisionJournal.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Types/OrderRequest.mqh,
//|                   Core/Types/ExecutionResult.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksDecisionJournal.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/Trade/CMksDecisionJournal.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>

MksDecisionJournalHeader MakeHeader()
{
   MksDecisionJournalHeader h;
   h.symbol="XAUUSDm"; h.broker="TESTBROKER"; h.account=123; h.digits=2;
   h.point=0.01; h.tickSize=0.01;
   h.seedMid=2000.0; h.seedTickSeq=1;
   h.spreadPts=13.0; h.slipPts=0.0; h.commPerLot=0.0;
   h.startBalance=10000.0; h.applySwap=false;
   h.slPoints=3000.0; h.magic=527001; h.lotMode="FIXED"; h.fixedLots=0.01; h.riskPct=0.0;
   h.fillDays=0; h.isShadow=false;
   return h;
}

// Sequência FIXA de decisões (função pura — sem tempo real, sem RNG).
void RunSequence(const string path)
{
   CMksDecisionJournal j;
   j.Open(path);
   MksDecisionJournalHeader h = MakeHeader();
   j.WriteHeader(h);

   j.SetBrickContext(0, 100);
   j.RecordSend(MKS_EXEC_FILLED, MKS_ORDER_BUY, 1001, 0.10, 3000.0, 0.0, 0);

   j.SetBrickContext(1, 200);
   j.RecordClose(MKS_EXEC_FILLED, 1001, 0.10, 0);
   j.RecordSend(MKS_EXEC_FILLED, MKS_ORDER_SELL, 1002, 0.10, 3000.0, 0.0, 0);

   // Auto-close de SL da posição SELL, no tick seq 250.
   j.RecordAutoClose(MKS_ORDER_SELL, 1002, 0.10, 250);

   // Send rejeitado pelo gate de risco (código 410).
   j.SetBrickContext(2, 300);
   j.RecordSend(MKS_EXEC_REJECTED, MKS_ORDER_BUY, 0, 0.10, 3000.0, 0.0, 410);

   j.Close();
}

// Lê o arquivo inteiro em bytes.
bool ReadBytes(const string path, uchar &out[])
{
   int h = FileOpen(path, FILE_READ | FILE_BIN);
   if(h == INVALID_HANDLE) return false;
   int n = (int)FileSize(h);
   ArrayResize(out, n);
   if(n > 0) FileReadArray(h, out, 0, n);
   FileClose(h);
   return true;
}

//==================================================================
// Determinismo: dois runs idênticos → arquivos byte-a-byte idênticos
//==================================================================

void Test_DJ_DeterministicBytes()
{
   string pa = "MKS-ULTIMATE\\Tests\\dj_a.tsv";
   string pb = "MKS-ULTIMATE\\Tests\\dj_b.tsv";
   RunSequence(pa);
   RunSequence(pb);

   uchar a[], b[];
   MKS_ASSERT_TRUE(ReadBytes(pa, a), "leu arquivo A");
   MKS_ASSERT_TRUE(ReadBytes(pb, b), "leu arquivo B");
   MKS_ASSERT_EQ_INT(ArraySize(a), ArraySize(b), "mesmo tamanho (determinismo)");

   bool identical = (ArraySize(a) == ArraySize(b));
   int firstDiff = -1;
   if(identical)
      for(int i = 0; i < ArraySize(a); i++)
         if(a[i] != b[i]) { identical = false; firstDiff = i; break; }
   MKS_ASSERT_TRUE(identical,
      StringFormat("bytes idênticos (1a divergência em %d)", firstDiff));

   FileDelete(pa); FileDelete(pb);
}

//==================================================================
// Correção: contagem de eventos + normalização de posOrdinal + retcode
//==================================================================

void Test_DJ_EventCountAndNormalization()
{
   string p = "MKS-ULTIMATE\\Tests\\dj_c.tsv";
   CMksDecisionJournal j;
   j.Open(p);
   MksDecisionJournalHeader h = MakeHeader();
   j.WriteHeader(h);
   j.SetBrickContext(0, 100);
   j.RecordSend(MKS_EXEC_FILLED, MKS_ORDER_BUY, 5555, 0.10, 3000.0, 0.0, 0);
   j.RecordSend(MKS_EXEC_FILLED, MKS_ORDER_SELL, 7777, 0.10, 3000.0, 0.0, 0);
   MKS_ASSERT_EQ_LONG(2, j.EventCount(), "2 eventos registrados");
   j.Close();

   // Relê e verifica: 2 linhas de dados; 1a com posOrdinal=1, 2a com =2.
   int fh = FileOpen(p, FILE_READ | FILE_TXT | FILE_ANSI);
   MKS_ASSERT_TRUE(fh != INVALID_HANDLE, "reabriu para leitura");
   int dataLines = 0;
   long firstOrd = -1, secondOrd = -1;
   bool sawColHeader = false;
   while(!FileIsEnding(fh))
   {
      string line = FileReadString(fh);
      if(StringLen(line) == 0) continue;
      if(StringGetCharacter(line, 0) == '#') continue;   // comentário
      if(StringFind(line, "ord\tev\t") == 0) { sawColHeader = true; continue; }
      string cols[];
      int nc = StringSplit(line, '\t', cols);
      if(nc < 11) continue;
      long posOrd = (long)StringToInteger(cols[6]); // coluna posOrdinal
      if(dataLines == 0) firstOrd = posOrd; else if(dataLines == 1) secondOrd = posOrd;
      dataLines++;
   }
   FileClose(fh);
   MKS_ASSERT_TRUE(sawColHeader, "cabeçalho de colunas presente");
   MKS_ASSERT_EQ_INT(2, dataLines, "2 linhas de dados");
   MKS_ASSERT_EQ_LONG(1, firstOrd, "1o SEND FILLED → posOrdinal 1");
   MKS_ASSERT_EQ_LONG(2, secondOrd, "2o SEND FILLED → posOrdinal 2");

   FileDelete(p);
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksDecisionJournal ===");
   MKS_RUN(Test_DJ_DeterministicBytes);
   MKS_RUN(Test_DJ_EventCountAndNormalization);
   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
