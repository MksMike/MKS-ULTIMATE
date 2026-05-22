//+------------------------------------------------------------------+
//| @file           : CMksCustomSymbolSink.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Output
//| @responsibility : Sink que empurra cada brick fechado como uma
//|                   barra no Custom Symbol via CustomRatesUpdate.
//|                   Timestamp M1 fictício monotônico (ADR-020 regra 4).
//|                   ATENÇÃO: esta versão preserva wicks (extração
//|                   sem mudança comportamental). ADR-020 regra 3
//|                   é aplicada em commit subsequente.
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
   int      barsPushed;
   int      updateFailures;

   CMksCustomSymbolSink()
   {
      csName         = "";
      nextBarTime    = 0;
      barsPushed     = 0;
      updateFailures = 0;
   }

   void OnBrickClose(const MksBrick &brick) override
   {
      if(StringLen(csName) == 0) return;
      MqlRates rates[1];
      rates[0].time        = nextBarTime;
      rates[0].open        = brick.open;
      rates[0].high        = brick.high;
      rates[0].low         = brick.low;
      rates[0].close       = brick.close;
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
};

#endif // MKS_ULTIMATE_CORE_OUTPUT_CMKSCUSTOMSYMBOLSINK_MQH
