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
// Tempo da bar (ADR-023, timeline híbrida real+bump — substitui ADR-020
// regra 4): cada brick fechado usa o MAIOR entre o tempo real do tick
// disparador (closeTimeMsc/1000) e o último slot+60s. Em mercado calmo,
// o tempo real vence → granularidade de segundos aparece naturalmente.
// Em mercado frenético (vários bricks/min), o bump +60s garante slot
// único (CustomRatesUpdate sobrescreve bars com mesmo time), MAS limitado a
// realTime+maxFutureDriftSecs (ADR-023-A): sem esse teto o bump sustentado
// dispara a timeline pro futuro sem limite — o que AMPLIFICA, mas não causa
// sozinho, o bug de plataforma do MT5.
//
// ATENÇÃO (correção 2026-05-30): CustomRatesUpdate tem um bug conhecido e
// não-corrigido que corrompe o container do Custom Symbol na VIRADA DE DIA do
// server (independe de barra-no-futuro; apaga a série inteira; retorna -1 com
// GetLastError()=0). O cap reduz o gatilho auto-infligido (futuro), mas NÃO
// elimina esse bug. A correção estrutural é aposentar o CS do caminho de
// visualização (renko brick-native em indicador/objetos — ADR em decisão).
class CMksCustomSymbolSink : public IRenkoSink
{
public:
   string   csName;
   datetime nextBarTime;
   datetime lastBarTime;   // ADR-028: slot atribuído ao último brick fechado (âncora p/ marcadores)
   double   brickSizePts;  // ADR-022 regra 8: tamanho VISUAL full do brick
   int      barsPushed;
   int      updateFailures;
   bool     showWicks;     // ADR-022 regra 3: false (default) = caixinhas;
                           // true = wicks de excursão preservados no CS
   long     maxFutureDriftSecs; // ADR-023-A: teto de adianto da timeline em
                                // segundos (default 6h). Trava o runaway do
                                // bump — ver ComputeBrickTime.

   CMksCustomSymbolSink()
   {
      csName             = "";
      nextBarTime        = 0;
      lastBarTime        = 0;
      brickSizePts       = 0.0;
      barsPushed         = 0;
      updateFailures     = 0;
      showWicks          = false;
      maxFutureDriftSecs = 6 * 3600; // 6h: folga ampla sob o teto do MT5
                                     // (~fim-de-amanhã, ≥24h no pior caso)
   }

   // ADR-023-A: timeline híbrida COM teto de adianto. Sem teto, num mercado
   // que fecha bricks mais rápido que 1/min de forma sustentada, o ramo do
   // bump (brickTime = nextBarTime) empurra a barra +60s por brick enquanto o
   // relógio real anda segundos — a timeline do CS dispara pro futuro sem
   // limite até o MT5 recusar CustomRatesUpdate (retorna -1, GetLastError()=0)
   // e os bricks "somem". O teto trava brickTime em realTime+maxFutureDriftSecs:
   // ao bater o teto, bricks do mesmo minuto se sobrescrevem (degradação visual
   // só nas rajadas extremas), reduzindo o gatilho AUTO-INFLIGIDO (não o bug de
   // virada-de-dia do MT5, ver header) e se autocurando quando o mercado
   // desacelera (realTime volta a vencer, adianto → ~0).
   // Em mercado calmo realTime > nextBarTime → brickTime = realTime ≤ teto →
   // sem efeito (comportamento ADR-023 original preservado). Pura → testável
   // sem Custom Symbol (Test_CMksCustomSymbolSink_Timeline).
   static datetime ComputeBrickTime(long closeTimeMsc, datetime nextBarTime,
                                    long maxFutureDriftSecs)
   {
      datetime realTime  = (datetime)(closeTimeMsc / 1000);
      datetime brickTime = (realTime > nextBarTime) ? realTime : nextBarTime;
      datetime cap       = (datetime)((long)realTime + maxFutureDriftSecs);
      if(brickTime > cap) brickTime = cap;
      return brickTime;
   }

   void OnBrickClose(const MksBrick &brick) override
   {
      if(StringLen(csName) == 0) return;
      MqlRates rates[1];

      // ADR-023 + ADR-023-A: timeline híbrida real+bump COM teto de drift.
      // closeTimeMsc é o tempo real do tick disparador. Usa real se maior que o
      // último slot+60s; senão bump — nunca além de realTime+maxFutureDriftSecs
      // (ComputeBrickTime). Guarda o slot escolhido em lastBarTime — o painter
      // (ADR-028) ancora marcadores nesse tempo.
      datetime brickTime = ComputeBrickTime(brick.closeTimeMsc, nextBarTime,
                                            maxFutureDriftSecs);
      rates[0].time = brickTime;

      // ADR-022 regra 8: bricks no CS têm tamanho VISUAL full (=
      // brickSizePts), independentemente de PO/PRO. close visual =
      // open ± size na direção. Em classic (ADR-026, Producer atual),
      // visualClose == brick.close real — sem divergência preço/desenho.
      // Em median legado (PO>0), reproduz visual Median Renko V5 com
      // sobreposição = PO*size. Fallback: se brickSizePts não foi
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
      lastBarTime = brickTime;                                  // ADR-028: âncora p/ marcadores
      nextBarTime = (datetime)((long)brickTime + 60);           // próximo slot mínimo
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
