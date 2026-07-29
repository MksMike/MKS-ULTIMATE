//+------------------------------------------------------------------+
//| @file           : CMksLogger.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Log
//| @responsibility : Implementação de ILogger conforme ADR-007.
//|                   Serializa cada chamada como JSON-line; destino
//|                   dual (Print + FileWrite). Arquivo por sessão.
//| @depends_on     : Core/Interfaces/ILogger.mqh, Core/Types/Error.mqh,
//|                   Core/Version.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Log/CMksLogger.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_LOG_CMKSLOGGER_MQH
#define MKS_ULTIMATE_CORE_LOG_CMKSLOGGER_MQH

#include <MKS-ULTIMATE/Core/Interfaces/ILogger.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Version.mqh>

// Nome do módulo de origem em logs internos do próprio logger (ex: header
// META). Constante em vez de string literal para consistência com o
// padrão do projeto e para facilitar refactor futuro.
#define MKS_MODULE_LOGGER "Logger"

// Helper livre: escapa um valor para uso seguro em ctxJson.
// Usar antes de StringFormat ao compor ctxJson com strings vindas
// de paths, mensagens de erro, ou qualquer texto que possa conter
// aspas, barras invertidas ou controles.
// Parâmetro por valor (não const &) porque MQL5 exige variável nomeada
// para passagem por referência — caller frequentemente passa
// temporários como err.ToString() ou StringFormat(...).
string MksJsonEscape(string s)
{
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\n", "\\n");
   StringReplace(s, "\r", "\\r");
   StringReplace(s, "\t", "\\t");
   return s;
}

// Padrão de uso:
//   CMksLogger lg;
//   if(!lg.Open("MKS-ULTIMATE/Logs/run1.log", MKS_LOG_INFO, true, true, err)) return;
//   lg.WriteHeader(broker, account, symbol, digits, eaName, sessionStartMsc);
//   lg.Log(MKS_LOG_INFO, "Producer", "starting", "");
//   lg.Log(MKS_LOG_INFO, "Producer", "brick emitted",
//          StringFormat("\"brickIdx\":%d,\"M\":%d", 1, 1));
//   // Precisão de ms: passe o timeMsc do tick que originou o evento.
//   lg.Log(MKS_LOG_INFO, "TradeManager", "brick closed", "",
//          brick.closeTimeMsc);
//   lg.Close();
//
// Timestamp: o overload de quatro parâmetros usa TimeCurrent (precisão
// de segundo, .000Z); o overload que recebe timeMsc produz precisão de
// ms real (ADR-007 §1). Escape: implementação escapa internamente module
// e msg (aspas, barras, controle). ctxJson NÃO é re-escapado — caller
// monta JSON válido.
class CMksLogger : public ILogger
{
private:
   int                m_handle;
   ENUM_MKS_LOG_LEVEL m_minLevel;
   bool               m_toPrint;
   bool               m_toFile;
   string             m_filePath;
   bool               m_closed;

   string LevelToString(ENUM_MKS_LOG_LEVEL level) const
   {
      switch(level)
      {
         case MKS_LOG_META:  return "META";
         case MKS_LOG_TRACE: return "TRACE";
         case MKS_LOG_DEBUG: return "DEBUG";
         case MKS_LOG_INFO:  return "INFO";
         case MKS_LOG_WARN:  return "WARN";
         case MKS_LOG_ERROR: return "ERROR";
      }
      return "UNKNOWN";
   }

   // Timestamp ISO 8601 UTC a partir do "agora" do broker. Precisão de
   // SEGUNDO — millis sempre .000. MQL5 não expõe API para "TimeCurrent
   // com millis" — time_msc só existe dentro de MqlTick, não como
   // "agora". GetTickCount não alinha com TimeCurrent (uptime do sistema
   // vs. tempo do broker), então não pode ser usado para preencher
   // sub-segundo honestamente. Em backtest, TimeCurrent é o tempo
   // simulado. Usado no overload de Log() sem timeMsc — quando o caller
   // tem o tick corrente, prefere-se FormatTimestampMsc para honrar a
   // precisão de ms exigida pela ADR-007 §1.
   string FormatTimestamp() const
   {
      datetime t = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(t, dt);
      return StringFormat("%04d-%02d-%02dT%02d:%02d:%02d.000Z",
                          dt.year, dt.mon, dt.day,
                          dt.hour, dt.min, dt.sec);
   }

   // Timestamp ISO 8601 UTC com precisão de milissegundo (ADR-007 §1) a
   // partir de um timeMsc explícito — ms desde epoch, mesma convenção de
   // MqlTick.time_msc e MksTick.timeMsc. O caller passa o timeMsc do tick
   // que originou o evento (ex.: brick.closeTimeMsc em decisões
   // pós-brick), garantindo que dois eventos no mesmo segundo sejam
   // distinguíveis no log-diff de paridade backtest/live.
   string FormatTimestampMsc(long timeMsc) const
   {
      datetime t  = (datetime)(timeMsc / 1000);
      int      ms = (int)(timeMsc % 1000);
      MqlDateTime dt;
      TimeToStruct(t, dt);
      return StringFormat("%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
                          dt.year, dt.mon, dt.day,
                          dt.hour, dt.min, dt.sec, ms);
   }

   // Escapa caracteres que invalidariam JSON. Cobre os controles
   // canônicos (\\, \", \n, \r, \t). Unicode não é tratado — strings
   // do framework são ASCII por convenção.
   string EscapeJson(const string &s) const
   {
      string out = s;
      StringReplace(out, "\\", "\\\\");
      StringReplace(out, "\"", "\\\"");
      StringReplace(out, "\n", "\\n");
      StringReplace(out, "\r", "\\r");
      StringReplace(out, "\t", "\\t");
      return out;
   }

   void EmitLine(const string &line)
   {
      if(m_toPrint)
         Print(line);
      if(m_toFile && m_handle != INVALID_HANDLE)
      {
         FileWriteString(m_handle, line + "\n");
         FileFlush(m_handle); // garante persistência mesmo em crash
      }
   }

   // Núcleo comum aos overloads públicos de Log: aplica o filtro de
   // nível, serializa o JSON-line com o ts já formatado e emite. Manter
   // uma única fonte da verdade do schema evita divergência entre o
   // caminho "agora" (sem timeMsc) e o caminho de precisão de ms.
   void EmitLog(ENUM_MKS_LOG_LEVEL level,
                const string &module,
                const string &msg,
                const string &ctxJson,
                const string &ts)
   {
      // META sempre escreve; demais respeitam filtro de nível mínimo.
      if(level != MKS_LOG_META && level < m_minLevel)
         return;

      string levelStr = LevelToString(level);

      string line;
      if(StringLen(ctxJson) > 0)
      {
         line = StringFormat(
            "{\"ts\":\"%s\",\"level\":\"%s\",\"module\":\"%s\","
            "\"msg\":\"%s\",%s}",
            ts, levelStr, EscapeJson(module), EscapeJson(msg), ctxJson);
      }
      else
      {
         line = StringFormat(
            "{\"ts\":\"%s\",\"level\":\"%s\",\"module\":\"%s\","
            "\"msg\":\"%s\"}",
            ts, levelStr, EscapeJson(module), EscapeJson(msg));
      }
      EmitLine(line);
   }

public:
   CMksLogger()
   {
      m_handle   = INVALID_HANDLE;
      m_minLevel = MKS_LOG_INFO;
      m_toPrint  = true;
      m_toFile   = true;
      m_filePath = "";
      m_closed   = false;
   }

   ~CMksLogger()
   {
      if(m_handle != INVALID_HANDLE)
         FileClose(m_handle);
   }

   // path: relativo a MQL5/Files; caller faz FolderCreate antes.
   // toFile=false desativa o arquivo (logger só faz Print).
   bool Open(const string &path,
             ENUM_MKS_LOG_LEVEL minLevel,
             bool toPrint,
             bool toFile,
             MksError &err)
   {
      if(m_handle != INVALID_HANDLE || m_closed)
      {
         MKS_SET_ERROR(err, MKS_ERR_LOG_STATE_INVALID,
                       "logger já aberto ou fechado", path);
         return false;
      }
      m_minLevel = minLevel;
      m_toPrint  = toPrint;
      m_toFile   = toFile;
      m_filePath = path;
      if(m_toFile)
      {
         m_handle = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
         if(m_handle == INVALID_HANDLE)
         {
            MKS_SET_ERROR(err, MKS_ERR_LOG_FILE_IO, "FileOpen falhou",
                          StringFormat("path=%s LastError=%d",
                                       path, GetLastError()));
            return false;
         }
      }
      return true;
   }

   // Primeira linha do arquivo: JSON-line com level=META carregando
   // proveniência (ADR-007 §6). Linhas subsequentes não repetem.
   void WriteHeader(const string &broker,
                    long accountLogin,
                    const string &symbol,
                    int digits,
                    const string &eaName,
                    long sessionStartMsc)
   {
      string ctxJson = StringFormat(
         "\"broker\":\"%s\",\"account\":%I64d,\"symbol\":\"%s\","
         "\"digits\":%d,\"frameworkVersion\":\"%s\","
         "\"eaName\":\"%s\",\"sessionStartMsc\":%I64d",
         EscapeJson(broker), accountLogin,
         EscapeJson(symbol), digits,
         MKS_ULTIMATE_VERSION_STR,
         EscapeJson(eaName), sessionStartMsc);
      Log(MKS_LOG_META, MKS_MODULE_LOGGER, "session header", ctxJson);
   }

   // Overload de contrato (ILogger): usa o "agora" do broker como ts,
   // com precisão de segundo (.000Z). Preferir o overload com timeMsc
   // sempre que o caller tiver o tick que originou o evento.
   void Log(ENUM_MKS_LOG_LEVEL level,
            const string &module,
            const string &msg,
            const string &ctxJson) override
   {
      EmitLog(level, module, msg, ctxJson, FormatTimestamp());
   }

   // Overload com precisão de ms (ADR-007 §1): o caller passa o timeMsc
   // do tick corrente (ex.: brick.closeTimeMsc em eventos pós-brick).
   // Disponível apenas via ponteiro concreto CMksLogger* — a interface
   // ILogger permanece com a assinatura de quatro parâmetros.
   void Log(ENUM_MKS_LOG_LEVEL level,
            const string &module,
            const string &msg,
            const string &ctxJson,
            long timeMsc)
   {
      EmitLog(level, module, msg, ctxJson, FormatTimestampMsc(timeMsc));
   }

   void Close()
   {
      if(m_handle != INVALID_HANDLE)
      {
         FileClose(m_handle);
         m_handle = INVALID_HANDLE;
      }
      m_closed = true;
   }

   string FilePath() const { return m_filePath; }

   //--- Helpers por nível. Disponíveis quando o caller tem ponteiro
   //--- para CMksLogger*; código que usa ILogger* chama Log() direto.
   void Trace(const string &module, const string &msg, const string &ctxJson)
   {
      Log(MKS_LOG_TRACE, module, msg, ctxJson);
   }
   void Debug(const string &module, const string &msg, const string &ctxJson)
   {
      Log(MKS_LOG_DEBUG, module, msg, ctxJson);
   }
   void Info(const string &module, const string &msg, const string &ctxJson)
   {
      Log(MKS_LOG_INFO, module, msg, ctxJson);
   }
   void Warn(const string &module, const string &msg, const string &ctxJson)
   {
      Log(MKS_LOG_WARN, module, msg, ctxJson);
   }
   void Error(const string &module, const string &msg, const string &ctxJson)
   {
      Log(MKS_LOG_ERROR, module, msg, ctxJson);
   }

   //--- Overloads com timeMsc explícito: ts ganha precisão de ms a
   //--- partir do tick que originou o evento (ADR-007 §1). Uso típico:
   //--- decisões pós-brick passando brick.closeTimeMsc.
   void Trace(const string &module, const string &msg, const string &ctxJson, long timeMsc)
   {
      Log(MKS_LOG_TRACE, module, msg, ctxJson, timeMsc);
   }
   void Debug(const string &module, const string &msg, const string &ctxJson, long timeMsc)
   {
      Log(MKS_LOG_DEBUG, module, msg, ctxJson, timeMsc);
   }
   void Info(const string &module, const string &msg, const string &ctxJson, long timeMsc)
   {
      Log(MKS_LOG_INFO, module, msg, ctxJson, timeMsc);
   }
   void Warn(const string &module, const string &msg, const string &ctxJson, long timeMsc)
   {
      Log(MKS_LOG_WARN, module, msg, ctxJson, timeMsc);
   }
   void Error(const string &module, const string &msg, const string &ctxJson, long timeMsc)
   {
      Log(MKS_LOG_ERROR, module, msg, ctxJson, timeMsc);
   }
};

#endif // MKS_ULTIMATE_CORE_LOG_CMKSLOGGER_MQH
