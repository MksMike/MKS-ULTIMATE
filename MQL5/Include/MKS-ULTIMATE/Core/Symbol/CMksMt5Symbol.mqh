//+------------------------------------------------------------------+
//| @file           : CMksMt5Symbol.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Symbol
//| @responsibility : Implementação de ISymbol que delega para a API
//|                   SymbolInfo* nativa do MQL5. ADR-016.
//| @depends_on     : Core/Interfaces/ISymbol.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Symbol/CMksMt5Symbol.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_SYMBOL_CMKSMT5SYMBOL_MQH
#define MKS_ULTIMATE_CORE_SYMBOL_CMKSMT5SYMBOL_MQH

#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>

// Implementação concreta de ISymbol para o MT5 real. Construtor recebe
// o nome do símbolo; cada método consulta SymbolInfoString/Integer/
// Double da API global. Get-on-demand — sem cache interno.
//
// Uso típico no composition root de um EA:
//   CMksMt5Symbol sym(_Symbol);
//   logger.Info("Producer", "digits", StringFormat("\"d\":%d", sym.Digits()));
class CMksMt5Symbol : public ISymbol
{
private:
   string m_name;

public:
   CMksMt5Symbol(const string symbolName)
   {
      m_name = symbolName;
   }

   string Name() const override { return m_name; }

   int    Digits() const override
   {
      return (int)SymbolInfoInteger(m_name, SYMBOL_DIGITS);
   }

   double Point() const override
   {
      return SymbolInfoDouble(m_name, SYMBOL_POINT);
   }

   double TickSize() const override
   {
      return SymbolInfoDouble(m_name, SYMBOL_TRADE_TICK_SIZE);
   }

   double TickValue() const override
   {
      return SymbolInfoDouble(m_name, SYMBOL_TRADE_TICK_VALUE);
   }

   double ContractSize() const override
   {
      return SymbolInfoDouble(m_name, SYMBOL_TRADE_CONTRACT_SIZE);
   }

   double VolumeMin() const override
   {
      return SymbolInfoDouble(m_name, SYMBOL_VOLUME_MIN);
   }

   double VolumeMax() const override
   {
      return SymbolInfoDouble(m_name, SYMBOL_VOLUME_MAX);
   }

   double VolumeStep() const override
   {
      return SymbolInfoDouble(m_name, SYMBOL_VOLUME_STEP);
   }

   int StopsLevel() const override
   {
      return (int)SymbolInfoInteger(m_name, SYMBOL_TRADE_STOPS_LEVEL);
   }

   int FreezeLevel() const override
   {
      return (int)SymbolInfoInteger(m_name, SYMBOL_TRADE_FREEZE_LEVEL);
   }

   int FillingMode() const override
   {
      return (int)SymbolInfoInteger(m_name, SYMBOL_FILLING_MODE);
   }

   string BaseCurrency() const override
   {
      return SymbolInfoString(m_name, SYMBOL_CURRENCY_BASE);
   }

   string ProfitCurrency() const override
   {
      return SymbolInfoString(m_name, SYMBOL_CURRENCY_PROFIT);
   }

   string MarginCurrency() const override
   {
      return SymbolInfoString(m_name, SYMBOL_CURRENCY_MARGIN);
   }
};

#endif // MKS_ULTIMATE_CORE_SYMBOL_CMKSMT5SYMBOL_MQH
