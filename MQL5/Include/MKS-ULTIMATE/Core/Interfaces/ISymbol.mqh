//+------------------------------------------------------------------+
//| @file           : ISymbol.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Interface ISymbol — ficha técnica do instrumento.
//|                   Propriedades estáticas/semi-estáticas consultadas
//|                   por código de lógica em vez da API SymbolInfo*
//|                   global (Protocolo 9, ADR-016).
//| @depends_on     : Nenhuma (tipos nativos do MQL5)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_ISYMBOL_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_ISYMBOL_MQH

// Contrato de "ficha técnica do instrumento" — propriedades que código
// de lógica precisa saber sobre um símbolo (digits, tick size, volume,
// stops, filling, moedas). Não inclui dados de tick ao vivo — esses
// vêm de ITickSource via MksTick.
//
// FillingMode retorna ENUM_SYMBOL_FILLING_MODE como bitmask int — a
// API MQL5 documenta SYMBOL_FILLING_MODE como bitmask de FOK/IOC/RETURN.
// Caller faz teste de bit (& SYMBOL_FILLING_FOK), não comparação por
// igualdade.
class ISymbol
{
public:
   virtual ~ISymbol() {}

   //--- Identidade ---
   virtual string Name()           const = 0;
   virtual int    Digits()         const = 0;
   virtual double Point()          const = 0;

   //--- Tick ---
   virtual double TickSize()       const = 0;
   virtual double TickValue()      const = 0;

   //--- Volume ---
   virtual double ContractSize()   const = 0;
   virtual double VolumeMin()      const = 0;
   virtual double VolumeMax()      const = 0;
   virtual double VolumeStep()     const = 0;

   //--- Trade ---
   virtual int    StopsLevel()     const = 0; // pontos
   virtual int    FreezeLevel()    const = 0; // pontos
   virtual int    FillingMode()    const = 0; // bitmask ENUM_SYMBOL_FILLING_MODE

   //--- Currencies ---
   virtual string BaseCurrency()   const = 0;
   virtual string ProfitCurrency() const = 0;
   virtual string MarginCurrency() const = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_ISYMBOL_MQH
