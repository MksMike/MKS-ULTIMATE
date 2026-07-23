//+------------------------------------------------------------------+
//| @file           : Test_DecisionGolden.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : E2 — golden de DECISAO headless. Roda o
//|                   CMksDecisionRunner sobre o fixture .mkstick REAL em
//|                   DUAS configs — A (baseline, gates OFF) e B (gate-crossing,
//|                   minEquityAbs=9990) — e compara cada decision journal
//|                   produzido contra o golden versionado
//|                   (tests/golden/e2-decision/{baseline,gate-minequity}.golden.tsv),
//|                   IGNORANDO as linhas '#' (proveniencia/timestamps) —
//|                   mesma normalizacao do verify-parity.ps1. Falha o
//|                   TestRunner em divergencia: a paridade de DECISAO vira
//|                   rede de regressao automatica, nao procedimento manual.
//|                   Config = defaults do MksDecisionRunnerConfig (brick 3.0,
//|                   L=10, K=20, FIXED 0.01, gates off) + slPoints=30000
//|                   (ADR-032: InpSlBricks=10 em digits=3). O fixture e o
//|                   golden precisam estar em Files\MKS-ULTIMATE\golden\.
//| @depends_on     : Strategy/Runner/CMksDecisionRunner.mqh,
//|                   Core/Data/CMksFileTickSource.mqh,
//|                   Core/Data/CMksTickFileReader.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh,
//|                   Core/Types/Tick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_DecisionGolden.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Strategy/Runner/CMksDecisionRunner.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksFileTickSource.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksTickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

input string InpFixturePath      = "MKS-ULTIMATE\\golden\\XAUUSDm_CR_20260720T233245.mkstick";
input string InpGoldenPath       = "MKS-ULTIMATE\\golden\\baseline.golden.tsv";
input string InpGatePath         = "MKS-ULTIMATE\\golden\\gate-minequity.golden.tsv";
input string InpProducedPath     = "MKS-ULTIMATE\\golden\\dr_baseline_produced.tsv";
input string InpProducedGatePath = "MKS-ULTIMATE\\golden\\dr_gate_produced.tsv";

//+------------------------------------------------------------------+
//| Le as linhas NAO-'#' de um TSV (ignora proveniencia/timestamps,   |
//| como verify-parity). Retorna a contagem, ou -1 se o arquivo falha.|
//+------------------------------------------------------------------+
int ReadDecisionLines(const string path, string &out[])
{
   ArrayResize(out, 0);
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) return -1;
   int n = 0;
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      if(StringLen(line) == 0) continue;                        // vazias (incl. final)
      if(StringGetCharacter(line, 0) == '#') continue;          // proveniencia -> ignora
      ArrayResize(out, n + 1);
      out[n] = line;
      n++;
   }
   FileClose(h);
   return n;
}

//+------------------------------------------------------------------+
//| Roda o CMksDecisionRunner sobre o fixture com um dado             |
//| minEquityAbs (0 = config A gates-off; 9990 = config B gate-crossing)|
//| e escreve o decision journal em journalPath.                      |
//+------------------------------------------------------------------+
bool RunOverFixture(const double minEquityAbs, const string journalPath, MksError &err)
{
   // Proveniencia do fixture (broker/account/symbol/digits).
   CMksTickFileReader prov;
   if(!prov.Open(InpFixturePath, err)) return false;
   string broker = prov.Broker(); long account = prov.AccountLogin();
   string symbol = prov.Symbol(); int digits = prov.Digits();
   prov.Close();

   // Config comum: defaults (brick 3.0, L=10, K=20, FIXED 0.01, custos 0) +
   // slPoints=30000 (unico override — ADR-032). Ver *.golden.tsv header.
   // Config A: minEquityAbs=0 (gates off). Config B: minEquityAbs=9990.
   MksDecisionRunnerConfig cfg;
   cfg.journalPath  = journalPath;
   cfg.feedBroker   = broker;       // so vai pro header '#' (ignorado no diff)
   cfg.feedAccount  = account;
   cfg.slPoints     = 30000.0;
   cfg.minEquityAbs = minEquityAbs;

   // Symbol com specs do XAUUSDm (digits=3, point=0.001). tickValue=1.0: no
   // gate-crossing (config B) a perda realizada do 1o trade (flip ~3 USD ->
   // ~30 USD) cai abaixo de 9990 -> o gate 409 dispara logo apos o 1o trade,
   // exatamente como o golden. A partir do trip TODO SEND e REJECTED, logo o
   // journal e deterministico independente do tickValue exato (a perda so
   // precisa passar de 10 USD no 1o trade).
   CMksFakeSymbol sym;
   sym.SetName(symbol); sym.SetDigits(digits);
   sym.SetPoint(0.001); sym.SetTickSize(0.001); sym.SetTickValue(1.0);

   CMksDecisionRunner run(GetPointer(sym), cfg, NULL);
   if(!run.Init(err)) return false;

   // Feed hermetico do fixture (mesma fonte do Replayer, NAO CopyTicksRange).
   CMksFileTickSource src(InpFixturePath, broker, account, symbol);
   if(!src.Open(err)) return false;
   MksTick t;
   while(src.Next(t))
      run.OnTick(t);
   run.Finish();   // escreve o rodape (# total) e fecha o journal
   return true;
}

//+------------------------------------------------------------------+
//| Helper: roda a config e assere journal produzido == golden        |
//| (linhas nao-#), com dump da 1a divergencia.                       |
//+------------------------------------------------------------------+
void AssertJournalMatchesGolden(const double minEquityAbs, const string producedPath,
                                const string goldenPath, const string label)
{
   MksError err;
   FileDelete(producedPath);
   MKS_ASSERT_TRUE(RunOverFixture(minEquityAbs, producedPath, err),
                   StringFormat("%s: runner rodou (%s)", label, err.ToString()));

   string produced[], golden[];
   int np = ReadDecisionLines(producedPath, produced);
   int ng = ReadDecisionLines(goldenPath, golden);
   MKS_ASSERT_TRUE(ng > 0,   StringFormat("%s: golden lido (>0 linhas)", label));
   MKS_ASSERT_TRUE(np > 0,   StringFormat("%s: journal produzido lido", label));
   MKS_ASSERT_EQ_INT(ng, np, StringFormat("%s: mesmo numero de linhas nao-#", label));

   int m = MathMin(np, ng);
   int firstDiff = -1;
   for(int i = 0; i < m; i++)
      if(produced[i] != golden[i]) { firstDiff = i; break; }
   if(firstDiff >= 0)
      PrintFormat("[%s] DIVERG linha %d:\n  produzido: %s\n  golden   : %s",
                  label, firstDiff, produced[firstDiff], golden[firstDiff]);

   MKS_ASSERT_TRUE(firstDiff < 0 && np == ng,
                   (firstDiff < 0 && np == ng)
                     ? StringFormat("%s: journal == golden (%d linhas nao-#)", label, ng)
                     : StringFormat("%s: divergencia (linha %d; ver Print)", label, firstDiff));
   FileDelete(producedPath);
}

// Config A (baseline, gates OFF): 33 decisoes / 17 flips.
void Test_DecisionGolden_MatchesBaseline()
{
   AssertJournalMatchesGolden(0.0, InpProducedPath, InpGoldenPath, "config-A baseline");
}

// Config B (gate-crossing, minEquityAbs=9990): 1 trade + 16 SEND REJECTED 409.
void Test_DecisionGolden_MatchesGate()
{
   AssertJournalMatchesGolden(9990.0, InpProducedGatePath, InpGatePath, "config-B gate-minequity");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_DecisionGolden (E2 — golden de decisao headless) ===");
   if(!FileIsExist(InpFixturePath))
   {
      Print("=== SETUP INCOMPLETO ===");
      PrintFormat("Fixture nao encontrado: Files\\%s", InpFixturePath);
      Print("Copie tests\\golden\\e2-decision\\XAUUSDm_CR_20260720T233245.mkstick para "
            "<terminal>\\MQL5\\Files\\MKS-ULTIMATE\\golden\\ .");
      return;
   }
   if(!FileIsExist(InpGoldenPath) || !FileIsExist(InpGatePath))
   {
      Print("=== SETUP INCOMPLETO ===");
      PrintFormat("Golden(s) nao encontrado(s) em Files\\MKS-ULTIMATE\\golden\\ (baseline/gate).");
      Print("Copie tests\\golden\\e2-decision\\baseline.golden.tsv e gate-minequity.golden.tsv "
            "para <terminal>\\MQL5\\Files\\MKS-ULTIMATE\\golden\\ .");
      return;
   }
   MKS_RUN(Test_DecisionGolden_MatchesBaseline);
   MKS_RUN(Test_DecisionGolden_MatchesGate);
   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
