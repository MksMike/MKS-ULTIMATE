//+------------------------------------------------------------------+
//| @file           : ValidateRenkoBuilder.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE
//| @responsibility : Validação informal do CMksRenkoBuilder —
//|                   sequências determinísticas de ticks, impressão
//|                   de cada brick e erro para conferência manual.
//| @depends_on     : Core/RenkoBuilder/CMksRenkoBuilder.mqh,
//|                   Core/RenkoBuilder/CMksFixedBrickSizer.mqh
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/ValidateRenkoBuilder.mq5
//+------------------------------------------------------------------+
#property script_show_inputs

#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksRenkoBuilder.mqh>
#include <MKS-ULTIMATE/Core/RenkoBuilder/CMksFixedBrickSizer.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/FormingBrick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>

//+------------------------------------------------------------------+
//| Sink de inspeção: imprime cada brick com todos os campos chave.  |
//+------------------------------------------------------------------+
class CInspectorSink : public IRenkoSink
{
public:
   void OnBrickClose(const MksBrick &brick) override
   {
      PrintFormat("BRICK %s open=%.2f close=%.2f high=%.2f low=%.2f M=%d trigger=%.2f tickId=%I64u overshoot=%.2f",
                  (brick.IsBull() ? "BULL" : "BEAR"),
                  brick.open, brick.close, brick.high, brick.low,
                  brick.thresholdsCrossed,
                  brick.triggerPrice, brick.triggerTickId, brick.Overshoot());
   }
};

//+------------------------------------------------------------------+
//| Helpers de construção de tick                                    |
//+------------------------------------------------------------------+
MksTick MakeTick(double bid, double ask, ulong seq, long timeMsc)
{
   MksTick t;
   t.bid = bid;
   t.ask = ask;
   t.seq = seq;
   t.timeMsc = timeMsc;
   t.last = 0.0;
   t.volume = 0;
   return t;
}

// Atalho: tick com spread fixo de 0.10 centrado em 'mid'.
MksTick MakeTickByMid(double mid, ulong seq, long timeMsc)
{
   return MakeTick(mid - 0.05, mid + 0.05, seq, timeMsc);
}

//+------------------------------------------------------------------+
//| Roda um cenário: builder novo, processa array, imprime resultados |
//+------------------------------------------------------------------+
void RunScenario(const string title, MksTick &ticks[])
{
   Print("");
   Print("=== ", title, " ===");

   CInspectorSink sink;
   CMksFixedBrickSizer sizer(100.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder builder(geom, GetPointer(sizer), GetPointer(sink));

   int n = ArraySize(ticks);
   for(int i = 0; i < n; i++)
   {
      MksError err;
      bool ok = builder.IngestTick(ticks[i], err);
      if(!ok)
         PrintFormat("  ERR tick #%d: %s", i, err.ToString());
   }
}

//+------------------------------------------------------------------+
//| Cenário de overshoot: 1º tick inicializa, 2º dispara brick e o   |
//| forming brick é inspecionado via GetFormingBrick().              |
//+------------------------------------------------------------------+
void RunOvershootScenario(const string title, double initMid, double triggerMid)
{
   Print("");
   Print("=== ", title, " ===");

   CInspectorSink sink;
   CMksFixedBrickSizer sizer(100.0);
   MksRenkoGeometry geom = MksGeometryMedian();
   CMksRenkoBuilder builder(geom, GetPointer(sizer), GetPointer(sink));

   MksError err;
   MksTick t1 = MakeTickByMid(initMid, 1, 1000);
   builder.IngestTick(t1, err);

   MksTick t2 = MakeTickByMid(triggerMid, 2, 2000);
   builder.IngestTick(t2, err);

   MksFormingBrick fb = builder.GetFormingBrick();
   PrintFormat("FORMING open=%.2f high=%.2f low=%.2f direction=%s hasData=%s",
               fb.open, fb.high, fb.low,
               (fb.direction == MKS_BRICK_BULL ? "BULL" : "BEAR"),
               (fb.hasData ? "true" : "false"));
}

//+------------------------------------------------------------------+
void OnStart()
{
   //----- Cenário 1: single-threshold continuação BULL
   MksTick s1[4];
   s1[0] = MakeTickByMid(2000.0, 1, 1000);  // init (sem brick)
   s1[1] = MakeTickByMid(2050.0, 2, 2000);  // BULL #1, close=2050
   s1[2] = MakeTickByMid(2100.0, 3, 3000);  // BULL #2, close=2100
   s1[3] = MakeTickByMid(2150.0, 4, 4000);  // BULL #3, close=2150
   RunScenario("CENÁRIO 1 — single-threshold continuação BULL (3 bricks)", s1);

   //----- Cenário 2: reversão BULL → BEAR
   MksTick s2[5];
   s2[0] = MakeTickByMid(2000.0, 1, 1000);  // init
   s2[1] = MakeTickByMid(2050.0, 2, 2000);  // BULL #1
   s2[2] = MakeTickByMid(2100.0, 3, 3000);  // BULL #2
   s2[3] = MakeTickByMid(2050.0, 4, 4000);  // REVERSÃO → BEAR #1, close=2050
   s2[4] = MakeTickByMid(2000.0, 5, 5000);  // BEAR continuação, close=2000
   RunScenario("CENÁRIO 2 — reversão BULL → BEAR", s2);

   //----- Cenário 3: multi-threshold (M=3 num único tick)
   MksTick s3[2];
   s3[0] = MakeTickByMid(2000.0, 1, 1000);  // init
   s3[1] = MakeTickByMid(2150.0, 2, 2000);  // salta 150 → BULL único M=3, close=2150
   RunScenario("CENÁRIO 3 — multi-threshold (M=3 num único tick)", s3);

   //----- Cenário 4: guarda de tick inválido (103 isolado, 104 stream corrupt)
   MksTick s4[14];
   s4[0]  = MakeTickByMid(2000.0, 1, 1000);                 // init (válido)
   s4[1]  = MakeTick(2010.0, 2009.0, 2, 2000);              // INVÁLIDO (ask < bid) → 103
   s4[2]  = MakeTickByMid(2050.0, 3, 3000);                 // válido → reset contador, BULL #1
   // T4..T13: 10 ticks inválidos consecutivos. 9 fogem como 103; o 10º
   // (índice 12) atinge L=10 e fira 104, marcando stream corrupt.
   for(int i = 0; i < 10; i++)
      s4[3+i] = MakeTick(2000.0 + i, 1999.0 + i, (ulong)(4+i), (long)(4000+i*1000));
   s4[13] = MakeTickByMid(2100.0, 14, 14000);               // válido pós-corrupt → ainda 104
   RunScenario("CENÁRIO 4 — guarda de tick inválido (103 isolado, 104 stream corrupt)", s4);

   //----- Cenário 5: overshoot single-threshold (mid salta 68 sobre threshold em 50)
   // Esperado: BRICK BULL open=2000 close=2050 M=1 trigger=2068 overshoot=18
   //           FORMING open=2050 high=2068 low=2050 direction=BULL hasData=true
   RunOvershootScenario("CENÁRIO 5 — overshoot single-threshold (esperado: brick close=2050 overshoot=18; forming open=2050 high=2068 low=2050)",
                        2000.0, 2068.0);

   //----- Cenário 6: overshoot multi-threshold (mid salta 168 → M=3, overshoot além do 3º threshold)
   // Esperado: BRICK BULL open=2000 close=2150 M=3 trigger=2168 overshoot=18
   //           FORMING open=2150 high=2168 low=2150 direction=BULL hasData=true
   RunOvershootScenario("CENÁRIO 6 — overshoot multi-threshold (esperado: brick close=2150 M=3 overshoot=18; forming open=2150 high=2168 low=2150)",
                        2000.0, 2168.0);

   Print("");
   Print("=== validação concluída ===");
}
