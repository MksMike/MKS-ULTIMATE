//+------------------------------------------------------------------+
//| @file           : Test_CMksDecisionRunner.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes do CMksDecisionRunner (E2.0 fatia 2) — o
//|                   núcleo determinístico da paridade de DECISÃO.
//|                   (1) DETERMINISMO: dirigir o MESMO grafo sobre a
//|                   MESMA sequência sintética 2× produz decision
//|                   journals BYTE-A-BYTE idênticos — dois cenários:
//|                   flips (SEND/CLOSE via broker) e SL hit (AUTOCLOSE
//|                   via drain). (2) Test_DriveOrder: prova que a ordem
//|                   simBroker.OnTick ANTES de builder.IngestTick é
//|                   LOAD-BEARING — o fill do Send depende do último
//|                   OnTick (parte A, baixo nível) e o runner respeita
//|                   a ordem (parte B: abre no mid do tick de gatilho
//|                   ATUAL, não do anterior). Inverter a ordem quebra
//|                   a parte B.
//| @depends_on     : Strategy/Runner/CMksDecisionRunner.mqh,
//|                   Core/Broker/CMksSimulatedBroker.mqh,
//|                   Core/Broker/CMksCostModel.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh,
//|                   Core/Types/Tick.mqh, Core/Types/OrderRequest.mqh,
//|                   Core/Types/ExecutionResult.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksDecisionRunner.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Strategy/Runner/CMksDecisionRunner.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksSimulatedBroker.mqh>
#include <MKS-ULTIMATE/Core/Broker/CMksCostModel.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>

#define RUN_TOL 1e-9

//--- Tick sintético: bid=ask=mid (spread do TICK = 0; o spread de
//--- execução vem do CostModel, aqui também 0 → fill == mid exato).
MksTick MakeTick(const ulong seq, const long timeMsc, const double mid)
{
   MksTick t;
   t.seq     = seq;
   t.timeMsc = timeMsc;
   t.bid     = mid;
   t.ask     = mid;
   t.last    = mid;
   t.volume  = 1;
   t.flags   = 0;
   return t;
}

//--- Config canônica de teste: XAU classic, brick 3.0, sem custo,
//--- FIXED 0.10 lot, conta 10000. slPoints/minSlBricks parametrizados.
MksDecisionRunnerConfig MakeCfg(const string path, const double slPoints,
                                const int minSlBricks)
{
   MksDecisionRunnerConfig c;
   c.journalPath      = path;
   c.feedBroker       = "TESTBROKER";
   c.feedAccount      = 123;
   c.brickSize        = 3.0;
   c.spreadPoints     = 0.0;
   c.slippagePoints   = 0.0;
   c.commissionPerLot = 0.0;
   c.startBalance     = 10000.0;
   c.slPoints         = slPoints;
   c.magic            = 527001;
   c.lotMode          = "FIXED";
   c.fixedLots        = 0.10;
   c.minSlBricks      = minSlBricks;
   c.maxOpenPositions = 1;
   return c;
}

//--- Lê o arquivo inteiro em bytes (para comparar determinismo).
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

//--- Dirige um runner novo sobre `mids`, fecha o journal e devolve as
//--- métricas capturadas ANTES da destruição (sym declarado antes de
//--- run → run destrói primeiro, com sym ainda vivo).
bool RunSeq(const string path, const double &mids[],
            const double slPoints, const int minSlBricks,
            CMksColorReversalMetrics &metricsOut, long &autoCloseOut,
            long &journalEventsOut, int &openOut, MksError &err)
{
   MksDecisionRunnerConfig cfg = MakeCfg(path, slPoints, minSlBricks);
   CMksFakeSymbol sym;                              // point=0.01, tickSize=0.01, tickValue=1.0
   CMksDecisionRunner run(GetPointer(sym), cfg, NULL);
   if(!run.Init(err)) return false;

   int n = ArraySize(mids);
   for(int i = 0; i < n; i++)
   {
      MksTick t = MakeTick((ulong)(i + 1), 1000L + (long)i * 1000L, mids[i]);
      run.OnTick(t);
   }
   run.Finish();

   metricsOut       = run.StrategyMetrics();
   autoCloseOut     = run.AutoCloseTotal();
   journalEventsOut = run.JournalEvents();
   openOut          = run.OpenPositions();
   return true;
}

//--- Compara dois arquivos byte-a-byte; assere igualdade e reporta 1ª
//--- divergência.
void AssertIdenticalBytes(const string pa, const string pb, const string what)
{
   uchar a[], b[];
   MKS_ASSERT_TRUE(ReadBytes(pa, a), StringFormat("%s: leu A", what));
   MKS_ASSERT_TRUE(ReadBytes(pb, b), StringFormat("%s: leu B", what));
   MKS_ASSERT_EQ_INT(ArraySize(a), ArraySize(b),
                     StringFormat("%s: mesmo tamanho", what));
   bool identical = (ArraySize(a) == ArraySize(b));
   int firstDiff = -1;
   if(identical)
      for(int i = 0; i < ArraySize(a); i++)
         if(a[i] != b[i]) { identical = false; firstDiff = i; break; }
   MKS_ASSERT_TRUE(identical,
      StringFormat("%s: bytes idênticos (1a divergência em %d)", what, firstDiff));
}

//==================================================================
// (1a) Determinismo — flips: SEND + CLOSE via broker (SL longe)
//==================================================================
void Test_Runner_DeterministicFlips()
{
   string pa = "MKS-ULTIMATE\\Tests\\dr_flip_a.tsv";
   string pb = "MKS-ULTIMATE\\Tests\\dr_flip_b.tsv";
   // Oscila 3 em 3 → um brick por tick após o 1º; flip a cada extremo.
   double mids[] = {2000, 2003, 2006, 2003, 2000, 2003, 2006, 2003, 2000, 2003};

   CMksColorReversalMetrics ma, mb;
   long aca, acb, jea, jeb;
   int opa, opb;
   MksError err;

   MKS_ASSERT_TRUE(RunSeq(pa, mids, 3000.0, 1, ma, aca, jea, opa, err),
                   StringFormat("run A ok (%s)", err.ToString()));
   MKS_ASSERT_TRUE(RunSeq(pb, mids, 3000.0, 1, mb, acb, jeb, opb, err),
                   StringFormat("run B ok (%s)", err.ToString()));

   // Coberto: a estratégia REALMENTE decidiu (journal não é vazio).
   MKS_ASSERT_EQ_LONG(4, ma.sendsFilled,  "4 sends preenchidos (4 flips)");
   MKS_ASSERT_EQ_LONG(3, ma.closesFilled, "3 closes via broker (flip fecha antes de abrir)");
   MKS_ASSERT_EQ_LONG(0, aca,             "SL longe → nenhum auto-close");
   MKS_ASSERT_EQ_LONG(7, jea,             "7 eventos no journal (1 SEND + 3×(CLOSE+SEND))");

   // Determinismo entre runs.
   MKS_ASSERT_EQ_LONG(ma.sendsFilled,  mb.sendsFilled,  "sends iguais entre runs");
   MKS_ASSERT_EQ_LONG(ma.closesFilled, mb.closesFilled, "closes iguais entre runs");
   MKS_ASSERT_EQ_LONG(jea, jeb, "eventos iguais entre runs");
   AssertIdenticalBytes(pa, pb, "flips");

   FileDelete(pa); FileDelete(pb);
}

//==================================================================
// (1b) Determinismo — SL hit: AUTOCLOSE via drain de PollAutoCloses
//==================================================================
void Test_Runner_DeterministicAutoClose()
{
   string pa = "MKS-ULTIMATE\\Tests\\dr_ac_a.tsv";
   string pb = "MKS-ULTIMATE\\Tests\\dr_ac_b.tsv";
   // SL = 1 brick (slPoints=300, piso de brick desligado). Cada reversão
   // com overshoot cruza o SL ANTES de o builder emitir o flip → o SL
   // dispara (AUTOCLOSE), a estratégia auto-detacha e abre na nova cor.
   double mids[] = {2000, 2003, 2006, 2003, 2007, 2000, 2004};

   CMksColorReversalMetrics ma, mb;
   long aca, acb, jea, jeb;
   int opa, opb;
   MksError err;

   MKS_ASSERT_TRUE(RunSeq(pa, mids, 300.0, 0, ma, aca, jea, opa, err),
                   StringFormat("run A ok (%s)", err.ToString()));
   MKS_ASSERT_TRUE(RunSeq(pb, mids, 300.0, 0, mb, acb, jeb, opb, err),
                   StringFormat("run B ok (%s)", err.ToString()));

   // Coberto: o caminho de auto-close realmente foi exercido.
   MKS_ASSERT_TRUE(aca >= 1,               ">=1 auto-close (SL hit) exercido");
   MKS_ASSERT_TRUE(ma.sendsFilled >= 2,    ">=2 sends preenchidos");
   MKS_ASSERT_TRUE(ma.autoDetected >= 1,   ">=1 auto-detach na estratégia");
   MKS_ASSERT_EQ_LONG(0, ma.closesFilled,  "closes via broker = 0 (todos por SL)");

   // Determinismo entre runs.
   MKS_ASSERT_EQ_LONG(aca, acb, "auto-closes iguais entre runs");
   MKS_ASSERT_EQ_LONG(jea, jeb, "eventos iguais entre runs");
   AssertIdenticalBytes(pa, pb, "autoclose");

   FileDelete(pa); FileDelete(pb);
}

//==================================================================
// (2A) Test_DriveOrder — parte A: a ordem é LOAD-BEARING no nível do
// simulador. O fill do Send depende do último OnTick.
//==================================================================
void Test_DriveOrder_ContractIsLoadBearing()
{
   CMksFakeSymbol sym;                       // point=0.01
   CMksCostModel  cm(0.0, 0.0, 0.0);         // spread/slip/comm = 0 → fill == mid
   MksTick t1 = MakeTick(1, 1000, 2000.0);
   MksTick t2 = MakeTick(2, 2000, 2010.0);

   MksOrderRequest req;
   req.side     = MKS_ORDER_BUY;
   req.lots     = 0.10;
   req.slPoints = 600.0;
   req.tpPoints = 0.0;

   // Ordem CORRETA: OnTick(tick atual) ANTES do Send → fill no mid atual.
   CMksSimulatedBroker bOk(GetPointer(sym), GetPointer(cm), 0.0);
   bOk.OnTick(t2);
   MksExecutionResult rOk = bOk.Send(req);
   MKS_ASSERT_TRUE(rOk.IsFilled(), "Send preenche após OnTick");
   MKS_ASSERT_NEAR_DOUBLE(2010.0, rOk.fillPrice, RUN_TOL,
      "fill == mid do tick ATUAL (ordem correta)");

   // Ordem INVERTIDA (simula IngestTick→Send antes de OnTick(atual)): o
   // broker só viu t1 → fill sai do mid ANTERIOR (stale).
   CMksSimulatedBroker bStale(GetPointer(sym), GetPointer(cm), 0.0);
   bStale.OnTick(t1);
   MksExecutionResult rStale = bStale.Send(req);
   MKS_ASSERT_TRUE(rStale.IsFilled(), "Send preenche com mid stale presente");
   MKS_ASSERT_NEAR_DOUBLE(2000.0, rStale.fillPrice, RUN_TOL,
      "fill == mid ANTERIOR quando OnTick(atual) não veio");
   MKS_ASSERT_TRUE(MathAbs(rOk.fillPrice - rStale.fillPrice) > 1e-6,
      "ordem é load-bearing: fills divergem (2010 vs 2000)");

   // 1º tick sem OnTick nenhum → sem mid → Send ERROR (não preenche).
   CMksSimulatedBroker bNone(GetPointer(sym), GetPointer(cm), 0.0);
   MksExecutionResult rNone = bNone.Send(req);
   MKS_ASSERT_FALSE(rNone.IsFilled(), "Send antes de qualquer OnTick → não preenche");
}

//==================================================================
// (2B) Test_DriveOrder — parte B: o RUNNER respeita a ordem. A posição
// abre no mid do tick de GATILHO atual, não do anterior. Inverter a
// ordem interna do runner faria abrir a 2006 (stale) e quebraria isto.
//==================================================================
void Test_DriveOrder_RunnerRespectsOrder()
{
   string path = "MKS-ULTIMATE\\Tests\\dr_order.tsv";
   // 2000,2003,2006,2003: o 4º tick (mid=2003) é o flip BULL→BEAR que
   // abre um SELL. Fill esperado = 2003 (mid do tick atual, spread 0),
   // NÃO 2006 (mid do tick anterior).
   double mids[] = {2000, 2003, 2006, 2003};

   MksDecisionRunnerConfig cfg = MakeCfg(path, 3000.0, 1);  // SL longe → não auto-fecha
   CMksFakeSymbol sym;
   CMksDecisionRunner run(GetPointer(sym), cfg, NULL);
   MksError err;
   MKS_ASSERT_TRUE(run.Init(err), StringFormat("runner init (%s)", err.ToString()));

   int n = ArraySize(mids);
   for(int i = 0; i < n; i++)
   {
      MksTick t = MakeTick((ulong)(i + 1), 1000L + (long)i * 1000L, mids[i]);
      run.OnTick(t);
   }
   run.Finish();

   MKS_ASSERT_EQ_INT(1, run.OpenPositions(), "1 posição aberta (SELL do flip)");

   MksSimPosition p;
   bool got = run.SimBroker().OpenPositionByIndex(0, p);
   MKS_ASSERT_TRUE(got, "obteve a posição aberta");
   MKS_ASSERT_TRUE(p.side == MKS_ORDER_SELL, "posição é SELL");
   MKS_ASSERT_NEAR_DOUBLE(2003.0, p.openPrice, RUN_TOL,
      "SELL abriu no mid do tick de gatilho ATUAL (2003), não no anterior (2006)");

   FileDelete(path);
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksDecisionRunner ===");
   FolderCreate("MKS-ULTIMATE\\Tests");

   MKS_RUN(Test_Runner_DeterministicFlips);
   MKS_RUN(Test_Runner_DeterministicAutoClose);
   MKS_RUN(Test_DriveOrder_ContractIsLoadBearing);
   MKS_RUN(Test_DriveOrder_RunnerRespectsOrder);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
