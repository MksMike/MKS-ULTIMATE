//+------------------------------------------------------------------+
//| @file           : ILogger.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Interfaces
//| @responsibility : Interface ILogger — contrato de logging estruturado
//|                   com schema fixo (ts, level, module, msg + contextos).
//|                   Formato concreto JSON-line definido pela ADR-007;
//|                   serialização e destino são responsabilidade da
//|                   implementação concreta (CMksLogger).
//| @depends_on     : Nenhuma (tipos nativos)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Interfaces/ILogger.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_INTERFACES_ILOGGER_MQH
#define MKS_ULTIMATE_CORE_INTERFACES_ILOGGER_MQH

// Níveis de log. META é especial: usado uma vez por sessão para
// proveniência do arquivo (broker, account, symbol, version) na
// primeira linha do .log (ADR-007 §6). Não passa pelo filtro de
// nível mínimo — sempre escreve.
enum ENUM_MKS_LOG_LEVEL
{
   MKS_LOG_META  = 0,
   MKS_LOG_TRACE = 1,
   MKS_LOG_DEBUG = 2,
   MKS_LOG_INFO  = 3,
   MKS_LOG_WARN  = 4,
   MKS_LOG_ERROR = 5
};

//--- Interface: registro de log estruturado (ADR-004, ADR-007).
//--- Schema mínimo obrigatório de cada linha:
//---   ts (ISO 8601 UTC ms), level, module, msg + ctxJson opcional.
//--- ctxJson é fragmento JSON de pares chave-valor SEM chaves externas;
//--- exemplo: "\"brickIdx\":123,\"direction\":\"BULL\""
//--- Vazio se não há contexto.
//--- Caller é responsável por escapar valores no ctxJson — a
//--- implementação escapa apenas module e msg.
class ILogger
{
public:
   virtual ~ILogger() {}

   virtual void Log(ENUM_MKS_LOG_LEVEL level,
                    const string &module,
                    const string &msg,
                    const string &ctxJson) = 0;
};

#endif // MKS_ULTIMATE_CORE_INTERFACES_ILOGGER_MQH
