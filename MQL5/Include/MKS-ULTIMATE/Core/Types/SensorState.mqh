//+------------------------------------------------------------------+
//| @file           : SensorState.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Types
//| @responsibility : Enum ENUM_MKS_SENSOR_STATE com os 4 estados que
//|                   um ISensor pode emitir (ADR-025) + helpers de
//|                   conversão para string (log/debug).
//| @depends_on     : Nenhuma (autocontido)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Types/SensorState.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TYPES_SENSORSTATE_MQH
#define MKS_ULTIMATE_CORE_TYPES_SENSORSTATE_MQH

//--- Estados que um ISensor pode emitir (ADR-025 §2).
enum ENUM_MKS_SENSOR_STATE
{
   MKS_SENSOR_INACTIVE = 0,  // sensor não disparou — sem sinal ativo
   MKS_SENSOR_FORMING  = 1,  // sinal aparecendo, ainda não confirmado
   MKS_SENSOR_ACTIVE   = 2,  // sinal confirmado, EA pode consumir
   MKS_SENSOR_BREAKING = 3   // sinal quebrando, EA deve sair
};

//--- Converte estado para string (log/debug).
string MksSensorStateToString(ENUM_MKS_SENSOR_STATE state)
{
   switch(state)
   {
      case MKS_SENSOR_INACTIVE: return "INACTIVE";
      case MKS_SENSOR_FORMING:  return "FORMING";
      case MKS_SENSOR_ACTIVE:   return "ACTIVE";
      case MKS_SENSOR_BREAKING: return "BREAKING";
   }
   return "UNKNOWN";
}

#endif // MKS_ULTIMATE_CORE_TYPES_SENSORSTATE_MQH
