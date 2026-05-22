//+------------------------------------------------------------------+
//| @file           : CMksCustomSymbolSink.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Output
//| @responsibility : Sink que empurra cada brick fechado como uma
//|                   barra no Custom Symbol via CustomRatesUpdate
//|                   (ADR-020). Bricks fechados são caixinhas sem
//|                   wicks (regra 3). A cada tick, OnBrickForming
//|                   também atualiza a bar parcial no slot do próximo
//|                   brick — com wicks (excursão), close = mid atual
//|                   (ADR-021). Quando o brick fecha, OnBrickClose
//|                   sobrescreve esse slot com a bar definitiva.
//| @depends_on     : Core/Interfaces/IRenkoSink.mqh, Core/Types/Brick.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Output/CMksCustomSymbolSink.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_OUTPUT_CMKSCUSTOMSYMBOLSINK_MQH
#define MKS_ULTIMATE_CORE_OUTPUT_CMKSCUSTOMSYMBOLSINK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>

// Empurra bricks como bars OHLC para um Custom Symbol existente. O
// CS precisa ter sido criado e selecionado em Market Watch ANTES de
// este sink ser anexado ao builder — esta classe não cria nem
// configura o CS (responsabilidade do composition root no EA).
//
// Tempo da bar (ADR-020 regra 4): índice ordenador monotônico, não
// tempo real do brick. CustomRatesUpdate sobrescreve bars com mesmo
// time, então cada brick precisa de um time único; +60s por brick
// resolve estruturalmente.
class CMksCustomSymbolSink : public IRenkoSink
{
public:
   string   csName;
   datetime nextBarTime;
   double   brickSizePts;  // ADR-022 regra 8: tamanho VISUAL full do brick
   int      barsPushed;
   int      updateFailures;
   bool     showWicks;     // ADR-022 regra 3: false (default) = caixinhas;
                           // true = wicks de excursão preservados no CS

   CMksCustomSymbolSink()
   {
      csName         = "";
      nextBarTime    = 0;
      brickSizePts   = 0.0;
      barsPushed     = 0;
      updateFailures = 0;
      showWicks      = false;
   }

   void OnBrickClose(const MksBrick &brick) override
   {
      if(StringLen(csName) == 0) return;
      MqlRates rates[1];
      rates[0].time = nextBarTime;

      // ADR-022 regra 8: bricks no CS têm tamanho VISUAL full (=
      // brickSizePts), independentemente de PO/PRO. close visual =
      // open ± size na direção. Reproduz visual Median Renko V5
      // (sobreposição = PO*size). Fallback: se brickSizePts não foi
      // configurado (0), usa close matemático (modo legado).
      double visualClose = brick.close;
      if(brickSizePts > 0.0)
         visualClose = brick.open + (brick.IsBull() ? brickSizePts : -brickSizePts);

      rates[0].open  = brick.open;
      rates[0].close = visualClose;

      // ADR-020 regra 3 + ADR-022 regra 3: caixinhas sem wicks por
      // default; showWicks=true propaga excursão intra-brick.
      // .mksbk sempre preserva brick.high/brick.low.
      if(showWicks)
      {
         rates[0].high = brick.high;
         rates[0].low  = brick.low;
      }
      else
      {
         rates[0].high = MathMax(brick.open, visualClose);
         rates[0].low  = MathMin(brick.open, visualClose);
      }
      rates[0].tick_volume = brick.thresholdsCrossed; // não é volume real
      rates[0].spread      = 0;
      rates[0].real_volume = 0;
      int n = CustomRatesUpdate(csName, rates);
      if(n < 0)
      {
         updateFailures++;
         PrintFormat("CS UPDATE FAIL: lastErr=%d", GetLastError());
      }
      else
      {
         barsPushed++;
      }
      nextBarTime = (datetime)((long)nextBarTime + 60);
   }

   // ADR-021: a cada tick, atualiza a bar PARCIAL no slot atual de
   // nextBarTime (a próxima bar, ainda não confirmada por brick fechado).
   // Empurra COM wicks — excursão durante a formação é informação. Quando
   // o brick fechar, OnBrickClose vai sobrescrever este mesmo slot com a
   // bar definitiva sem wicks (ADR-020 regra 3) e incrementar nextBarTime.
   void OnBrickForming(const MksFormingBrick &fb) override
   {
      if(!fb.hasData) return;
      if(StringLen(csName) == 0) return;
      MqlRates rates[1];
      rates[0].time        = nextBarTime;
      rates[0].open        = fb.open;
      rates[0].high        = fb.high;          // wicks de excursão
      rates[0].low         = fb.low;
      rates[0].close       = fb.currentMid;    // preço atual
      rates[0].tick_volume = 0;
      rates[0].spread      = 0;
      rates[0].real_volume = 0;
      int n = CustomRatesUpdate(csName, rates);
      if(n < 0)
      {
         updateFailures++;
         // Sem log a cada tick — emit failures vai pro contador.
      }
   }
};

#endif // MKS_ULTIMATE_CORE_OUTPUT_CMKSCUSTOMSYMBOLSINK_MQH
