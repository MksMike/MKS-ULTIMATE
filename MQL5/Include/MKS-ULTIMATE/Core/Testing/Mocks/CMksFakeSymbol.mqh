//+------------------------------------------------------------------+
//| @file           : CMksFakeSymbol.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Testing / Mocks
//| @responsibility : Mock de ISymbol — ficha técnica do instrumento
//|                   com valores configuráveis em runtime, default
//|                   genéricos. Substitui CFakeSymbol inline nos
//|                   testes existentes (Test_CMksSimulatedBroker).
//|                   Ver ADR-005.
//| @depends_on     : Core/Interfaces/ISymbol.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Testing/Mocks/CMksFakeSymbol.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKESYMBOL_MQH
#define MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKESYMBOL_MQH

#include <MKS-ULTIMATE/Core/Interfaces/ISymbol.mqh>

class CMksFakeSymbol : public ISymbol
{
private:
   string m_name;
   int    m_digits;
   double m_point;
   double m_tickSize;
   double m_tickValue;
   double m_contractSize;
   double m_volumeMin;
   double m_volumeMax;
   double m_volumeStep;
   int    m_stopsLevel;
   int    m_freezeLevel;
   int    m_fillingMode;
   string m_baseCurrency;
   string m_profitCurrency;
   string m_marginCurrency;

public:
   //--- Defaults compatíveis com o CFakeSymbol inline de
   //--- Test_CMksSimulatedBroker (digits=2, point=0.01, etc.).
   //--- Tests que precisem de outros valores chamam os setters.
   CMksFakeSymbol()
   {
      m_name           = "FAKE";
      m_digits         = 2;
      m_point          = 0.01;
      m_tickSize       = 0.01;
      m_tickValue      = 1.0;
      m_contractSize   = 100.0;
      m_volumeMin      = 0.01;
      m_volumeMax      = 100.0;
      m_volumeStep     = 0.01;
      m_stopsLevel     = 0;
      m_freezeLevel    = 0;
      m_fillingMode    = 1;
      m_baseCurrency   = "FAK";
      m_profitCurrency = "USD";
      m_marginCurrency = "USD";
   }

   //--- ISymbol overrides ----------------------------------------+
   string Name()           const override { return m_name; }
   int    Digits()         const override { return m_digits; }
   double Point()          const override { return m_point; }
   double TickSize()       const override { return m_tickSize; }
   double TickValue()      const override { return m_tickValue; }
   double ContractSize()   const override { return m_contractSize; }
   double VolumeMin()      const override { return m_volumeMin; }
   double VolumeMax()      const override { return m_volumeMax; }
   double VolumeStep()     const override { return m_volumeStep; }
   int    StopsLevel()     const override { return m_stopsLevel; }
   int    FreezeLevel()    const override { return m_freezeLevel; }
   int    FillingMode()    const override { return m_fillingMode; }
   string BaseCurrency()   const override { return m_baseCurrency; }
   string ProfitCurrency() const override { return m_profitCurrency; }
   string MarginCurrency() const override { return m_marginCurrency; }

   //--- Setters fluentes (retornam ponteiro para encadeamento opcional)
   void SetName(const string v)           { m_name = v; }
   void SetDigits(int v)                  { m_digits = v; }
   void SetPoint(double v)                { m_point = v; }
   void SetTickSize(double v)             { m_tickSize = v; }
   void SetTickValue(double v)            { m_tickValue = v; }
   void SetContractSize(double v)         { m_contractSize = v; }
   void SetVolumeMin(double v)            { m_volumeMin = v; }
   void SetVolumeMax(double v)            { m_volumeMax = v; }
   void SetVolumeStep(double v)           { m_volumeStep = v; }
   void SetStopsLevel(int v)              { m_stopsLevel = v; }
   void SetFreezeLevel(int v)             { m_freezeLevel = v; }
   void SetFillingMode(int v)             { m_fillingMode = v; }
   void SetBaseCurrency(const string v)   { m_baseCurrency = v; }
   void SetProfitCurrency(const string v) { m_profitCurrency = v; }
   void SetMarginCurrency(const string v) { m_marginCurrency = v; }
};

#endif // MKS_ULTIMATE_CORE_TESTING_MOCKS_FAKESYMBOL_MQH
