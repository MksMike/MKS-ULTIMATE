//+------------------------------------------------------------------+
//| @file           : Test_CMksColorReversalStrategy.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE / Tests
//| @responsibility : Testes da estratégia minimalista da Fase 9 —
//|                   reversão de cor pura. Cobre: primeiro brick (sem
//|                   ação), brick repetido (sem ação), flip BULL→BEAR
//|                   (close+open SELL), flip BEAR→BULL (close+open
//|                   BUY), múltiplos flips em sequência, auto-detach
//|                   via IPositionBook, métricas agregadas.
//| @depends_on     : Strategy/CMksColorReversalStrategy.mqh,
//|                   Core/Trade/CMksFixedLotSizer.mqh,
//|                   Core/Testing/Asserts.mqh,
//|                   Core/Testing/Mocks/CMksRecordingBroker.mqh,
//|                   Core/Testing/Mocks/CMksFakeSymbol.mqh,
//|                   Core/Testing/Mocks/CMksFakePositionBook.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/Tests/Test_CMksColorReversalStrategy.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Strategy/CMksColorReversalStrategy.mqh>
#include <MKS-ULTIMATE/Core/Trade/CMksFixedLotSizer.mqh>
#include <MKS-ULTIMATE/Core/Testing/Asserts.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksRecordingBroker.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksFakePositionBook.mqh>
#include <MKS-ULTIMATE/Core/Testing/Mocks/CMksRecordingVisualizer.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>

#define CR_TOL 1e-9
const double SL_POINTS = 100.0;
const double FIXED_LOTS = 0.10;
const long   MAGIC = 527001;

//+------------------------------------------------------------------+
//| Helpers                                                            |
//+------------------------------------------------------------------+
MksBrick MakeBrick(ENUM_MKS_BRICK_DIR dir, double open, double close,
                   ulong triggerTickId = 1, long closeTimeMsc = 1000)
{
   MksBrick b;
   b.direction         = dir;
   b.open              = open;
   b.close             = close;
   b.high              = MathMax(open, close);
   b.low               = MathMin(open, close);
   b.triggerPrice      = close;
   b.triggerTickId     = triggerTickId;
   b.closeTimeMsc      = closeTimeMsc;
   b.thresholdsCrossed = 1;
   return b;
}

//==================================================================
// Primeiro brick — sem flip, sem ação
//==================================================================

void Test_CR_FirstBrickRegistersDirectionNoAction()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), FIXED_LOTS);
   CMksColorReversalStrategy strat(GetPointer(br), GetPointer(sizer),
                                    GetPointer(sym), SL_POINTS, MAGIC);

   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2000.0, 2003.0));

   MKS_ASSERT_EQ_INT(0, br.SendCount(), "primeiro brick não dispara Send");
   MKS_ASSERT_EQ_INT(0, br.CloseCount(), "primeiro brick não dispara Close");
   MKS_ASSERT_TRUE(strat.HasLastBrick(), "lastBrickDir registrado");
   MKS_ASSERT_EQ_INT((int)MKS_BRICK_BULL, (int)strat.LastBrickDir(), "dir = BULL");
   MKS_ASSERT_FALSE(strat.HasOpenPosition(), "sem posição aberta");
}

//==================================================================
// Brick repetido — sem flip, sem ação
//==================================================================

void Test_CR_SameDirectionTwiceNoAction()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), FIXED_LOTS);
   CMksColorReversalStrategy strat(GetPointer(br), GetPointer(sizer),
                                    GetPointer(sym), SL_POINTS, MAGIC);

   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2000.0, 2003.0));
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2003.0, 2006.0));
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2006.0, 2009.0));

   MKS_ASSERT_EQ_INT(0, br.SendCount(), "0 Sends em sequência BULL-BULL-BULL");
   MKS_ASSERT_EQ_INT(0, br.CloseCount(), "0 Closes em sequência sem flip");
   MKS_ASSERT_EQ_LONG(0, strat.Metrics().flipsDetected, "0 flips registrados");
   MKS_ASSERT_EQ_LONG(3, strat.Metrics().bricksSeen, "3 bricks vistos");
}

//==================================================================
// Flip BULL → BEAR: sem posição prévia, abre SELL
//==================================================================

void Test_CR_FlipBullToBearOpensSellNoPriorPosition()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), FIXED_LOTS);
   CMksColorReversalStrategy strat(GetPointer(br), GetPointer(sizer),
                                    GetPointer(sym), SL_POINTS, MAGIC);

   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2000.0, 2003.0)); // primeiro
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2003.0, 2000.0)); // flip

   MKS_ASSERT_EQ_INT(1, br.SendCount(), "1 Send no flip");
   MKS_ASSERT_EQ_INT(0, br.CloseCount(), "0 Close (sem posição prévia)");
   MKS_ASSERT_TRUE(strat.HasOpenPosition(), "posição aberta");
   MKS_ASSERT_EQ_INT((int)MKS_ORDER_SELL, (int)strat.CurrentSide(), "side SELL");
   MKS_ASSERT_EQ_LONG(1, strat.Metrics().flipsDetected, "1 flip");
   MKS_ASSERT_EQ_LONG(1, strat.Metrics().sendsFilled, "1 send filled");
}

//==================================================================
// Flip BEAR → BULL: sem posição prévia, abre BUY
//==================================================================

void Test_CR_FlipBearToBullOpensBuyNoPriorPosition()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), FIXED_LOTS);
   CMksColorReversalStrategy strat(GetPointer(br), GetPointer(sizer),
                                    GetPointer(sym), SL_POINTS, MAGIC);

   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2000.0, 1997.0));
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 1997.0, 2000.0));

   MKS_ASSERT_EQ_INT(1, br.SendCount(), "1 Send no flip");
   MKS_ASSERT_EQ_INT((int)MKS_ORDER_BUY, (int)strat.CurrentSide(), "side BUY");
}

//==================================================================
// Sequência de flips: BULL → BEAR → BULL → BEAR (close+open a cada flip)
//==================================================================

void Test_CR_MultipleFlipsCloseAndReverse()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), FIXED_LOTS);
   CMksColorReversalStrategy strat(GetPointer(br), GetPointer(sizer),
                                    GetPointer(sym), SL_POINTS, MAGIC);

   // BULL (primeiro, sem ação)
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2000.0, 2003.0));
   // Flip → SELL (1 Send, 0 Close)
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2003.0, 2000.0));
   // Flip → BUY (1 Send, 1 Close)
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2000.0, 2003.0));
   // Flip → SELL (1 Send, 1 Close)
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2003.0, 2000.0));

   MKS_ASSERT_EQ_INT(3, br.SendCount(), "3 Sends (1 por flip)");
   MKS_ASSERT_EQ_INT(2, br.CloseCount(), "2 Closes (a partir do 2º flip)");
   MKS_ASSERT_EQ_LONG(3, strat.Metrics().flipsDetected, "3 flips");
   MKS_ASSERT_EQ_LONG(3, strat.Metrics().sendsFilled, "3 sends filled");
   MKS_ASSERT_EQ_LONG(2, strat.Metrics().closesFilled, "2 closes filled");
   MKS_ASSERT_TRUE(strat.HasOpenPosition(), "posição aberta no final");
   MKS_ASSERT_EQ_INT((int)MKS_ORDER_SELL, (int)strat.CurrentSide(), "última = SELL");
}

//==================================================================
// SL e comment montados corretamente no request
//==================================================================

void Test_CR_OrderRequestFieldsCorrect()
{
   // RecordingBroker não expõe o último request, mas conseguimos
   // verificar lots e side via state da strategy + fill price padrão.
   CMksRecordingBroker br;
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), FIXED_LOTS);
   CMksColorReversalStrategy strat(GetPointer(br), GetPointer(sizer),
                                    GetPointer(sym), SL_POINTS, MAGIC);

   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2000.0, 2003.0));
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2003.0, 2000.0));

   MKS_ASSERT_NEAR_DOUBLE(FIXED_LOTS, strat.CurrentLots(), CR_TOL,
                          "lots = FIXED_LOTS via sizer");
   MKS_ASSERT_NEAR_DOUBLE(SL_POINTS, strat.SlPoints(), CR_TOL,
                          "slPoints preservado");
   MKS_ASSERT_EQ_LONG(MAGIC, strat.Magic(), "magic preservado");
}

//==================================================================
// Auto-detach via IPositionBook — posição "atual" sumiu do broker
//==================================================================

void Test_CR_AutoDetachWhenBookSaysClosed()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym;
   CMksFakePositionBook book;
   CMksFixedLotSizer sizer(GetPointer(sym), FIXED_LOTS);
   CMksColorReversalStrategy strat(GetPointer(br), GetPointer(sizer),
                                    GetPointer(sym), SL_POINTS, MAGIC,
                                    NULL, GetPointer(book));

   // Abre BUY via flip BEAR→BULL.
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2000.0, 1997.0));
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 1997.0, 2000.0));
   MKS_ASSERT_TRUE(strat.HasOpenPosition(), "posição aberta");
   ulong pid = strat.CurrentPositionId();

   // Simula auto-close externo (SL hit do broker, manual close, etc).
   book.MarkClosed(pid);

   // Próximo brick (sem flip) — só atualiza dir. Auto-detach acontece
   // no início do OnBrickClose.
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2000.0, 2003.0));

   MKS_ASSERT_FALSE(strat.HasOpenPosition(), "auto-detach zerou estado");
   MKS_ASSERT_EQ_LONG(1, strat.Metrics().autoDetected, "métrica autoDetected++");
   MKS_ASSERT_EQ_INT(0, br.CloseCount(),
      "Close NÃO foi chamado (broker já fechou — strategy só limpou state)");
}

//==================================================================
// Auto-detach + flip subsequente: deve abrir nova posição limpa
//==================================================================

void Test_CR_AutoDetachThenFlipOpensCleanly()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym;
   CMksFakePositionBook book;
   CMksFixedLotSizer sizer(GetPointer(sym), FIXED_LOTS);
   CMksColorReversalStrategy strat(GetPointer(br), GetPointer(sizer),
                                    GetPointer(sym), SL_POINTS, MAGIC,
                                    NULL, GetPointer(book));

   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2000.0, 1997.0));
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 1997.0, 2000.0));
   ulong pid = strat.CurrentPositionId();
   book.MarkClosed(pid);

   // Flip BULL → BEAR. Auto-detach roda primeiro (zera state), depois
   // o flip processa "close (no-op, já zerado) + open SELL".
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2000.0, 1997.0));

   MKS_ASSERT_TRUE(strat.HasOpenPosition(), "nova posição aberta");
   MKS_ASSERT_EQ_INT((int)MKS_ORDER_SELL, (int)strat.CurrentSide(), "side SELL");
   MKS_ASSERT_EQ_INT(2, br.SendCount(), "2 Sends totais (BUY + SELL)");
   MKS_ASSERT_EQ_INT(0, br.CloseCount(),
      "0 Closes — auto-detach evitou Close fantasma sobre PID já fechado");
}

//==================================================================
// Sem book — comportamento legacy (sem auto-detach)
//==================================================================

void Test_CR_NoBookPreservesLegacyBehavior()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), FIXED_LOTS);
   // Sem book.
   CMksColorReversalStrategy strat(GetPointer(br), GetPointer(sizer),
                                    GetPointer(sym), SL_POINTS, MAGIC);

   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2000.0, 1997.0));
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 1997.0, 2000.0));
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2000.0, 1997.0));

   // Sem book, autoDetected nunca incrementa.
   MKS_ASSERT_EQ_LONG(0, strat.Metrics().autoDetected, "sem book = sem auto-detect");
   // Mas o flip processa normalmente: Close + Send.
   MKS_ASSERT_EQ_INT(2, br.SendCount(), "2 Sends (2 flips)");
   MKS_ASSERT_EQ_INT(1, br.CloseCount(), "1 Close (2º flip fechou primeira posição)");
}

//==================================================================
// Send rejeitada: state não fica corrompido
//==================================================================

void Test_CR_SendRejectedNoStateCorruption()
{
   CMksRecordingBroker br;
   br.SetNextSendStatus(MKS_EXEC_REJECTED);
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), FIXED_LOTS);
   CMksColorReversalStrategy strat(GetPointer(br), GetPointer(sizer),
                                    GetPointer(sym), SL_POINTS, MAGIC);

   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2000.0, 2003.0));
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2003.0, 2000.0));

   MKS_ASSERT_EQ_LONG(1, strat.Metrics().sendsRejected, "1 rejeição contada");
   MKS_ASSERT_EQ_LONG(0, strat.Metrics().sendsFilled, "0 filled");
   MKS_ASSERT_FALSE(strat.HasOpenPosition(), "sem posição (rejeitada)");
   MKS_ASSERT_EQ_INT((int)MKS_BRICK_BEAR, (int)strat.LastBrickDir(),
                     "lastBrickDir avança mesmo com rejeição");
}

//==================================================================
// ResetMetrics zera contadores
//==================================================================

void Test_CR_ResetMetricsZeroesCounters()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym;
   CMksFixedLotSizer sizer(GetPointer(sym), FIXED_LOTS);
   CMksColorReversalStrategy strat(GetPointer(br), GetPointer(sizer),
                                    GetPointer(sym), SL_POINTS, MAGIC);

   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2000.0, 2003.0));
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2003.0, 2000.0));
   MKS_ASSERT_EQ_LONG(2, strat.Metrics().bricksSeen, "2 bricks antes");

   strat.ResetMetrics();
   MKS_ASSERT_EQ_LONG(0, strat.Metrics().bricksSeen, "zerado");
   MKS_ASSERT_EQ_LONG(0, strat.Metrics().flipsDetected, "flips zerado");
   MKS_ASSERT_EQ_LONG(0, strat.Metrics().sendsFilled, "sends zerado");
}

//==================================================================
// Visualização (ADR-028) — eventos disparam + paridade ON vs OFF
//==================================================================

void Test_CR_VisualizerReceivesEntryAndExit()
{
   CMksRecordingBroker br;
   CMksFakeSymbol sym;
   CMksRecordingVisualizer viz;
   CMksFixedLotSizer sizer(GetPointer(sym), FIXED_LOTS);
   CMksColorReversalStrategy strat(GetPointer(br), GetPointer(sizer),
                                    GetPointer(sym), SL_POINTS, MAGIC,
                                    NULL, NULL, GetPointer(viz));

   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2000.0, 2003.0, 10, 1000));
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BEAR, 2003.0, 2000.0, 20, 2000)); // flip → entry SELL
   strat.OnBrickClose(MakeBrick(MKS_BRICK_BULL, 2000.0, 2003.0, 30, 3000)); // flip → exit + entry BUY

   MKS_ASSERT_EQ_INT(2, viz.EntryCount(), "2 entradas marcadas (2 flips)");
   MKS_ASSERT_EQ_INT(1, viz.ExitCount(),  "1 saída marcada (fechou 1a no 2o flip)");
   MKS_ASSERT_EQ_INT((int)MKS_ORDER_BUY, (int)viz.LastEntrySide(), "última entrada BUY");
   MKS_ASSERT_EQ_LONG(3000, viz.LastEntryTimeMsc(), "entry ancorada no closeTimeMsc do brick");
}

void Test_CR_VisualizerParityOnVsOff()
{
   // Mesma sequência de bricks com visualizer NULL e com mock. As
   // DECISÕES (Sends/Closes no broker) devem ser idênticas — visualização
   // é observador passivo (ADR-028 §7). Prova de paridade em nível de teste.
   ENUM_MKS_BRICK_DIR dirs[] = {MKS_BRICK_BULL, MKS_BRICK_BEAR, MKS_BRICK_BULL,
                                MKS_BRICK_BEAR, MKS_BRICK_BEAR, MKS_BRICK_BULL};
   double opens[]  = {2000, 2003, 2000, 2003, 2000, 1997};
   double closes[] = {2003, 2000, 2003, 2000, 1997, 2000};

   // Run A — sem visualizer
   CMksRecordingBroker brA;
   CMksFakeSymbol symA;
   CMksFixedLotSizer sizerA(GetPointer(symA), FIXED_LOTS);
   CMksColorReversalStrategy stratA(GetPointer(brA), GetPointer(sizerA),
                                     GetPointer(symA), SL_POINTS, MAGIC);

   // Run B — com visualizer
   CMksRecordingBroker brB;
   CMksFakeSymbol symB;
   CMksRecordingVisualizer viz;
   CMksFixedLotSizer sizerB(GetPointer(symB), FIXED_LOTS);
   CMksColorReversalStrategy stratB(GetPointer(brB), GetPointer(sizerB),
                                     GetPointer(symB), SL_POINTS, MAGIC,
                                     NULL, NULL, GetPointer(viz));

   for(int i = 0; i < 6; i++)
   {
      MksBrick b = MakeBrick(dirs[i], opens[i], closes[i], (ulong)(i + 1), (i + 1) * 1000);
      stratA.OnBrickClose(b);
      stratB.OnBrickClose(b);
   }

   // Decisões idênticas: mesmo nº de Sends e Closes no broker.
   MKS_ASSERT_EQ_INT(brA.SendCount(), brB.SendCount(),
                     "Sends idênticos com/sem visualizer");
   MKS_ASSERT_EQ_INT(brA.CloseCount(), brB.CloseCount(),
                     "Closes idênticos com/sem visualizer");
   // Estado final idêntico.
   MKS_ASSERT_EQ_INT((int)stratA.CurrentSide(), (int)stratB.CurrentSide(),
                     "side final idêntico");
   MKS_ASSERT_EQ_LONG(stratA.Metrics().flipsDetected, stratB.Metrics().flipsDetected,
                      "flips idênticos");
   MKS_ASSERT_EQ_LONG(stratA.Metrics().sendsFilled, stratB.Metrics().sendsFilled,
                      "sendsFilled idênticos");
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== Test_CMksColorReversalStrategy ===");

   MKS_RUN(Test_CR_FirstBrickRegistersDirectionNoAction);
   MKS_RUN(Test_CR_SameDirectionTwiceNoAction);
   MKS_RUN(Test_CR_FlipBullToBearOpensSellNoPriorPosition);
   MKS_RUN(Test_CR_FlipBearToBullOpensBuyNoPriorPosition);
   MKS_RUN(Test_CR_MultipleFlipsCloseAndReverse);
   MKS_RUN(Test_CR_OrderRequestFieldsCorrect);

   MKS_RUN(Test_CR_AutoDetachWhenBookSaysClosed);
   MKS_RUN(Test_CR_AutoDetachThenFlipOpensCleanly);
   MKS_RUN(Test_CR_NoBookPreservesLegacyBehavior);

   MKS_RUN(Test_CR_SendRejectedNoStateCorruption);
   MKS_RUN(Test_CR_ResetMetricsZeroesCounters);

   MKS_RUN(Test_CR_VisualizerReceivesEntryAndExit);
   MKS_RUN(Test_CR_VisualizerParityOnVsOff);

   g_mksTestRunner.Summary();
}
//+------------------------------------------------------------------+
