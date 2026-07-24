//+------------------------------------------------------------------+
//| @file           : CMksCustomSymbolSink.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Output
//| @responsibility : Sink que empurra cada brick fechado como uma
//|                   barra no Custom Symbol via CustomRatesUpdate
//|                   (ADR-020). Bricks fechados são caixinhas sem
//|                   wicks (regra 3). A cada tick, OnBrickForming
//|                   atualiza a bar parcial no slot nextBarTime — com
//|                   wicks (excursão), close = mid atual (ADR-021). Ao
//|                   fechar, OnBrickClose grava em ComputeBrickTime: em
//|                   mercado frenético (bump vence) sobrescreve o slot
//|                   da parcial; em mercado calmo (realTime vence) grava
//|                   num slot À FRENTE e a parcial fica órfã no slot
//|                   anterior (aceito, ADR-023 r.3 — o .mksbk é a verdade).
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
// NOTA (revisado 2026-05-30): a "morte" do CS na virada de dia era
// majoritariamente AUTO-INFLIGIDA, não um bug incondicional do MT5 (o V5 usava
// o mesmo CustomRatesUpdate e sobrevivia à meia-noite). Causas, todas no
// composition root (EnsureCustomSymbolReady):
//   1) CS criado SEM sessões 24/7 → o MT5 recusa CustomRatesUpdate na virada
//      de dia do server (-1, GetLastError()=0). Causa-raiz. O V5 setava
//      sessões 24/7 nos 7 dias.
//   2) spec-setters (DIGITS/POINT/TICK/...) reaplicados a cada OnInit apagavam
//      a série a cada re-anexação do EA. Agora só rodam na criação.
// O cap abaixo fica como HIGIENE (limita a deriva do bump), não como cura. Há
// uma fragilidade de plataforma reportada no fórum, mas CONDICIONAL a vários
// CS cruzando a virada (não reproduzida com um único CS). OnBrickClose tem
// recovery (re-seleciona + 1 retry) espelhando o HealthCheck do V5.
class CMksCustomSymbolSink : public IRenkoSink
{
public:
   string   csName;
   datetime nextBarTime;
   datetime lastBarTime;   // ADR-028: slot atribuído ao último brick fechado (âncora p/ marcadores)
   double   brickSizePts;  // ADR-022 regra 8: tamanho VISUAL full do brick
   int      barsPushed;
   int      updateFailures;      // agregado (close + forming) — consumido pelo relatório do EA
   int      formingUpdateFailures; // só forming: gate do log da 1ª falha (E7.2, sinal precoce)
   int      formingSuppressed;  // barras parciais puladas por nextBarTime<=0 (guard time=0, 2026-07-22)
   int      invalidTimeDropped; // bricks descartados do desenho por brickTime<=0 (defesa)
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
      formingUpdateFailures = 0;
      formingSuppressed  = 0;
      invalidTimeDropped = 0;
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

   // Uma barra do CS exige slot de tempo VÁLIDO (> 0). Escrever em time <= 0
   // grava a barra em 1970.01.01 e CORROMPE o container do CS (sintoma
   // observado 2026-07-22: HistoryBase "invalid container (1970.01.01)").
   // Guarda pura na fronteira de escrita — o .mksbk segue com o brick intacto
   // (ADR-020: o CS é só desenho, a estratégia não o lê). Testável sem CS.
   static bool IsRenderableBarTime(datetime t) { return t > (datetime)0; }

   // Bordas do CORPO da caixinha renko (high/low SEM pavio de excursão) =
   // extremos entre open e close visual. Usadas por OnBrickClose E
   // OnBrickForming quando showWicks=false (ADR-020/022 regra 3). Puras,
   // testáveis sem CS.
   static double BoxBodyHigh(double open, double close) { return MathMax(open, close); }
   static double BoxBodyLow (double open, double close) { return MathMin(open, close); }

   // Transição pura da timeline após UMA tentativa de gravar a barra do brick
   // fechado (finding cs-recovery-advances-timeline-on-fail). SUCESSO (ok) →
   // ancora lastBarTime no slot gravado e prepara o próximo slot mínimo (+60s).
   // FALHA (!ok) → NÃO mexe em lastBarTime NEM em nextBarTime: ambos mantêm o
   // slot da última barra REAL. Assim o painter (ADR-028) nunca ancora em slot
   // vazio e a timeline não deriva pro futuro alimentando o runaway do bump que
   // matava o CS. Não congela nada: no próximo brick de mercado calmo/recuperado
   // o realTime volta a vencer em ComputeBrickTime. Testável sem Custom Symbol.
   static void ApplyCloseTimeline(bool ok, datetime brickTime,
                                  datetime &lastBarTime, datetime &nextBarTime)
   {
      if(!ok) return;                                 // falha: mantém os dois slots
      lastBarTime = brickTime;
      nextBarTime = (datetime)((long)brickTime + 60); // próximo slot mínimo
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
      // Defesa: brickTime<=0 só ocorre se closeTimeMsc<=0 (tick sem tempo) —
      // NÃO acontece com tick real (ComputeBrickTime(>0) > 0, provado em
      // Test_FirstBrickFromEpochZero). Se ocorrer, gravar corromperia o CS:
      // descarta do DESENHO (o brick segue no .mksbk) e falha alto, SEM avançar
      // lastBarTime/nextBarTime a partir de um tempo inválido.
      if(!IsRenderableBarTime(brickTime))
      {
         invalidTimeDropped++;
         PrintFormat("[CS] brick descartado do desenho: brickTime<=0 "
                     "(closeTimeMsc=%I64d). Brick intacto no .mksbk. cs=%s",
                     brick.closeTimeMsc, csName);
         return;
      }
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
         rates[0].high = BoxBodyHigh(brick.open, visualClose);
         rates[0].low  = BoxBodyLow (brick.open, visualClose);
      }
      rates[0].tick_volume = brick.thresholdsCrossed; // não é volume real
      rates[0].spread      = 0;
      rates[0].real_volume = 0;
      int n = CustomRatesUpdate(csName, rates);
      if(n < 0)
      {
         // Recovery (espelha o HealthCheck do V5): a série pode ter sido
         // recusada/corrompida. Re-seleciona o símbolo e tenta UMA vez. A
         // causa-raiz (sessões 24/7) é tratada na criação do CS; isto é
         // defesa-em-profundidade, não substituto.
         if(SymbolSelect(csName, true))
            n = CustomRatesUpdate(csName, rates);
      }
      bool ok = (n >= 0);
      if(ok)
         barsPushed++;
      else
      {
         updateFailures++;
         if(updateFailures == 1 || (updateFailures % 500) == 0)
            PrintFormat("CS UPDATE FAIL (#%d): lastErr=%d",
                        updateFailures, GetLastError());
      }
      // E7.2 / cs-recovery-advances-timeline-on-fail: lastBarTime E nextBarTime
      // só avançam no SUCESSO. Em falha, ambos mantêm o slot da última barra
      // real — o painter (ADR-028) não ancora em slot vazio e a timeline não
      // deriva pro futuro (o runaway do bump). Ver ApplyCloseTimeline.
      ApplyCloseTimeline(ok, brickTime, lastBarTime, nextBarTime);
   }

   // ADR-021: a cada tick, atualiza a bar PARCIAL no slot atual de
   // nextBarTime (a próxima bar, ainda não confirmada por brick fechado).
   // RESPEITA showWicks (igual ao OnBrickClose): com wicks o parcial mostra a
   // excursão; sem, caixinha limpa. Ao fechar, OnBrickClose grava em
   // ComputeBrickTime: em mercado frenético (bump) sobrescreve ESTE slot com a
   // bar definitiva; em mercado calmo (realTime vence) grava num slot à frente e
   // esta parcial fica órfã aqui (aceito, ADR-023 r.3).
   void OnBrickForming(const MksFormingBrick &fb) override
   {
      if(!fb.hasData) return;
      if(StringLen(csName) == 0) return;
      // Guard (2026-07-22): sem brick fechado, nextBarTime==0 → o slot seria
      // 1970.01.01, que CORROMPE o container do CS. Pula a barra parcial e
      // FALHA ALTO (uma vez): se persistir, o builder não fechou nenhum brick
      // (ex.: K subdimensionado p/ brick pequeno) — sintoma exposto, não
      // silêncio. Sem afetar o caminho normal (nextBarTime>0 após o 1º brick).
      if(!IsRenderableBarTime(nextBarTime))
      {
         formingSuppressed++;
         if(formingSuppressed == 1)
            PrintFormat("[CS] forming suprimido: nextBarTime<=0 (nenhum brick "
                        "fechou ainda). Barra parcial NAO gravada p/ evitar "
                        "time=0. cs=%s", csName);
         return;
      }
      MqlRates rates[1];
      rates[0].time        = nextBarTime;
      rates[0].open        = fb.open;
      rates[0].close       = fb.currentMid;    // preço atual
      // BUG 2026-07-22: o forming ignorava showWicks e escrevia SEMPRE
      // fb.high/fb.low → o CS mostrava pavios mesmo com wicks=false (na barra
      // viva E nas parciais órfãs de slot). Agora respeita showWicks igual ao
      // OnBrickClose. O .mksbk preserva a excursão real de qualquer forma.
      if(showWicks)
      {
         rates[0].high = fb.high;
         rates[0].low  = fb.low;
      }
      else
      {
         rates[0].high = BoxBodyHigh(fb.open, fb.currentMid);
         rates[0].low  = BoxBodyLow (fb.open, fb.currentMid);
      }
      rates[0].tick_volume = 0;
      rates[0].spread      = 0;
      rates[0].real_volume = 0;
      int n = CustomRatesUpdate(csName, rates);
      if(n < 0)
      {
         updateFailures++;
         formingUpdateFailures++;
         // E7.2 / cs-forming-no-recovery-asymmetry: o forming roda a cada tick e
         // é o sinal MAIS PRECOCE da morte do CS. Loga só a 1ª falha (contador
         // dedicado, independente do close) — captura o instante exato da recusa
         // do container sem poluir o log a cada tick.
         if(formingUpdateFailures == 1)
            PrintFormat("[CS] FORMING UPDATE FAIL (1a): lastErr=%d slot=%I64d cs=%s",
                        GetLastError(), (long)nextBarTime, csName);
      }
   }
};

#endif // MKS_ULTIMATE_CORE_OUTPUT_CMKSCUSTOMSYMBOLSINK_MQH
