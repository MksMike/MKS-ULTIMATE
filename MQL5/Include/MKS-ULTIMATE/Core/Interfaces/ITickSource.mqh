//+------------------------------------------------------------------+
//| @file           : ITickSource.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Interface ITickSource — produtor único de ticks;
//|                   mesma fonte para backtest e live.
//| @depends_on     : MksTick (Core/Types/Tick.mqh)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/ITickSource.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_ITICKSOURCE_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_ITICKSOURCE_MQH

#include <MKS-ULTIMATE/Core/Types/Tick.mqh>

//--- Interface: fonte sequencial de ticks (ADR-004).
//--- Invariante 2 do V5-POSTMORTEM: um único produtor de feed.
class ITickSource
{
public:
   virtual ~ITickSource() {}

   // Preenche 'tick' com o próximo tick em ordem de seq.
   // false quando não há tick disponível (fim do feed em
   // backtest; nenhum tick novo em live).
   virtual bool Next(MksTick &tick) = 0;

   // timeMsc do último tick entregue por Next() bem-sucedido.
   // 0 antes do primeiro tick. Substituiu o getter não-virtual antigo
   // do CMksFileTickSource para que CMksReplayClock possa receber
   // qualquer ITickSource (single-file, multi-file, futuras).
   // Live tick sources (futuras) podem retornar timeMsc do último
   // SymbolInfoTick observado, ou TimeCurrent()*1000.
   virtual long LastTickTimeMsc() const = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_ITICKSOURCE_MQH
