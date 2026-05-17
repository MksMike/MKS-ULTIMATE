//+------------------------------------------------------------------+
//| @file           : ILogger.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Interface ILogger — contrato de logging com
//|                   níveis; formato definido pela implementação.
//| @depends_on     : Nenhuma (tipos nativos)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/ILogger.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_ILOGGER_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_ILOGGER_MQH

enum ENUM_MKS_LOG_LEVEL
{
   MKS_LOG_TRACE,
   MKS_LOG_DEBUG,
   MKS_LOG_INFO,
   MKS_LOG_WARN,
   MKS_LOG_ERROR
};

//--- Interface: registro de log (ADR-004). O formato do log
//--- (ADR-007) é decidido pela implementação, não pelo contrato.
class ILogger
{
public:
   virtual ~ILogger() {}

   virtual void Log(ENUM_MKS_LOG_LEVEL level, const string &message) = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_ILOGGER_MQH
