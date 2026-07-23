//+------------------------------------------------------------------+
//| @file           : Test_DecisionGolden.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : E2 — golden de DECISAO headless. Roda o
//|                   CMksDecisionRunner sobre o fixture .mkstick REAL
//|                   (config A = baseline, gates de conta OFF) e compara o
//|                   decision journal produzido contra o golden versionado
//|                   (tests/golden/e2-decision/baseline.golden.tsv),
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

input string InpFixturePath  = "MKS-ULTIMATE\\golden\\XAUUSDm_CR_20260720T233245.mkstick";
input string InpGoldenPath   = "MKS-ULTIMATE\\golden\\baseline.golden.tsv";
input string InpProducedPath = "MKS-ULTIMATE\\golden\\dr_baseline_produced.tsv";

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
//| Roda o CMksDecisionRunner (config A do golden) sobre o fixture e   |
//| escreve o decision journal em InpProducedPath.                    |
//+------------------------------------------------------------------+
bool RunBaselineOverFixture(MksError &err)
{
   // Proveniencia do fixture (broker/account/symbol/digits).
   CMksTickFileReader prov;
   if(!prov.Open(InpFixturePath, err)) return false;
   string broker = prov.Broker(); long account = prov.AccountLogin();
   string symbol = prov.Symbol(); int digits = prov.Digits();
   prov.Close();

   // Config A: defaults (brick 3.0, L=10, K=20, FIXED 0.01, custos 0, gates OFF)
   // + slPoints=30000 (unico override — ADR-032). Ver baseline.golden.tsv header.
   MksDecisionRunnerConfig cfg;
   cfg.journalPath = InpProducedPath;
   cfg.feedBroker  = broker;       // so vai pro header '#' (ignorado no diff)
   cfg.feedAccount = account;
   cfg.slPoints    = 30000.0;

   // Symbol com specs do XAUUSDm (digits=3, point=0.001) — o golden foi
   // produzido nesse ambiente. (Sem auto-close no golden, mas casa por seguranca.)
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
//| O teste: journal de decisao produzido == golden (linhas nao-#).   |
//+------------------------------------------------------------------+
void Test_DecisionGolden_MatchesBaseline()
{
   MksError err;
   FileDelete(InpProducedPath);
   MKS_ASSERT_TRUE(RunBaselineOverFixture(err),
                   StringFormat("runner rodou sobre o fixture (%s)", err.ToString()));

   string produced[], golden[];
   int np = ReadDecisionLines(InpProducedPath, produced);
   int ng = ReadDecisionLines(InpGoldenPath, golden);
   MKS_ASSERT_TRUE(ng > 0,  "golden lido (linhas de decisao > 0)");
   MKS_ASSERT_TRUE(np > 0,  "journal produzido lido");
   MKS_ASSERT_EQ_INT(ng, np, "mesmo numero de linhas de decisao (nao-#)");

   int m = MathMin(np, ng);
   int firstDiff = -1;
   for(int i = 0; i < m; i++)
      if(produced[i] != golden[i]) { firstDiff = i; break; }
   if(firstDiff >= 0)
      PrintFormat("DIVERG linha %d:\n  produzido: %s\n  golden   : %s",
                  firstDiff, produced[firstDiff], golden[firstDiff]);

   MKS_ASSERT_TRUE(firstDiff < 0 && np == ng,
                   (firstDiff < 0 && np == ng)
                     ? StringFormat("journal de decisao == golden (%d linhas nao-#)", ng)
                     : StringFormat("divergencia (linha %d; ver Print)", firstDiff));
   FileDelete(InpProducedPath);
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
   if(!FileIsExist(InpGoldenPath))
   {
      Print("=== SETUP INCOMPLETO ===");
      PrintFormat("Golden nao encontrado: Files\\%s", InpGoldenPath);
      Print("Copie tests\\golden\\e2-decision\\baseline.golden.tsv para "
            "<terminal>\\MQL5\\Files\\MKS-ULTIMATE\\golden\\ .");
      return;
   }
   MKS_RUN(Test_DecisionGolden_MatchesBaseline);
   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
