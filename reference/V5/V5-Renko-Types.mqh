//+------------------------------------------------------------------+
//| MKS-Renko-Types.mqh                                          |
//| MKS Framework - V5.0 Research Engine                             |
//| Descricao: Tipos, enums, structs e parsing de configuracao    |
//| Instalacao: MQL5/Include/MKS-V5.0/Core/                        |
//| Build: V5.0 (2026-04-07)                                         |
//+------------------------------------------------------------------+

#ifndef __MKS_RENKO_TYPES_MQH__
#define __MKS_RENKO_TYPES_MQH__

#include <MKS-V5.0/Core/Logger.mqh>

//=====================================================================
// SEÇÃO 1: VERSÃO E METADADOS
//=====================================================================

// 1.1 - Versão do framework
#define MKS_VERSION    "V5.0"
#define MKS_BUILD_DATE "2026-04-07"

//=====================================================================
// SEÇÃO 2: ENUMERAÇÕES TIPADAS
//=====================================================================

// 2.1 - Presets de configuração Renko
enum ENUM_MKS_PRESET
{
   MKS_PRESET_RENKO = 0,      // Renko clássico (PO=0%, PRO=0%)
   MKS_PRESET_MEDIAN = 1,     // Median Renko (PO=50%, PRO=50%)
   MKS_PRESET_TURBO = 2,      // Turbo Renko (PO=50%, PRO=25%)
   MKS_PRESET_HYBRID = 3,     // Hybrid Renko (PO=25%, PRO=25%)
   MKS_PRESET_CUSTOM = 4,     // Custom (usuário define PO/PRO)
   MKS_PRESET_SCALP = 5       // Scalp Renko (PO=50%, PRO=75%)
};

// 2.2 - Modos de tamanho de brick
enum ENUM_MKS_SIZE_MODE
{
   MKS_SIZE_TICKS = 0,        // Tamanho em ticks
   MKS_SIZE_POINTS = 1,       // Tamanho em pontos
   MKS_SIZE_PIPS = 2,         // Tamanho em pips (ponto * 10)
   MKS_SIZE_PRICE = 3,        // Tamanho direto em preço
   MKS_SIZE_ATR = 4,          // Tamanho baseado em ATR
   MKS_SIZE_PERCENT = 5       // Tamanho em % do preço
};

// 2.3 - Fonte de dados
enum ENUM_MKS_DATA_SOURCE
{
   MKS_SOURCE_TICKS = 0,      // Usa ticks reais (mais preciso)
   MKS_SOURCE_M1 = 1          // Usa barras M1 (mais rápido)
};

// 2.4 - Direção do brick
enum ENUM_MKS_DIRECTION
{
   MKS_BEAR = -1,             // Brick de baixa (bearish)
   MKS_NONE = 0,              // Sem direção (inicial)
   MKS_BULL = 1               // Brick de alta (bullish)
};

// 2.5 - Códigos de erro do framework
enum ENUM_MKS_ERROR
{
   MKS_ERROR_NONE = 0,                    // Sem erro
   MKS_ERROR_INVALID_CONFIG = 1,          // Configuração inválida
   MKS_ERROR_INVALID_BRICK_SIZE = 2,      // Tamanho de brick inválido
   MKS_ERROR_SYMBOL_NOT_FOUND = 3,        // Símbolo não encontrado
   MKS_ERROR_INIT_FAILED = 4,             // Falha na inicialização
   MKS_ERROR_INVALID_PRESET = 5,          // Preset inválido
   MKS_ERROR_INVALID_SIZE_MODE = 6,       // Modo de tamanho inválido
   MKS_ERROR_ATR_FAILED = 7,              // Falha ao calcular ATR
   MKS_ERROR_CUSTOM_SYMBOL_FAILED = 8,    // Falha ao criar Custom Symbol
   MKS_ERROR_LIVE_ENGINE_SYNC = 9,        // Falha de sincronização LiveEngine
   MKS_ERROR_PARSING_FAILED = 10          // Falha ao fazer parsing de nome
};

//=====================================================================
// SEÇÃO 3: ESTRUTURAS DE DADOS
//=====================================================================

// 3.1 - Configuração Renko (com validação)
struct MKSRenkoConfig
{
   //--- Metadados
   int      version;                      // Versão da config (para compatibilidade)
   
   //--- Configuração básica
   ENUM_MKS_PRESET preset;                // Preset selecionado
   double   brickSize;                    // Tamanho base do brick
   ENUM_MKS_SIZE_MODE sizeMode;           // Modo de cálculo do tamanho
   
   //--- Configuração de reversão
   double   openPct;                      // % de abertura para continuação (PO)
   double   revOpenPct;                   // % de abertura para reversão (PRO)
   double   revSizePct;                   // % do tamanho para reversão
   
   //--- Fonte e período
   ENUM_MKS_DATA_SOURCE dataSource;       // Fonte de dados (ticks ou M1)
   int      days;                         // Dias de histórico
   
   //--- Visualização
   bool     showWicks;                    // Mostrar wicks nos bricks
   
   //--- Parâmetros específicos por modo
   int      atrPeriod;                    // Período ATR (se SIZE_ATR)
   double   atrFactor;                    // Multiplicador ATR
   double   percentFactor;                // Fator % (se SIZE_PERCENT)
   
   //--- Construtor com valores padrão seguros
   MKSRenkoConfig()
   {
      version = 3;                        // v3.0
      preset = MKS_PRESET_MEDIAN;
      brickSize = 100;
      sizeMode = MKS_SIZE_TICKS;
      openPct = 0.50;
      revOpenPct = 0.50;
      revSizePct = 100.0;
      dataSource = MKS_SOURCE_TICKS;
      days = 30;
      showWicks = true;
      atrPeriod = 14;
      atrFactor = 1.5;
      percentFactor = 0.5;
   }
   
   //--- Método de validação (retorna false se inválido)
   bool Validate(string &errorMsg)
   {
      // Valida versão
      if(version != 3)
      {
         errorMsg = StringFormat("Versão incompatível: %d (esperado: 3)", version);
         return false;
      }
      
      // Valida preset
      if(preset < MKS_PRESET_RENKO || preset > MKS_PRESET_SCALP)
      {
         errorMsg = StringFormat("Preset inválido: %d", preset);
         return false;
      }
      
      // Valida brick size
      if(brickSize <= 0)
      {
         errorMsg = StringFormat("BrickSize deve ser > 0: %.2f", brickSize);
         return false;
      }
      
      // Valida size mode
      if(sizeMode < MKS_SIZE_TICKS || sizeMode > MKS_SIZE_PERCENT)
      {
         errorMsg = StringFormat("SizeMode inválido: %d", sizeMode);
         return false;
      }
      
      // Valida percentuais de abertura (se custom)
      if(preset == MKS_PRESET_CUSTOM)
      {
         if(openPct < 0 || openPct > 1.0)
         {
            errorMsg = StringFormat("OpenPct fora do range [0-1]: %.2f", openPct);
            return false;
         }
         
         if(revOpenPct < 0 || revOpenPct > 1.0)
         {
            errorMsg = StringFormat("RevOpenPct fora do range [0-1]: %.2f", revOpenPct);
            return false;
         }
      }
      
      // Valida reversal size
      if(revSizePct <= 0)
      {
         errorMsg = StringFormat("RevSizePct deve ser > 0: %.2f", revSizePct);
         return false;
      }
      
      // Valida ATR period (se modo ATR)
      if(sizeMode == MKS_SIZE_ATR && atrPeriod <= 0)
      {
         errorMsg = StringFormat("ATR Period deve ser > 0: %d", atrPeriod);
         return false;
      }
      
      // Valida days
      if(days < 1)
      {
         errorMsg = StringFormat("Days deve ser >= 1: %d", days);
         return false;
      }
      
      // Tudo OK
      return true;
   }
};

// 3.2 - Brick individual
struct MKSRenkoBrick
{
   //--- Preços OHLC
   double   open;                         // Preço de abertura
   double   high;                         // Preço máximo (com wick se ativo)
   double   low;                          // Preço mínimo (com wick se ativo)
   double   close;                        // Preço de fechamento
   
   //--- Metadados
   ENUM_MKS_DIRECTION direction;          // Direção do brick (bull/bear)
   datetime time;                         // Timestamp real do brick
   bool     isForming;                    // True se brick em formação
   
   //--- V3.0.1 BUG FIX: Spread histórico
   int      spread;                       // Spread em ticks no momento da formação
   
   //--- Métodos auxiliares inline
   bool IsBull() const { return direction == MKS_BULL; }
   bool IsBear() const { return direction == MKS_BEAR; }
   double GetSize() const { return MathAbs(close - open); }
};

// 3.3 - Estado interno do core
struct MKSRenkoState
{
   //--- Estado do último brick completado
   double   prevClose;                    // Close do último brick
   ENUM_MKS_DIRECTION prevDir;            // Direção do último brick
   
   //--- Wicks acumulados
   double   wickHigh;                     // Wick alto acumulado
   double   wickLow;                      // Wick baixo acumulado
   
   //--- Contadores
   int      count;                        // Total de bricks completados
   
   //--- Brick em formação
   double   formOpen;                     // Open do forming brick
   double   formHigh;                     // High do forming brick
   double   formLow;                      // Low do forming brick
   double   formClose;                    // Close do forming brick
   ENUM_MKS_DIRECTION formDir;            // Direção do forming brick
   
   //--- Construtor
   MKSRenkoState()
   {
      prevClose = 0.0;
      prevDir = MKS_NONE;
      wickHigh = 0.0;
      wickLow = 0.0;
      count = 0;
      formOpen = 0.0;
      formHigh = 0.0;
      formLow = 0.0;
      formClose = 0.0;
      formDir = MKS_NONE;
   }
};

// 3.4 - Estrutura de erro (com contexto)
struct MKSError
{
   ENUM_MKS_ERROR code;                   // Código do erro
   string message;                        // Mensagem descritiva
   string context;                        // Contexto adicional
   
   //--- Construtor
   MKSError()
   {
      code = MKS_ERROR_NONE;
      message = "";
      context = "";
   }
   
   //--- Define erro e loga automaticamente
   void Set(ENUM_MKS_ERROR errorCode, string msg, string ctx = "")
   {
      code = errorCode;
      message = msg;
      context = ctx;
      
      // Log automático
      CLogger::Error("MKS-Error", StringFormat("[%d] %s | Context: %s",
                                               errorCode, msg, ctx));
   }
   
   //--- Verifica se há erro
   bool HasError() const
   {
      return (code != MKS_ERROR_NONE);
   }
   
   //--- Limpa erro
   void Clear()
   {
      code = MKS_ERROR_NONE;
      message = "";
      context = "";
   }
   
   //--- Retorna descrição completa
   string ToString() const
   {
      if(!HasError()) return "No error";
      
      return StringFormat("[%d] %s | Context: %s", code, message, context);
   }
};

//=====================================================================
// SEÇÃO 4: FUNÇÕES AUXILIARES DE PRESET
//=====================================================================

// 4.1 - Retorna % de abertura para continuação (PO)
double MKS_PO(MKSRenkoConfig &cfg)
{
   switch(cfg.preset)
   {
      case MKS_PRESET_RENKO:  return 0.00;   // Renko clássico
      case MKS_PRESET_MEDIAN: return 0.50;   // Median Renko
      case MKS_PRESET_TURBO:  return 0.50;   // Turbo Renko
      case MKS_PRESET_HYBRID: return 0.25;   // Hybrid Renko
      case MKS_PRESET_CUSTOM: return cfg.openPct;  // Custom
      case MKS_PRESET_SCALP:  return 0.50;   // Scalp Renko
      default:                return 0.50;   // Fallback seguro
   }
}

// 4.2 - Retorna % de abertura para reversão (PRO)
double MKS_PRO(MKSRenkoConfig &cfg)
{
   switch(cfg.preset)
   {
      case MKS_PRESET_RENKO:  return 0.00;   // Renko clássico
      case MKS_PRESET_MEDIAN: return 0.50;   // Median Renko
      case MKS_PRESET_TURBO:  return 0.25;   // Turbo Renko
      case MKS_PRESET_HYBRID: return 0.25;   // Hybrid Renko
      case MKS_PRESET_CUSTOM: return cfg.revOpenPct;  // Custom
      case MKS_PRESET_SCALP:  return 0.75;   // Scalp Renko
      default:                return 0.50;   // Fallback seguro
   }
}

//=====================================================================
// SEÇÃO 5: CÁLCULO DE BRICK SIZE
//=====================================================================

// 5.1 - Calcula o tamanho real do brick em preço
double MKS_CalcBrickSize(string symbol, MKSRenkoConfig &cfg, MKSError &error)
{
   // Obtém propriedades do símbolo
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   // Fallbacks para valores inválidos
   if(tickSize <= 0.0 && point > 0.0) tickSize = point;
   if(point <= 0.0 && tickSize > 0.0) point = tickSize;
   if(tickSize <= 0.0) tickSize = MathPow(10.0, -digits);
   
   // Log de debug
   CLogger::Debug("CalcBrickSize", StringFormat("%s | digits=%d | point=%.6f | tick=%.6f",
                                                symbol, digits, point, tickSize));
   
   double sz = 0.0;
   
   // Calcula tamanho baseado no modo
   switch(cfg.sizeMode)
   {
      case MKS_SIZE_TICKS:
         // Modo: Ticks (ex: 100 ticks)
         sz = cfg.brickSize * tickSize;
         break;
         
      case MKS_SIZE_POINTS:
         // Modo: Points (ex: 100 points)
         sz = cfg.brickSize * point;
         break;
         
      case MKS_SIZE_PIPS:
         // Modo: Pips (ex: 10 pips = 100 points)
         sz = cfg.brickSize * point * 10.0;
         break;
         
      case MKS_SIZE_PRICE:
         // Modo: Preço direto (ex: 3.0 = $3.00)
         sz = cfg.brickSize;
         break;
         
      case MKS_SIZE_ATR:
      {
         // Modo: ATR (Average True Range)
         int atrHandle = iATR(symbol, PERIOD_D1, cfg.atrPeriod);
         if(atrHandle == INVALID_HANDLE)
         {
            error.Set(MKS_ERROR_ATR_FAILED, "Falha ao criar ATR handle", symbol);
            return 0.0;
         }
         
         double atrBuf[];
         ArraySetAsSeries(atrBuf, true);
         if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) <= 0)
         {
            error.Set(MKS_ERROR_ATR_FAILED, "Falha ao ler ATR buffer", symbol);
            IndicatorRelease(atrHandle);
            return 0.0;
         }
         
         sz = cfg.atrFactor * atrBuf[0];
         
         CLogger::Info("CalcBrickSize", StringFormat("ATR(%d)=%.6f | fator=%.2f | sz=%.6f",
                                                     cfg.atrPeriod, atrBuf[0], cfg.atrFactor, sz));
         
         IndicatorRelease(atrHandle);
         break;
      }
      
      case MKS_SIZE_PERCENT:
      {
         // Modo: % do preço atual
         double price = SymbolInfoDouble(symbol, SYMBOL_BID);
         if(price <= 0.0)
         {
            error.Set(MKS_ERROR_SYMBOL_NOT_FOUND, "Preço inválido", symbol);
            return 0.0;
         }
         sz = (cfg.percentFactor / 100.0) * price;
         break;
      }
      
      default:
         error.Set(MKS_ERROR_INVALID_SIZE_MODE, "SizeMode desconhecido",
                  StringFormat("mode=%d", cfg.sizeMode));
         return 0.0;
   }
   
   // Normaliza para os dígitos do símbolo
   sz = NormalizeDouble(sz, digits);
   
   // Garante que não seja menor que tick size
   if(sz < tickSize)
   {
      CLogger::Warn("CalcBrickSize", StringFormat("sz (%.6f) < tickSize (%.6f) - ajustado",
                                                  sz, tickSize));
      sz = tickSize;
   }
   
   // Log final
   CLogger::Info("CalcBrickSize", StringFormat("%s | Mode=%d | BrickSize=%.4f | SZ=%.6f",
                                               symbol, cfg.sizeMode, cfg.brickSize, sz));
   
   return sz;
}

//=====================================================================
// SEÇÃO 6: NAMING CONVENTION
//=====================================================================

// 6.1 - Gera nome do Custom Symbol (formato v3.0)
// Formato: SYMBOL_MKS_SIZE_PRESET
// Exemplo: XAUUSDm_MKS_3.0Pr_MR
string MKS_SymbolName(string symbol, MKSRenkoConfig &cfg)
{
   // Determina sufixo do modo
   string modeName = "";
   switch(cfg.sizeMode)
   {
      case MKS_SIZE_TICKS:   modeName = "T"; break;
      case MKS_SIZE_POINTS:  modeName = "P"; break;
      case MKS_SIZE_PIPS:    modeName = "Pip"; break;
      case MKS_SIZE_PRICE:   modeName = "Pr"; break;
      case MKS_SIZE_ATR:     modeName = "ATR"; break;
      case MKS_SIZE_PERCENT: modeName = "Pct"; break;
      default:               modeName = "?"; break;
   }
   
   // Determina sufixo do preset
   string presetName = "";
   switch(cfg.preset)
   {
      case MKS_PRESET_RENKO:  presetName = "Rk"; break;
      case MKS_PRESET_MEDIAN: presetName = "MR"; break;
      case MKS_PRESET_TURBO:  presetName = "TR"; break;
      case MKS_PRESET_HYBRID: presetName = "HR"; break;
      case MKS_PRESET_CUSTOM: presetName = "Cu"; break;
      case MKS_PRESET_SCALP:  presetName = "Sc"; break;
      default:                presetName = "XX"; break;
   }
   
   // Formata string do tamanho
   string sizeStr = "";
   if(cfg.sizeMode == MKS_SIZE_PRICE || cfg.sizeMode == MKS_SIZE_ATR || cfg.sizeMode == MKS_SIZE_PERCENT)
      sizeStr = DoubleToString(cfg.brickSize, 1);  // Ex: 3.0
   else
      sizeStr = IntegerToString((int)cfg.brickSize);  // Ex: 100
   
   // Monta nome final
   // Formato v3.0: SYMBOL_MKS_SIZE_PRESET
   string csName = symbol + "_MKS_" + sizeStr + modeName + "_" + presetName;
   
   // Verifica limite de 32 caracteres do MT5
   if(StringLen(csName) > 32)
   {
      CLogger::Warn("SymbolName", StringFormat("Nome muito longo (%d chars): %s",
                                               StringLen(csName), csName));
      
      // Trunca o símbolo base se necessário
      int maxSymLen = 32 - StringLen("_MKS_") - StringLen(sizeStr) - StringLen(modeName) 
                         - StringLen("_") - StringLen(presetName);
      
      if(maxSymLen > 0 && StringLen(symbol) > maxSymLen)
      {
         string symTrunc = StringSubstr(symbol, 0, maxSymLen);
         csName = symTrunc + "_MKS_" + sizeStr + modeName + "_" + presetName;
         CLogger::Info("SymbolName", StringFormat("Truncado para: %s", csName));
      }
   }
   
   return csName;
}

// 6.2 - Faz parsing do nome do Custom Symbol (v3.0)
// Formato esperado: SYMBOL_MKS_SIZE_PRESET
// Retorna: true se sucesso, false se falha
bool MKS_ParseSymbolName(string csName, string &outBaseSymbol, double &outBrickSize, 
                         ENUM_MKS_SIZE_MODE &outSizeMode, ENUM_MKS_PRESET &outPreset)
{
   // Divide por underscore
   string parts[];
   int count = StringSplit(csName, '_', parts);
   
   // Mínimo esperado: 4 partes (SYMBOL_MKS_SIZE_PRESET)
   if(count < 4)
   {
      CLogger::Error("ParseSymbolName", "Nome inválido - esperado formato: SYMBOL_MKS_SIZE_PRESET");
      return false;
   }
   
   // Valida que segunda parte é "MKS"
   int mksIndex = -1;
   for(int i = 0; i < count; i++)
   {
      if(parts[i] == "MKS")
      {
         mksIndex = i;
         break;
      }
   }
   
   if(mksIndex == -1)
   {
      CLogger::Error("ParseSymbolName", "Nome não contém '_MKS_'");
      return false;
   }
   
   // Extrai símbolo base (tudo antes de MKS)
   outBaseSymbol = "";
   for(int i = 0; i < mksIndex; i++)
   {
      if(i > 0) outBaseSymbol += "_";
      outBaseSymbol += parts[i];
   }
   
   // Valida que há pelo menos 2 partes após MKS
   if(mksIndex + 2 >= count)
   {
      CLogger::Error("ParseSymbolName", "Faltam SIZE e PRESET após MKS");
      return false;
   }
   
   // Extrai SIZE (parte após MKS)
   string sizeStr = parts[mksIndex + 1];
   
   // Determina size mode pelo sufixo
   // IMPORTANTE: verificar sufixos mais especificos ANTES dos mais curtos
   // para evitar falso-positivo: "ATR" contem "T"; "Pip"/"Pr"/"Pct" contem "P"
   // BUG FIX Cowork-V4.5: reordenado para evitar ATR detectado como TICKS
   if(StringFind(sizeStr, "ATR") >= 0)
      outSizeMode = MKS_SIZE_ATR;
   else if(StringFind(sizeStr, "Pip") >= 0)
      outSizeMode = MKS_SIZE_PIPS;
   else if(StringFind(sizeStr, "Pct") >= 0)
      outSizeMode = MKS_SIZE_PERCENT;
   else if(StringFind(sizeStr, "Pr") >= 0)
      outSizeMode = MKS_SIZE_PRICE;
   else if(StringFind(sizeStr, "P") >= 0)
      outSizeMode = MKS_SIZE_POINTS;
   else if(StringFind(sizeStr, "T") >= 0)
      outSizeMode = MKS_SIZE_TICKS;
   else
      outSizeMode = MKS_SIZE_TICKS;  // Default
   
   // Extrai número do size
   string numStr = "";
   for(int i = 0; i < StringLen(sizeStr); i++)
   {
      ushort ch = StringGetCharacter(sizeStr, i);
      if((ch >= '0' && ch <= '9') || ch == '.')
         numStr += ShortToString(ch);
      else
         break;
   }
   
   outBrickSize = StringToDouble(numStr);
   
   if(outBrickSize <= 0.0)
   {
      CLogger::Error("ParseSymbolName", StringFormat("BrickSize inválido: %s", sizeStr));
      return false;
   }
   
   // Extrai PRESET (última parte)
   string presetStr = parts[count - 1];
   
   if(presetStr == "Rk")
      outPreset = MKS_PRESET_RENKO;
   else if(presetStr == "MR")
      outPreset = MKS_PRESET_MEDIAN;
   else if(presetStr == "TR")
      outPreset = MKS_PRESET_TURBO;
   else if(presetStr == "HR")
      outPreset = MKS_PRESET_HYBRID;
   else if(presetStr == "Cu")
      outPreset = MKS_PRESET_CUSTOM;
   else if(presetStr == "Sc")
      outPreset = MKS_PRESET_SCALP;
   else
   {
      CLogger::Warn("ParseSymbolName", StringFormat("Preset desconhecido: %s - usando MEDIAN", presetStr));
      outPreset = MKS_PRESET_MEDIAN;
   }
   
   // Log de sucesso
   CLogger::Info("ParseSymbolName", StringFormat("CS: %s → Symbol: %s | Size: %.2f | Mode: %d | Preset: %d",
                                                 csName, outBaseSymbol, outBrickSize, outSizeMode, outPreset));
   
   return true;
}

#endif