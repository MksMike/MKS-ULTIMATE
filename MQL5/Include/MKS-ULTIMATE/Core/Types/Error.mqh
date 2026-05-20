//+------------------------------------------------------------------+
//| @file           : Error.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Types
//| @responsibility : Tipo de erro estruturado MksError, enum de
//|                   códigos particionado por módulo e a macro de
//|                   captura de localização. Ver ADR-009.
//| @depends_on     : Nenhuma (autocontido)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Types/Error.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TYPES_ERROR_MQH
#define MKS_ULTIMATE_CORE_TYPES_ERROR_MQH

enum ENUM_MKS_ERROR_CODE
{
   MKS_ERR_NONE = 0,                    // ausência de erro

   //--- Core: faixa 1–99 ---
   MKS_ERR_CORE_INVALID_ARGUMENT = 1,   // argumento fora do contrato

   //--- RenkoBuilder: faixa 100–199 ---
   MKS_ERR_RENKO_INVALID_GEOMETRY = 100,   // triplo (PO,PRO,revSizeRatio) inválido
   MKS_ERR_RENKO_INVALID_BRICK_SIZE = 101, // tamanho de brick inválido (<= 0)
   MKS_ERR_RENKO_THRESHOLD_LIMIT_EXCEEDED = 102, // cruzamento acima do limiar K (ADR-011)
   MKS_ERR_RENKO_INVALID_TICK = 103,        // tick reprovado por IsValid() (ADR-006)
   MKS_ERR_RENKO_TICK_STREAM_CORRUPT = 104, // L ticks inválidos consecutivos (ADR-006)

   //--- Broker 200–299, Trade 300–399, Risk 400–499,
   //    StressLab 500–599, Log 600–699, Testing 700–799 — ver ADR-009
   //    Data 800–899 — ver ADR-012 (TickSource, serializadores, integridade de header)
};

struct MksError
{
   ENUM_MKS_ERROR_CODE code;
   string  message;     // descrição legível
   string  file;        // arquivo de origem (__FILE__)
   string  function;    // função de origem (__FUNCTION__)
   int     line;        // linha de origem (__LINE__)
   string  detail;      // valores de runtime, contexto adicional

   MksError()
   {
      code = MKS_ERR_NONE;
      message = ""; file = ""; function = ""; line = 0; detail = "";
   }

   //--- Preenche o erro. NÃO loga — logar é decisão do chamador (ADR-009).
   //--- Use a macro MKS_SET_ERROR para capturar a localização sozinho.
   void Set(ENUM_MKS_ERROR_CODE c, const string &msg, const string &det,
            const string &srcFile, const string &srcFunc, int srcLine)
   {
      code = c; message = msg; detail = det;
      file = srcFile; function = srcFunc; line = srcLine;
   }

   void Clear()
   {
      code = MKS_ERR_NONE;
      message = ""; file = ""; function = ""; line = 0; detail = "";
   }

   bool   HasError() const { return code != MKS_ERR_NONE; }

   string ToString() const
   {
      if(code == MKS_ERR_NONE)
         return "no error";
      return StringFormat("[%d] %s | %s:%s:%d | %s",
                          (int)code, message, file, function, line, detail);
   }
};

//--- Preenche um MksError capturando arquivo/função/linha do call site.
#define MKS_SET_ERROR(err, code, msg, detail) \
   (err).Set((code), (msg), (detail), __FILE__, __FUNCTION__, __LINE__)

#endif // MKS_ULTIMATE_CORE_TYPES_ERROR_MQH
