//+------------------------------------------------------------------+
//| @file           : Test_MksMt5BrokerLive.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Experts / MKS-ULTIMATE
//| @responsibility : EA mínimo para validação empírica do CMksMt5Broker
//|                   em conta demo. Atacha, faz Init, envia 1 ordem
//|                   pequena, fecha. Sem estratégia — apenas plumbing.
//|                   APENAS PARA DEMO — usa AutoTrading.
//| @depends_on     : Core/Broker/CMksMt5Broker.mqh,
//|                   Core/Symbol/CMksMt5Symbol.mqh,
//|                   Core/Account/CMksMt5Account.mqh,
//|                   Core/Types/OrderRequest.mqh, Core/Types/ExecutionResult.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Experts/MKS-ULTIMATE/Test_MksMt5BrokerLive.mq5
//+------------------------------------------------------------------+
#property strict

#include <MKS-ULTIMATE/Core/Broker/CMksMt5Broker.mqh>
#include <MKS-ULTIMATE/Core/Symbol/CMksMt5Symbol.mqh>
#include <MKS-ULTIMATE/Core/Account/CMksMt5Account.mqh>
#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

input double InpLots             = 0.01;       // lote mínimo para teste
input int    InpMagic            = 13371337;   // magic number
input int    InpDeviation        = 10;         // pontos
input bool   InpRunOnceOnAttach  = true;       // executa 1 ciclo Send+Close ao atachar
input bool   InpCloseImmediately = true;       // fecha logo após o Send

CMksMt5Symbol  *g_sym  = NULL;
CMksMt5Account *g_acc  = NULL;
CMksMt5Broker  *g_brk  = NULL;
bool g_shouldRun = false;
bool g_testDone  = false;

void PrintResult(const string &label, const MksExecutionResult &r)
{
   PrintFormat("%s: status=%d positionId=%I64u dealId=%I64u",
               label, (int)r.status, r.positionId, r.dealId);
   PrintFormat("  fillPrice=%.5f requestedPrice=%.5f filledLots=%.2f",
               r.fillPrice, r.requestedPrice, r.filledLots);
   PrintFormat("  commission=%.4f swap=%.4f attempts=%d retcode=%d",
               r.commission, r.swap, r.attempts, r.brokerRetcode);
   PrintFormat("  slippage=%.5f execTimeMsc=%I64d",
               r.Slippage(), r.execTimeMsc);
}

void Cleanup()
{
   if(g_brk != NULL) { delete g_brk; g_brk = NULL; }
   if(g_acc != NULL) { delete g_acc; g_acc = NULL; }
   if(g_sym != NULL) { delete g_sym; g_sym = NULL; }
}

int OnInit()
{
   // Guarda contra conta real. Este EA executa Send/Close reais —
   // anexar em conta real por engano abre posição com capital de verdade.
   // O magic 13371337 já é defensivo; o guard fecha a porta de vez.
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL)
   {
      Print("Test_MksMt5BrokerLive: recusado em conta REAL. Use DEMO ou CONTEST.");
      return INIT_FAILED;
   }

   g_sym = new CMksMt5Symbol(_Symbol);
   g_acc = new CMksMt5Account();
   g_brk = new CMksMt5Broker(g_sym, g_acc, InpMagic, InpDeviation);

   MksError err;
   if(!g_brk.Init(err))
   {
      PrintFormat("Init falhou: %s", err.ToString());
      Cleanup();
      return INIT_FAILED;
   }

   Print("");
   Print("=== Test_MksMt5BrokerLive ===");
   PrintFormat("symbol=%s account=%I64d broker=\"%s\"",
               g_sym.Name(), g_acc.Login(), g_acc.Company());
   PrintFormat("digits=%d point=%.5f tickSize=%.5f tickValue=%.5f",
               g_sym.Digits(), g_sym.Point(),
               g_sym.TickSize(), g_sym.TickValue());
   PrintFormat("volumeMin=%.2f volumeMax=%.2f volumeStep=%.2f",
               g_sym.VolumeMin(), g_sym.VolumeMax(), g_sym.VolumeStep());
   PrintFormat("balance=%.2f equity=%.2f freeMargin=%.2f leverage=%d",
               g_acc.Balance(), g_acc.Equity(),
               g_acc.FreeMargin(), g_acc.Leverage());
   PrintFormat("filling effective: %d (FOK=0 IOC=1 RETURN=2)",
               (int)g_brk.EffectiveFilling());
   PrintFormat("marginMode: %d (NETTING=0 EXCHANGE=1 HEDGING=2)",
               (int)g_brk.MarginMode());

   if(InpRunOnceOnAttach)
   {
      g_shouldRun = true;
      Print("InpRunOnceOnAttach=true — ciclo Send+Close será executado no próximo OnTick.");
   }
   else
   {
      Print("InpRunOnceOnAttach=false — EA permanece quieto. Mude o input para disparar.");
   }
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(!g_shouldRun || g_testDone || g_brk == NULL) return;
   g_testDone = true; // marca antes pra não repetir

   MksOrderRequest req;
   req.side     = MKS_ORDER_BUY;
   req.lots     = InpLots;
   req.slPoints = 0.0; // sem SL/TP nesse teste mínimo
   req.tpPoints = 0.0;
   req.comment  = "mt5-broker-test";

   Print("");
   PrintFormat("--- Send BUY %.2f lots ---", InpLots);
   MksExecutionResult r = g_brk.Send(req);
   PrintResult("Send", r);

   if(r.status != MKS_EXEC_FILLED)
   {
      Print("Send NÃO preencheu — abortando Close.");
      return;
   }

   if(!InpCloseImmediately)
   {
      PrintFormat("Posição %I64u aberta. InpCloseImmediately=false — fechar manualmente.",
                  r.positionId);
      return;
   }

   Print("");
   PrintFormat("--- Close position %I64u ---", r.positionId);
   MksExecutionResult rc = g_brk.Close(r.positionId, InpLots);
   PrintResult("Close", rc);

   Print("");
   Print("=== teste concluído ===");
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(g_brk != NULL)
      g_brk.OnTradeTransactionEvent(trans, request, result);
}

void OnDeinit(const int reason)
{
   PrintFormat("Test_MksMt5BrokerLive: deinit reason=%d", reason);
   Cleanup();
}
//+------------------------------------------------------------------+
