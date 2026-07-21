//+------------------------------------------------------------------+
//| @file           : CMksStressLabReport.mqh
//| @project        : MKS-ULTIMATE
//| @module         : StressLab
//| @responsibility : Estrutura de relatorio agregado de uma corrida
//|                   sob um nivel de stress + formatador comparativo
//|                   multi-nivel. Coleta passiva: caller chama
//|                   CaptureFromJournal apos a corrida, com snapshot
//|                   do CMksStressLabBroker e do CMksTradeJournal.
//|                   Fase 7 ADR-019 — criterio de saida (tabela de
//|                   sensibilidade entre niveis).
//| @depends_on     : Core/Trade/CMksTradeJournal.mqh,
//|                   StressLab/CMksStressLabBroker.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/StressLab/CMksStressLabReport.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_STRESSLAB_CMKSSTRESSLABREPORT_MQH
#define MKS_ULTIMATE_STRESSLAB_CMKSSTRESSLABREPORT_MQH

#include <MKS-ULTIMATE/Core/Trade/CMksTradeJournal.mqh>
#include <MKS-ULTIMATE/StressLab/CMksStressLabBroker.mqh>

// Snapshot de uma corrida — estrutura plana (POD), copiavel.
//
// Filosofia: o report nao orquestra a execucao; ele agrega resultados
// apos o fato. O caller (futuro CStressLabEngine ou EA Replayer
// rodando em modo multi-stress) faz N corridas, captura N reports,
// e passa o array para PrintComparison.
struct CMksStressLabReport
{
   // Identidade do run
   string levelName;
   uint   rngSeed;

   // Stress broker metrics
   long   sendAttempts;
   long   sendsFilled;
   long   sendsRejectedPre;
   long   sendsRejectedRequote;
   long   requoteEvents;
   double slippageTotalPoints;
   double slippageMaxPoints;

   // Trade journal aggregates
   int    tradesClosed;
   int    wins;
   int    losses;
   double winRate;
   double grossProfitPoints;
   double grossLossPoints;
   double profitFactor;
   double netPnLPoints;
   double avgWinPoints;
   double avgLossPoints;
   double largestWinPoints;
   double largestLossPoints;
   int    maxConsecutiveWins;
   int    maxConsecutiveLosses;

   // Resultado em MOEDA — eixo 3 (E4.1/ADR-034). hasCurrency=false quando o
   // journal não teve SetMoneyConversion (os campos abaixo ficam 0).
   bool   hasCurrency;
   double netPnLCurrency;       // líquido = bruto − comissão − swap
   double grossProfitCurrency;
   double grossLossCurrency;
   double totalCommission;
   double totalSwap;

   CMksStressLabReport()
   {
      levelName = ""; rngSeed = 0;
      sendAttempts = 0; sendsFilled = 0;
      sendsRejectedPre = 0; sendsRejectedRequote = 0;
      requoteEvents = 0;
      slippageTotalPoints = 0.0; slippageMaxPoints = 0.0;
      tradesClosed = 0; wins = 0; losses = 0;
      winRate = 0.0;
      grossProfitPoints = 0.0; grossLossPoints = 0.0;
      profitFactor = 0.0; netPnLPoints = 0.0;
      avgWinPoints = 0.0; avgLossPoints = 0.0;
      largestWinPoints = 0.0; largestLossPoints = 0.0;
      maxConsecutiveWins = 0; maxConsecutiveLosses = 0;
      hasCurrency = false;
      netPnLCurrency = 0.0; grossProfitCurrency = 0.0; grossLossCurrency = 0.0;
      totalCommission = 0.0; totalSwap = 0.0;
   }

   // Captura snapshot de uma corrida. Caller invoca depois de
   // executar a estrategia sob o stress configurado.
   void Capture(const string &name, uint seed,
                const CMksStressMetrics &m,
                const CMksTradeJournal &j)
   {
      levelName = name;
      rngSeed   = seed;

      sendAttempts         = m.sendAttempts;
      sendsFilled          = m.sendsFilled;
      sendsRejectedPre     = m.sendsRejectedPre;
      sendsRejectedRequote = m.sendsRejectedRequote;
      requoteEvents        = m.requoteEvents;
      slippageTotalPoints  = m.slippageTotalPoints;
      slippageMaxPoints    = m.slippageMaxPoints;

      tradesClosed         = j.ClosedCount();
      wins                 = j.WinCount();
      losses               = j.LossCount();
      winRate              = j.WinRate();
      grossProfitPoints    = j.GrossProfitPoints();
      grossLossPoints      = j.GrossLossPoints();
      profitFactor         = j.ProfitFactor();
      netPnLPoints         = j.NetPnLPoints();
      avgWinPoints         = j.AvgWinPoints();
      avgLossPoints        = j.AvgLossPoints();
      largestWinPoints     = j.LargestWinPoints();
      largestLossPoints    = j.LargestLossPoints();
      maxConsecutiveWins   = j.MaxConsecutiveWins();
      maxConsecutiveLosses = j.MaxConsecutiveLosses();

      // Eixo 3 (E4.1): resultado em moeda + custo. Só válido se o journal
      // tem conversão de moeda; senão os campos ficam 0 e hasCurrency=false.
      // TotalCommission é dado bruto e é capturado sempre (é só uma soma).
      hasCurrency         = j.HasMoneyConversion();
      totalCommission     = j.TotalCommission();
      totalSwap           = j.TotalSwap();
      grossProfitCurrency = j.GrossProfitCurrency();
      grossLossCurrency   = j.GrossLossCurrency();
      netPnLCurrency      = j.NetPnLCurrency();
   }

   // Linha resumo em formato JSON-line (alinhado a ADR-007).
   string ToJsonLine() const
   {
      return StringFormat(
         "{\"level\":\"%s\",\"seed\":%u,"
         "\"trades\":%d,\"wins\":%d,\"losses\":%d,"
         "\"winRate\":%.4f,\"profitFactor\":%.4f,\"netPnLPts\":%.2f,"
         "\"sendRej\":%I64d,\"slipTotPts\":%.2f,\"slipMaxPts\":%.2f,"
         "\"hasCcy\":%s,\"netPnLCcy\":%.2f,\"commission\":%.2f}",
         levelName, rngSeed,
         tradesClosed, wins, losses,
         winRate, profitFactor, netPnLPoints,
         (sendsRejectedPre + sendsRejectedRequote),
         slippageTotalPoints, slippageMaxPoints,
         (hasCurrency ? "true" : "false"), netPnLCurrency, totalCommission);
   }
};

// PrintComparison — emite tabela ASCII comparativa de N reports.
//
// Usa Print() do MQL5 (vai pro Experts tab). Imprime cabecalho,
// uma linha por report, e uma linha-resumo destacando degradacao
// quando net PnL decresce entre niveis consecutivos.
//
// Nao retorna string (MQL5 imprime direto); para captura, use
// ToJsonLine de cada report.
void MksStressLabPrintComparison(const CMksStressLabReport &reports[])
{
   int n = ArraySize(reports);
   if(n == 0) { Print("[StressLab] sem reports"); return; }

   Print("=========================================================================================");
   Print("StressLab — Comparativo Multi-Nivel");
   Print("=========================================================================================");
   Print(StringFormat("%-12s %6s %6s %6s %8s %8s %10s %8s %8s %11s %10s",
                      "Level", "Trades", "Wins", "Loss", "WinRate", "PF", "NetPnLpts",
                      "Rej", "SlipPts", "NetPnLccy", "Comm"));
   Print("-----------------------------------------------------------------------------------------");

   double prevNet = 0.0; bool hasPrev = false;
   for(int i = 0; i < n; i++)
   {
      string pf = (reports[i].profitFactor >= 1e17)
                  ? "  INF " : StringFormat("%8.3f", reports[i].profitFactor);
      long totalRej = reports[i].sendsRejectedPre + reports[i].sendsRejectedRequote;

      string marker = " ";
      if(hasPrev && reports[i].netPnLPoints < prevNet) marker = "v";

      Print(StringFormat("%s%-11s %6d %6d %6d %8.4f %s %10.2f %8I64d %8.2f %11.2f %10.2f",
                         marker,
                         reports[i].levelName,
                         reports[i].tradesClosed,
                         reports[i].wins,
                         reports[i].losses,
                         reports[i].winRate,
                         pf,
                         reports[i].netPnLPoints,
                         totalRej,
                         reports[i].slippageTotalPoints,
                         reports[i].netPnLCurrency,
                         reports[i].totalCommission));
      prevNet = reports[i].netPnLPoints;
      hasPrev = true;
   }
   Print("=========================================================================================");
   Print("Marcador 'v' = degradacao de netPnL vs nivel anterior");
   Print("=========================================================================================");
}

#endif // MKS_ULTIMATE_STRESSLAB_CMKSSTRESSLABREPORT_MQH
