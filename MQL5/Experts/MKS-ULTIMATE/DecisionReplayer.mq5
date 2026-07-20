//+------------------------------------------------------------------+
//| @file           : DecisionReplayer.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Experts / MKS-ULTIMATE
//| @responsibility : EA de replay da camada de DECISÃO (E2.1). Monta o
//|                   composition root FORA do Strategy Tester e dirige o
//|                   CMksDecisionRunner (grafo DDR) sobre um .mkstick,
//|                   emitindo um decision journal TSV determinístico. É o
//|                   irmão do Replayer.mq5 (que emite .mksbk / paridade
//|                   feed→brick): este emite o stream de ORDENS, o
//|                   oráculo de paridade da DECISÃO. Dois runs do mesmo
//|                   .mkstick + config pinada → journal byte-a-byte
//|                   idêntico (determinismo); um run vs golden → regressão
//|                   (tools/verify-parity.ps1 -JournalA -JournalB).
//|                   Reframe honesto (checkpoint §4.1): prova DETERMINISMO
//|                   sim↔sim, NÃO fidelidade ao broker real.
//| @depends_on     : Core/Data/CMksFileTickSource.mqh,
//|                   Core/Data/CMksMultiFileTickSource.mqh,
//|                   Core/Data/CMksTickFileReader.mqh,
//|                   Core/Symbol/CMksMt5Symbol.mqh,
//|                   Core/Log/CMksLogger.mqh,
//|                   Strategy/Runner/CMksDecisionRunner.mqh,
//|                   Core/Interfaces/ITickSource.mqh,
//|                   Core/Types/Tick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Experts/MKS-ULTIMATE/DecisionReplayer.mq5
//+------------------------------------------------------------------+
#property strict
#property copyright "MKS-ULTIMATE"
#property version   "1.00"

#include <MKS-ULTIMATE/Core/Data/CMksFileTickSource.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksMultiFileTickSource.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksTickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Symbol/CMksMt5Symbol.mqh>
#include <MKS-ULTIMATE/Core/Log/CMksLogger.mqh>
#include <MKS-ULTIMATE/Strategy/Runner/CMksDecisionRunner.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/ITickSource.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

//--- Inputs --------------------------------------------------------
input group "=== Fonte de ticks ==="
input string InpTickFilePath  = "MKS-ULTIMATE\\Ticks\\XAUUSDm_20260520.mkstick"; // single-file
input string InpTickFolder    = "";        // multi: pasta com .mkstick (vazia = single)
input string InpSymbolPrefix  = "";        // multi: prefixo de nome (ex: XAUUSDm)

input group "=== Brick (classic, ADR-026) ==="
input double InpBrickSize        = 3.0;    // mesmo valor do Producer/Replayer
input int    InpInvalidTickLimit = 10;     // L (ADR-006)
input int    InpThresholdLimit   = 20;     // K (ADR-011)

input group "=== Estratégia (ColorReversal) ==="
input double InpSlPoints         = 3000.0; // SL em pontos do símbolo
input long   InpMagic            = 527001; // magic da estratégia

input group "=== Sizing ==="
input string InpLotMode          = "FIXED"; // "FIXED" | "PERCENT"
input double InpFixedLots         = 0.01;   // lote fixo (FIXED)
input double InpRiskPct           = 1.0;    // % do balance por trade (PERCENT)

input group "=== Conta sim + CostModel (bundle pinado) ==="
input double InpStartBalance     = 10000.0;
input double InpSpreadPts         = 0.0;    // spread do CostModel (pontos)
input double InpSlipPts           = 0.0;    // slippage do CostModel (pontos)
input double InpCommPerLot        = 0.0;    // comissão por lote (moeda)

input group "=== Piso de SL (E0.3/M12) ==="
input int    InpMinSlBricks      = 1;       // piso de SL em bricks (>=1 mantém o gate ativo)
input double InpMinSlFloorPts     = 0.0;    // belt absoluto do piso (pontos)

input group "=== Risco por estratégia / conta ==="
input int    InpMaxOpenPositions = 1;       // ColorReversal é 1 posição
input double InpMaxDailyLossPct   = 0.0;    // 0 = sem limite
input double InpMaxDrawdownPct    = 0.0;    // 0 = sem limite
input double InpMinEquityAbs      = 0.0;    // 0 = sem circuit breaker absoluto

input group "=== Output ==="
input string InpJournalPath      = "";      // vazio = auto: Journals\decision_<stem>_<TS>.tsv
input bool   InpLogToFile        = true;

input group "=== Performance ==="
input int    InpTimerMs          = 1;       // OnTimer (1ms = throughput máximo)
input int    InpTicksPerCycle    = 10000;   // máx ticks por chamada do OnTimer

//--- Estado global -------------------------------------------------
ISymbol                 *g_iSymbol      = NULL;
ITickSource             *g_source       = NULL;
CMksFileTickSource      *g_singleSource = NULL;  // ownership single
CMksMultiFileTickSource *g_multiSource  = NULL;  // ownership multi
CMksLogger              *g_logger       = NULL;
CMksDecisionRunner      *g_runner       = NULL;

string  g_sourceSymbol  = "";
string  g_sourceBroker  = "";
long    g_sourceAccount = 0;
int     g_sourceDigits  = 0;
string  g_journalPath   = "";
string  g_logPath       = "";

bool    g_eof           = false;
bool    g_halted        = false;   // source halt (não o do builder — esse fica no runner)
long    g_ticksConsumed = 0;
ulong   g_startMs       = 0;
bool    g_isMultiMode   = false;
bool    g_finished      = false;

//+------------------------------------------------------------------+
//| Lê proveniência do primeiro .mkstick (header-only).               |
//+------------------------------------------------------------------+
bool ReadFirstFileProvenance(const string &path, string &broker, long &account,
                              string &symbol, int &digits, MksError &err)
{
   CMksTickFileReader r;
   if(!r.Open(path, err)) return false;
   broker  = r.Broker();
   account = r.AccountLogin();
   symbol  = r.Symbol();
   digits  = r.Digits();
   r.Close();
   return true;
}

//+------------------------------------------------------------------+
//| Lista .mkstick numa pasta por prefixo (ordem cronológica ==       |
//| lexicográfica pelo naming YYYYMMDD).                              |
//+------------------------------------------------------------------+
int ListMkstickFolder(const string &folder, const string &symbolPrefix, string &out[])
{
   ArrayResize(out, 0);
   string pattern = folder + "\\" + symbolPrefix + "_*.mkstick";
   string filename;
   long handle = FileFindFirst(pattern, filename);
   if(handle == INVALID_HANDLE) return 0;

   int n = 0;
   do
   {
      if(StringFind(filename, ".mkstick") < 0) continue;
      ArrayResize(out, n + 1);
      out[n] = folder + "\\" + filename;
      n++;
   } while(FileFindNext(handle, filename));
   FileFindClose(handle);

   if(n > 1) ArraySort(out);
   return n;
}

//+------------------------------------------------------------------+
//| Extrai stem (nome sem extensão e sem path) de um caminho.         |
//+------------------------------------------------------------------+
string PathStem(const string &path)
{
   int len = StringLen(path);
   int lastSep = -1;
   for(int i = len - 1; i >= 0; i--)
   {
      ushort c = StringGetCharacter(path, i);
      if(c == '\\' || c == '/') { lastSep = i; break; }
   }
   string name = (lastSep >= 0) ? StringSubstr(path, lastSep + 1) : path;
   int dot = StringFind(name, ".");
   return (dot > 0) ? StringSubstr(name, 0, dot) : name;
}

//+------------------------------------------------------------------+
//| Auto-nome do journal quando InpJournalPath vazio.                 |
//+------------------------------------------------------------------+
string AutoJournalPath(const string &sourceStem)
{
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   string stamp = StringFormat("%04d%02d%02dT%02d%02d%02d",
                                dt.year, dt.mon, dt.day,
                                dt.hour, dt.min, dt.sec);
   return StringFormat("MKS-ULTIMATE\\Journals\\decision_%s_%s.tsv",
                       sourceStem, stamp);
}

//+------------------------------------------------------------------+
//| Cleanup global ordenado. O runner é dono do próprio grafo — só o  |
//| deletamos; ele desmonta o resto. Source/logger/symbol são nossos. |
//+------------------------------------------------------------------+
void Cleanup()
{
   if(g_runner       != NULL) { delete g_runner;       g_runner       = NULL; }
   if(g_singleSource != NULL) { delete g_singleSource; g_singleSource = NULL; g_source = NULL; }
   if(g_multiSource  != NULL) { delete g_multiSource;  g_multiSource  = NULL; g_source = NULL; }
   if(g_logger       != NULL) { delete g_logger;       g_logger       = NULL; }
   if(g_iSymbol      != NULL) { delete g_iSymbol;      g_iSymbol      = NULL; }
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_startMs = GetTickCount();
   g_isMultiMode = (StringLen(InpTickFolder) > 0 && StringLen(InpSymbolPrefix) > 0);

   // 1. Arquivo "primeiro" para proveniência canônica.
   string firstPath = "";
   string allPaths[];
   if(g_isMultiMode)
   {
      int n = ListMkstickFolder(InpTickFolder, InpSymbolPrefix, allPaths);
      if(n == 0)
      {
         PrintFormat("DecisionReplayer: nenhum .mkstick em '%s' prefixo '%s'",
                     InpTickFolder, InpSymbolPrefix);
         return INIT_PARAMETERS_INCORRECT;
      }
      firstPath = allPaths[0];
   }
   else
   {
      if(StringLen(InpTickFilePath) == 0)
      {
         Print("DecisionReplayer: InpTickFilePath vazio (e multi não ativado)");
         return INIT_PARAMETERS_INCORRECT;
      }
      firstPath = InpTickFilePath;
   }

   // 2. Proveniência do primeiro arquivo.
   MksError err;
   if(!ReadFirstFileProvenance(firstPath, g_sourceBroker, g_sourceAccount,
                                g_sourceSymbol, g_sourceDigits, err))
   {
      PrintFormat("DecisionReplayer: proveniência de '%s' falhou: %s",
                  firstPath, err.ToString());
      return INIT_FAILED;
   }

   // 3. SymbolSelect (borda). O símbolo real fornece TickValue/TickSize/
   //    Point à conta sim e ao sizer — parte do bundle pinado.
   bool symbolSelected = SymbolSelect(g_sourceSymbol, true);

   // 4. Composition root (borda ADR-013 §2).
   g_iSymbol = new CMksMt5Symbol(g_sourceSymbol);

   FolderCreate("MKS-ULTIMATE");
   FolderCreate("MKS-ULTIMATE\\Journals");
   FolderCreate("MKS-ULTIMATE\\Logs");

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   string stamp = StringFormat("%04d%02d%02dT%02d%02d%02d",
                                dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);

   // 5. Logger.
   g_logger = new CMksLogger();
   g_logPath = StringFormat("MKS-ULTIMATE\\Logs\\DecisionReplayer_%s_%s.log",
                            g_sourceSymbol, stamp);
   if(!g_logger.Open(g_logPath, MKS_LOG_INFO, true, InpLogToFile, err))
   {
      PrintFormat("DecisionReplayer: logger.Open falhou: %s", err.ToString());
      Cleanup();
      return INIT_FAILED;
   }
   g_logger.WriteHeader(g_sourceBroker, g_sourceAccount, g_sourceSymbol,
                        g_sourceDigits, "DecisionReplayer", (long)now * 1000);
   g_logger.Info("DecisionReplayer", "starting",
      StringFormat("\"mode\":\"%s\",\"firstPath\":\"%s\",\"symbolSelected\":%s,"
                   "\"S\":%.4f,\"L\":%d,\"K\":%d",
                   (g_isMultiMode ? "multi" : "single"),
                   MksJsonEscape(firstPath),
                   (symbolSelected ? "true" : "false"),
                   InpBrickSize, InpInvalidTickLimit, InpThresholdLimit));

   // 5.5 Numéricos do símbolo são LOAD-BEARING aqui (sizer, piso de SL,
   //     conta sim) — diferente do Replayer, onde o símbolo é só metadado
   //     de brick. Um símbolo indisponível (ex.: .mkstick de outra
   //     corretora) dá Point/TickSize/TickValue=0 → sizing/risco/PnL
   //     degenerados e SILENCIOSOS, com o EA reportando "sucesso". O
   //     Validate do sizer pega o caso VolumeStep=0, mas apontaria o
   //     sintoma; aqui falhamos na causa-raiz com mensagem acionável
   //     (disciplina anti-falha-silenciosa do projeto).
   if(g_iSymbol.Point() <= 0.0 || g_iSymbol.TickSize() <= 0.0 ||
      g_iSymbol.TickValue() <= 0.0)
   {
      string smsg = StringFormat(
         "símbolo '%s' sem numéricos usáveis (point=%.6f tickSize=%.6f "
         "tickValue=%.6f, selected=%s) — sizer/risco/conta seriam "
         "degenerados. O terminal tem esse símbolo disponível?",
         g_sourceSymbol, g_iSymbol.Point(), g_iSymbol.TickSize(),
         g_iSymbol.TickValue(), (symbolSelected ? "true" : "false"));
      g_logger.Error("DecisionReplayer", "symbol numerics unusable",
         StringFormat("\"msg\":\"%s\"", MksJsonEscape(smsg)));
      Alert("DecisionReplayer: " + smsg);
      Cleanup();
      return INIT_FAILED;
   }

   // 6. Source.
   if(g_isMultiMode)
   {
      g_multiSource = new CMksMultiFileTickSource(allPaths, g_sourceBroker,
                                                   g_sourceAccount, g_sourceSymbol);
      if(!g_multiSource.Open(err))
      {
         g_logger.Error("DecisionReplayer", "multi source open failed",
            StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
         Cleanup();
         return INIT_FAILED;
      }
      g_source = g_multiSource;
      g_logger.Info("DecisionReplayer", "multi source opened",
         StringFormat("\"fileCount\":%d", g_multiSource.FileCount()));
   }
   else
   {
      g_singleSource = new CMksFileTickSource(InpTickFilePath, g_sourceBroker,
                                               g_sourceAccount, g_sourceSymbol);
      if(!g_singleSource.Open(err))
      {
         g_logger.Error("DecisionReplayer", "single source open failed",
            StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
         Cleanup();
         return INIT_FAILED;
      }
      g_source = g_singleSource;
      g_logger.Info("DecisionReplayer", "single source opened",
         StringFormat("\"path\":\"%s\",\"tickCount\":%I64d",
                      MksJsonEscape(InpTickFilePath), g_singleSource.TickCount()));
   }

   // 7. Journal path. MQL5 não passa rvalue a parâmetro por referência
   //    (nem const) — PathStem em variável local antes de AutoJournalPath.
   if(StringLen(InpJournalPath) > 0)
      g_journalPath = InpJournalPath;
   else
   {
      string stem = PathStem(firstPath);
      g_journalPath = AutoJournalPath(stem);
   }

   // 8. Config pinada do runner (o bundle versionado do golden).
   MksDecisionRunnerConfig cfg;
   cfg.journalPath      = g_journalPath;
   cfg.feedBroker       = g_sourceBroker;
   cfg.feedAccount      = g_sourceAccount;
   cfg.isShadow         = false;
   cfg.fillDays         = 0;             // paridade exige 0 (E2.3)
   cfg.brickSize        = InpBrickSize;
   cfg.invalidLimit     = InpInvalidTickLimit;
   cfg.thresholdLimit   = InpThresholdLimit;
   cfg.spreadPoints     = InpSpreadPts;
   cfg.slippagePoints   = InpSlipPts;
   cfg.commissionPerLot = InpCommPerLot;
   cfg.startBalance     = InpStartBalance;
   cfg.applySwap        = false;         // v1: swap OFF
   cfg.slPoints         = InpSlPoints;
   cfg.magic            = InpMagic;
   cfg.lotMode          = InpLotMode;
   cfg.fixedLots        = InpFixedLots;
   cfg.riskPct          = InpRiskPct;
   cfg.requireSl        = true;
   cfg.maxLotsPerTrade  = 0.0;
   cfg.minSlFloorPts    = InpMinSlFloorPts;
   cfg.minSlBricks      = InpMinSlBricks;
   cfg.maxOpenPositions = InpMaxOpenPositions;
   cfg.maxTotalLots     = 0.0;
   cfg.maxDailyLossPct  = InpMaxDailyLossPct;
   cfg.maxDrawdownPct   = InpMaxDrawdownPct;
   cfg.minEquityAbs     = InpMinEquityAbs;

   // 9. Runner (dono do grafo DDR + helper de ordem-por-tick).
   g_runner = new CMksDecisionRunner(g_iSymbol, cfg, g_logger);
   if(!g_runner.Init(err))
   {
      g_logger.Error("DecisionReplayer", "runner init failed",
         StringFormat("\"err\":\"%s\"", MksJsonEscape(err.ToString())));
      Cleanup();
      return INIT_FAILED;
   }
   g_logger.Info("DecisionReplayer", "runner ready",
      StringFormat("\"journalPath\":\"%s\",\"lotMode\":\"%s\",\"slPoints\":%.2f,"
                   "\"startBalance\":%.2f,\"minSlBricks\":%d,\"maxOpenPositions\":%d",
                   MksJsonEscape(g_journalPath), InpLotMode, InpSlPoints,
                   InpStartBalance, InpMinSlBricks, InpMaxOpenPositions));

   // 10. Timer para processar ticks.
   int timerMs = (InpTimerMs > 0) ? InpTimerMs : 1;
   EventSetMillisecondTimer(timerMs);

   g_logger.Info("DecisionReplayer", "OnInit done, replay dispatched via OnTimer",
      StringFormat("\"timerMs\":%d,\"ticksPerCycle\":%d", timerMs, InpTicksPerCycle));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Processa N ticks por chamada. Retorna true se atingiu EOF/halt.   |
//| O runner absorve as guardas do builder (inválido/K/halt) e mantém |
//| os contadores — aqui só drenamos o source e alimentamos o runner. |
//+------------------------------------------------------------------+
bool ProcessBatch()
{
   if(g_halted || g_eof) return true;

   int processed = 0;
   MksTick t;
   while(processed < InpTicksPerCycle)
   {
      if(!g_source.Next(t))
      {
         if(g_isMultiMode)
         {
            if(g_multiSource.SeqDiscontinuityDetected())
            {
               g_logger.Error("DecisionReplayer", "multi seq discontinuity",
                  StringFormat("\"msg\":\"%s\"",
                               MksJsonEscape(g_multiSource.SeqDiscontinuityMsg())));
               g_halted = true;
               return true;
            }
            if(g_multiSource.AdvanceFailureDetected())
            {
               g_logger.Error("DecisionReplayer", "multi advance failure",
                  StringFormat("\"msg\":\"%s\"",
                               MksJsonEscape(g_multiSource.AdvanceErrorMsg())));
               g_halted = true;
               return true;
            }
         }
         g_eof = true;
         return true;
      }
      g_ticksConsumed++;
      g_runner.OnTick(t);   // grafo DDR: ordem-por-tick load-bearing lá dentro
      processed++;
   }
   return false; // mais ticks pendentes — OnTimer volta
}

//+------------------------------------------------------------------+
//| Termina o replay: fecha o journal, loga summary, encerra o EA.    |
//+------------------------------------------------------------------+
void FinishReplay()
{
   EventKillTimer();
   if(g_finished) { ExpertRemove(); return; }

   if(g_runner != NULL) g_runner.Finish();   // escreve rodapé + fecha o journal
   g_finished = true;

   ulong elapsedMs = GetTickCount() - g_startMs;
   double ticksPerSec = (elapsedMs > 0) ? (double)g_ticksConsumed * 1000.0 / elapsedMs : 0.0;

   if(g_logger != NULL && g_runner != NULL)
   {
      CMksColorReversalMetrics m = g_runner.StrategyMetrics();
      g_logger.Info("DecisionReplayer", "replay summary",
         StringFormat("\"eof\":%s,\"srcHalted\":%s,\"builderHalted\":%s,"
                      "\"ticksConsumed\":%I64d,\"ticksInvalid\":%I64d,"
                      "\"ticksK102\":%I64d,\"ticksK105\":%I64d,\"bricksSeen\":%I64d,"
                      "\"journalEvents\":%I64d,\"sendsFilled\":%I64d,"
                      "\"closesFilled\":%I64d,\"autoCloseTotal\":%I64d,"
                      "\"openAtEnd\":%d,\"balance\":%.2f,\"equity\":%.2f,"
                      "\"elapsedMs\":%I64u,\"ticksPerSec\":%.0f,"
                      "\"journalPath\":\"%s\",\"logPath\":\"%s\"",
                      (g_eof ? "true" : "false"),
                      (g_halted ? "true" : "false"),
                      (g_runner.Halted() ? "true" : "false"),
                      g_ticksConsumed, g_runner.TicksInvalid(),
                      g_runner.TicksK102(), g_runner.TicksK105(), g_runner.BricksSeen(),
                      g_runner.JournalEvents(), m.sendsFilled,
                      m.closesFilled, g_runner.AutoCloseTotal(),
                      g_runner.OpenPositions(), g_runner.Balance(), g_runner.Equity(),
                      elapsedMs, ticksPerSec,
                      MksJsonEscape(g_journalPath), MksJsonEscape(g_logPath)));
      g_logger.Close();
   }

   ExpertRemove();
}

//+------------------------------------------------------------------+
void OnTimer()
{
   if(g_eof || g_halted) return;
   if(ProcessBatch()) FinishReplay();
}

//+------------------------------------------------------------------+
//| OnTick: DecisionReplayer NÃO consome ticks live — o feed é o       |
//| .mkstick. Vazio deliberadamente; o motor roda em OnTimer.          |
//+------------------------------------------------------------------+
void OnTick() {}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   // Deinit por desanexo antes do EOF: fecha o journal para não deixar
   // rodapé faltando (o Finish é idempotente).
   if(!g_finished && g_runner != NULL)
   {
      g_runner.Finish();
      if(g_logger != NULL)
      {
         g_logger.Info("DecisionReplayer", "deinit before EOF",
            StringFormat("\"reason\":%d,\"ticksConsumed\":%I64d",
                         reason, g_ticksConsumed));
         g_logger.Close();
      }
      g_finished = true;
   }
   Cleanup();
}
//+------------------------------------------------------------------+
