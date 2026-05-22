//+------------------------------------------------------------------+
//| Logger.mqh                                                   |
//| MKS Framework - V5.0 Research Engine                             |
//| Descricao: Sistema de logging com rotacao, filtros e buffer   |
//| Instalacao: MQL5/Include/MKS-V5.0/Core/                        |
//| Build: V5.0 (2026-04-07)                                         |
//+------------------------------------------------------------------+

#ifndef __LOGGER_MQH__
#define __LOGGER_MQH__

//=====================================================================
// SEÇÃO 1: ENUMERAÇÕES E CONSTANTES
//=====================================================================

// 1.1 - Níveis de severidade do log
enum ENUM_LOG_LEVEL
{
   LOG_LEVEL_TRACE = 0,     // Rastreamento detalhado (desenvolvimento)
   LOG_LEVEL_DEBUG = 1,     // Informações de debug (desenvolvimento)
   LOG_LEVEL_INFO = 2,      // Informações gerais (produção)
   LOG_LEVEL_WARN = 3,      // Avisos (produção)
   LOG_LEVEL_ERROR = 4,     // Erros recuperáveis (produção)
   LOG_LEVEL_FATAL = 5      // Erros fatais não recuperáveis (produção)
};

// 1.2 - Constantes de configuração
#define MAX_LOG_FILE_SIZE_KB 5120    // 5MB - quando atingir, rotaciona
#define MAX_LOG_BACKUPS 3             // Mantém últimos 3 arquivos

//=====================================================================
// SEÇÃO 2: ESTRUTURA DE ESTATÍSTICAS
//=====================================================================

// 2.1 - Estatísticas de logging (útil para debug)
struct LogStats
{
   int traceCount;
   int debugCount;
   int infoCount;
   int warnCount;
   int errorCount;
   int fatalCount;
   
   LogStats()
   {
      traceCount = 0;
      debugCount = 0;
      infoCount = 0;
      warnCount = 0;
      errorCount = 0;
      fatalCount = 0;
   }
   
   int GetTotal()
   {
      return traceCount + debugCount + infoCount + warnCount + errorCount + fatalCount;
   }
   
   void Reset()
   {
      traceCount = 0;
      debugCount = 0;
      infoCount = 0;
      warnCount = 0;
      errorCount = 0;
      fatalCount = 0;
   }
};

//=====================================================================
// SEÇÃO 3: CLASSE LOGGER ESTÁTICA
//=====================================================================

// 3.1 - Logger centralizado do framework (singleton estático)
class CLogger
{
private:
   //--- Configuração global
   static ENUM_LOG_LEVEL m_minLevel;        // Nível mínimo para logar
   static bool           m_writeToFile;     // Se true, logs >= WARN vão para arquivo
   static string         m_logFile;         // Nome do arquivo de log
   static bool           m_showTimestamp;   // Se true, adiciona timestamp
   static bool           m_showComponent;   // Se true, mostra componente
   static bool           m_colorOutput;     // Se true, usa cores no terminal (futura feature)
   
   //--- Performance tracking
   static bool           m_trackPerf;       // Se true, rastreia tempo entre logs
   static uint           m_lastLogTimeMs;   // Último timestamp de log
   
   //--- Estatísticas
   static LogStats       m_stats;           // Contadores por nível
   static bool           m_statsEnabled;    // Se true, mantém estatísticas
   
   //--- Filtragem por componente
   static string         m_filteredComponentsStr; // String com componentes separados por "|"
   static bool           m_useComponentFilter;     // Se true, filtra por componente
   
   //--- Rotação de logs
   static bool           m_autoRotate;      // Se true, rotaciona arquivo grande
   static datetime       m_lastRotateCheck; // Última verificação de rotação
   
   //=================================================================
   // 3.2 - MÉTODOS PRIVADOS AUXILIARES
   //=================================================================
   
   // Converte nível para string
   static string LevelToString(ENUM_LOG_LEVEL level)
   {
      switch(level)
      {
         case LOG_LEVEL_TRACE: return "TRACE";
         case LOG_LEVEL_DEBUG: return "DEBUG";
         case LOG_LEVEL_INFO:  return "INFO ";
         case LOG_LEVEL_WARN:  return "WARN ";
         case LOG_LEVEL_ERROR: return "ERROR";
         case LOG_LEVEL_FATAL: return "FATAL";
         default:              return "?????";
      }
   }
   
   // Verifica se componente está na lista de filtros
   static bool IsComponentFiltered(string component)
   {
      if(!m_useComponentFilter)
         return false;
      
      if(m_filteredComponentsStr == "")
         return false;
      
      // Verifica se componente está na string (formato: "|Component1|Component2|")
      string searchStr = "|" + component + "|";
      return StringFind("|" + m_filteredComponentsStr + "|", searchStr) >= 0;
   }
   
   // Atualiza estatísticas
   static void UpdateStats(ENUM_LOG_LEVEL level)
   {
      if(!m_statsEnabled)
         return;
      
      switch(level)
      {
         case LOG_LEVEL_TRACE: m_stats.traceCount++; break;
         case LOG_LEVEL_DEBUG: m_stats.debugCount++; break;
         case LOG_LEVEL_INFO:  m_stats.infoCount++; break;
         case LOG_LEVEL_WARN:  m_stats.warnCount++; break;
         case LOG_LEVEL_ERROR: m_stats.errorCount++; break;
         case LOG_LEVEL_FATAL: m_stats.fatalCount++; break;
      }
   }
   
   // Verifica e rotaciona log se necessário
   static void CheckRotation()
   {
      if(!m_autoRotate)
         return;
      
      // Verifica apenas a cada 5 minutos
      datetime now = TimeCurrent();
      if(now - m_lastRotateCheck < 300)
         return;
      
      m_lastRotateCheck = now;
      
      // Verifica tamanho do arquivo
      if(!FileIsExist(m_logFile))
         return;
      
      // Cast explícito para evitar warning de conversão
      ulong fileSize = (ulong)FileGetInteger(m_logFile, FILE_SIZE);
      
      // Se menor que limite, não rotaciona
      if(fileSize < (ulong)MAX_LOG_FILE_SIZE_KB * 1024ULL)  // 1024ULL = ulong literal
         return;
      
      // Rotaciona arquivos
      RotateLogFiles();
   }
   
   // Rotaciona arquivos de log (mantém últimos N backups)
   static void RotateLogFiles()
   {
      Print(StringFormat("[Logger] Rotacionando logs - arquivo atual: %llu KB", (ulong)FileGetInteger(m_logFile, FILE_SIZE) / 1024ULL));
      
      // Remove backup mais antigo se existir
      string oldestBackup = m_logFile + "." + IntegerToString(MAX_LOG_BACKUPS);
      if(FileIsExist(oldestBackup))
         FileDelete(oldestBackup);
      
      // Renomeia backups existentes (shift)
      for(int i = MAX_LOG_BACKUPS - 1; i >= 1; i--)
      {
         string currentBackup = m_logFile + "." + IntegerToString(i);
         string nextBackup = m_logFile + "." + IntegerToString(i + 1);
         
         if(FileIsExist(currentBackup))
            FileMove(currentBackup, 0, nextBackup, 0);
      }
      
      // Move arquivo atual para .1
      string firstBackup = m_logFile + ".1";
      FileMove(m_logFile, 0, firstBackup, 0);
      
      Print("[Logger] Rotação completa - novo arquivo criado");
   }
   
   // Escreve linha no arquivo de log
   static void WriteToFile(string message)
   {
      // Verifica rotação antes de escrever
      CheckRotation();
      
      // Tenta abrir arquivo em modo append
      int handle = FileOpen(m_logFile, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI);
      
      if(handle == INVALID_HANDLE)
      {
         // Tenta criar novo arquivo
         handle = FileOpen(m_logFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
         
         if(handle == INVALID_HANDLE)
         {
            Print(StringFormat("❌ [Logger] Falha ao criar arquivo: %s (erro: %d)", m_logFile, GetLastError()));
            return;
         }
      }
      else
      {
         // Vai para o final do arquivo
         FileSeek(handle, 0, SEEK_END);
      }
      
      // Escreve linha + newline
      FileWriteString(handle, message + "\n");
      
      // Fecha arquivo
      FileClose(handle);
   }

public:
   //=================================================================
   // 3.3 - INICIALIZAÇÃO E CONFIGURAÇÃO
   //=================================================================
   
   // Inicializa logger com configurações padrão
   static void Init(ENUM_LOG_LEVEL minLevel = LOG_LEVEL_INFO, 
                    bool writeToFile = true,
                    string logFileName = "MKS_Framework.log")
   {
      m_minLevel = minLevel;
      m_writeToFile = writeToFile;
      m_logFile = logFileName;
      m_showTimestamp = true;
      m_showComponent = true;
      m_colorOutput = false;
      m_trackPerf = false;
      m_lastLogTimeMs = 0;
      m_statsEnabled = true;
      m_useComponentFilter = false;
      m_autoRotate = true;
      m_lastRotateCheck = 0;
      
      // Reseta estatísticas
      m_stats.Reset();
      
      // Limpa filtros
      m_filteredComponentsStr = "";
      
      // Log de inicialização
      Info("Logger", StringFormat("v3.0 Inicializado | MinLevel=%s | File=%s | Rotate=%s",
                                  LevelToString(minLevel),
                                  writeToFile ? logFileName : "disabled",
                                  m_autoRotate ? "ON" : "OFF"));
   }
   
   // Configura opções de formato
   static void SetFormatOptions(bool showTimestamp, bool showComponent)
   {
      m_showTimestamp = showTimestamp;
      m_showComponent = showComponent;
   }
   
   // Habilita/desabilita performance tracking
   static void SetPerformanceTracking(bool enable)
   {
      m_trackPerf = enable;
      if(enable)
         Info("Logger", "Performance tracking HABILITADO");
   }
   
   // Habilita/desabilita estatísticas
   static void SetStatistics(bool enable)
   {
      m_statsEnabled = enable;
      if(!enable)
         m_stats.Reset();
   }
   
   // Habilita/desabilita rotação automática
   static void SetAutoRotate(bool enable)
   {
      m_autoRotate = enable;
   }
   
   // Adiciona componente ao filtro (logs deste componente serão ignorados)
   static void AddComponentFilter(string component)
   {
      // Adiciona componente à string separada por |
      if(m_filteredComponentsStr != "")
         m_filteredComponentsStr += "|";
      
      m_filteredComponentsStr += component;
      m_useComponentFilter = true;
      
      Info("Logger", StringFormat("Filtro adicionado: %s", component));
   }
   
   // Remove componente do filtro
   static void RemoveComponentFilter(string component)
   {
      // Remove componente da string
      StringReplace(m_filteredComponentsStr, component + "|", "");
      StringReplace(m_filteredComponentsStr, "|" + component, "");
      StringReplace(m_filteredComponentsStr, component, "");
      
      if(m_filteredComponentsStr == "")
         m_useComponentFilter = false;
   }
   
   // Limpa todos os filtros
   static void ClearComponentFilters()
   {
      m_filteredComponentsStr = "";
      m_useComponentFilter = false;
      Info("Logger", "Filtros de componente limpos");
   }
   
   //=================================================================
   // 3.4 - LOGGING PRINCIPAL
   //=================================================================
   
   // Método principal de log (todos os outros chamam este)
   static void Log(ENUM_LOG_LEVEL level, string component, string message)
   {
      // Filtra por nível mínimo
      if(level < m_minLevel)
         return;
      
      // Filtra por componente
      if(IsComponentFiltered(component))
         return;
      
      // Atualiza estatísticas
      UpdateStats(level);
      
      // Captura tempo atual
      uint nowMs = GetTickCount();
      datetime now = TimeCurrent();
      
      // Monta string formatada
      string formatted = "";
      
      // Adiciona timestamp (se habilitado)
      if(m_showTimestamp)
      {
         string timestamp = TimeToString(now, TIME_DATE|TIME_MINUTES|TIME_SECONDS);
         formatted += "[" + timestamp + "] ";
      }
      
      // Adiciona nível
      formatted += "[" + LevelToString(level) + "] ";
      
      // Adiciona componente (se habilitado)
      if(m_showComponent)
      {
         // Limita tamanho do componente para alinhamento
         string comp = component;
         if(StringLen(comp) > 20)
            comp = StringSubstr(comp, 0, 17) + "...";
         
         formatted += "[" + comp + "] ";
      }
      
      // Adiciona performance delta (se habilitado)
      if(m_trackPerf && m_lastLogTimeMs > 0)
      {
         uint deltaMs = nowMs - m_lastLogTimeMs;
         if(deltaMs > 0)
            formatted += StringFormat("(+%ums) ", deltaMs);
      }
      
      // Adiciona mensagem
      formatted += message;
      
      // Atualiza último timestamp
      if(m_trackPerf)
         m_lastLogTimeMs = nowMs;
      
      // Imprime no console
      Print(formatted);
      
      // Salva em arquivo se configurado (WARN ou superior)
      if(m_writeToFile && level >= LOG_LEVEL_WARN)
      {
         WriteToFile(formatted);
      }
   }
   
   //=================================================================
   // 3.5 - MÉTODOS DE CONVENIÊNCIA (SHORTCUTS)
   //=================================================================
   
   // TRACE - Rastreamento muito detalhado
   static void Trace(string component, string message)
   {
      Log(LOG_LEVEL_TRACE, component, message);
   }
   
   // DEBUG - Informações de debug
   static void Debug(string component, string message)
   {
      Log(LOG_LEVEL_DEBUG, component, message);
   }
   
   // INFO - Informações gerais
   static void Info(string component, string message)
   {
      Log(LOG_LEVEL_INFO, component, message);
   }
   
   // WARN - Avisos
   static void Warn(string component, string message)
   {
      Log(LOG_LEVEL_WARN, component, message);
   }
   
   // ERROR - Erros recuperáveis
   static void Error(string component, string message)
   {
      Log(LOG_LEVEL_ERROR, component, message);
   }
   
   // FATAL - Erros fatais (também dispara Alert)
   static void Fatal(string component, string message)
   {
      Log(LOG_LEVEL_FATAL, component, message);
      Alert("🚨 ERRO FATAL: " + component + " - " + message);
   }
   
   //=================================================================
   // 3.6 - MÉTODOS DE CONVENIÊNCIA COM FORMATAÇÃO
   //=================================================================
   
   // Shortcut para log de entrada em função
   static void Enter(string component, string functionName)
   {
      Trace(component, "→ " + functionName + "()");
   }
   
   // Shortcut para log de saída de função
   static void Exit(string component, string functionName)
   {
      Trace(component, "← " + functionName + "()");
   }
   
   // Shortcut para log de checkpoint
   static void Checkpoint(string component, string checkpointName)
   {
      Debug(component, "✓ " + checkpointName);
   }
   
   //=================================================================
   // 3.7 - ESTATÍSTICAS E DIAGNÓSTICO
   //=================================================================
   
   // Retorna estatísticas atuais
   static LogStats GetStatistics()
   {
      return m_stats;
   }
   
   // Imprime relatório de estatísticas
   static void PrintStatistics()
   {
      if(!m_statsEnabled)
      {
         Print("[Logger] Estatísticas desabilitadas");
         return;
      }
      
      Print("========================================");
      Print("LOGGER STATISTICS");
      Print("========================================");
      Print(StringFormat("TRACE: %d", m_stats.traceCount));
      Print(StringFormat("DEBUG: %d", m_stats.debugCount));
      Print(StringFormat("INFO:  %d", m_stats.infoCount));
      Print(StringFormat("WARN:  %d", m_stats.warnCount));
      Print(StringFormat("ERROR: %d", m_stats.errorCount));
      Print(StringFormat("FATAL: %d", m_stats.fatalCount));
      Print("----------------------------------------");
      Print(StringFormat("TOTAL: %d", m_stats.GetTotal()));
      Print("========================================");
   }
   
   // Reseta estatísticas
   static void ResetStatistics()
   {
      m_stats.Reset();
      Info("Logger", "Estatísticas resetadas");
   }
   
   // Retorna tamanho atual do arquivo de log (em KB)
   static ulong GetLogFileSizeKB()
   {
      if(!FileIsExist(m_logFile))
         return 0;
      
      return (ulong)FileGetInteger(m_logFile, FILE_SIZE) / 1024ULL;
   }
   
   // Força rotação manual do log
   static void ForceRotate()
   {
      if(!FileIsExist(m_logFile))
      {
         Warn("Logger", "Arquivo de log não existe - rotação cancelada");
         return;
      }
      
      RotateLogFiles();
      Info("Logger", "Rotação manual executada");
   }
   
   // Limpa arquivo de log atual (CUIDADO!)
   static void ClearLogFile()
   {
      if(FileIsExist(m_logFile))
      {
         FileDelete(m_logFile);
         Info("Logger", "Arquivo de log deletado");
      }
   }
   
   //=================================================================
   // 3.8 - DIAGNÓSTICO DO SISTEMA
   //=================================================================
   
   // Imprime configuração atual do logger
   static void PrintConfiguration()
   {
      Print("========================================");
      Print("LOGGER CONFIGURATION");
      Print("========================================");
      Print("Version:      MKS Framework v3.0");
      Print("Min Level:    ", LevelToString(m_minLevel));
      Print("Write to File:", m_writeToFile ? "YES" : "NO");
      Print("Log File:     ", m_logFile);
      Print(StringFormat("File Size:    %llu KB", GetLogFileSizeKB()));  // Conversão explícita ulong
      Print("Timestamp:    ", m_showTimestamp ? "ON" : "OFF");
      Print("Component:    ", m_showComponent ? "ON" : "OFF");
      Print("Perf Track:   ", m_trackPerf ? "ON" : "OFF");
      Print("Statistics:   ", m_statsEnabled ? "ON" : "OFF");
      Print("Auto Rotate:  ", m_autoRotate ? "ON" : "OFF");
      // Conta componentes (número de separadores | + 1, ou 0 se vazio)
      int numComponents = 0;
      if(m_filteredComponentsStr != "")
      {
         numComponents = 1;
         for(int i = 0; i < StringLen(m_filteredComponentsStr); i++)
         {
            if(StringGetCharacter(m_filteredComponentsStr, i) == (ushort)'|')  // Cast explícito
               numComponents++;
         }
      }
      Print(StringFormat("Filters:      %d componentes", numComponents));  // Conversão explícita int
      Print("========================================");
   }
};

//=====================================================================
// SEÇÃO 4: INICIALIZAÇÃO DE VARIÁVEIS ESTÁTICAS
//=====================================================================

// 4.1 - Variáveis estáticas da classe (necessário em MQL5)
static ENUM_LOG_LEVEL CLogger::m_minLevel = LOG_LEVEL_INFO;
static bool CLogger::m_writeToFile = true;
static string CLogger::m_logFile = "MKS_Framework.log";
static bool CLogger::m_showTimestamp = true;
static bool CLogger::m_showComponent = true;
static bool CLogger::m_colorOutput = false;
static bool CLogger::m_trackPerf = false;
static uint CLogger::m_lastLogTimeMs = 0;
static LogStats CLogger::m_stats;
static bool CLogger::m_statsEnabled = true;
static string CLogger::m_filteredComponentsStr = "";  // String vazia inicialmente
static bool CLogger::m_useComponentFilter = false;
static bool CLogger::m_autoRotate = true;
static datetime CLogger::m_lastRotateCheck = 0;

#endif