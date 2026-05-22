//+------------------------------------------------------------------+
//| MKS-Renko-Core.mqh                                           |
//| MKS Framework - V5.0 Research Engine                             |
//| Descricao: Motor Renko PO/PRO com state machine               |
//| Instalacao: MQL5/Include/MKS-V5.0/Core/                        |
//| Build: V5.0 (2026-04-07)                                         |
//+------------------------------------------------------------------+

#ifndef __MKS_RENKO_CORE_MQH__
#define __MKS_RENKO_CORE_MQH__

#include <MKS-V5.0/Core/MKS-Renko-Types.mqh>
#include <MKS-V5.0/Core/Logger.mqh>

//=====================================================================
// SEÇÃO 1: ESTRUTURAS DE PERFORMANCE
//=====================================================================

// 1.1 - Métricas de performance do Core
struct MKSCoreMetrics
{
   //--- Contadores de processamento
   uint totalProcessCalls;              // Total de chamadas ProcessPrice()
   uint totalBricksGenerated;           // Total de bricks gerados
   uint totalPricesProcessed;           // Total de preços processados
   
   //--- Performance de tempo
   uint avgProcessTimeUs;               // Tempo médio de processamento (microsegundos)
   uint maxProcessTimeUs;               // Tempo máximo de processamento
   uint minProcessTimeUs;               // Tempo mínimo de processamento
   
   //--- Estatísticas de bricks
   uint bullBricks;                     // Total de bricks bullish
   uint bearBricks;                     // Total de bricks bearish
   uint reversalCount;                  // Total de reversões
   
   //--- Timestamps
   datetime lastProcessTime;            // Último timestamp processado
   datetime startTime;                  // Timestamp de inicialização
   
   //--- Taxas calculadas
   double bricksPerSecond;              // Taxa de geração de bricks
   double avgBricksPerCall;             // Média de bricks por chamada
   
   //--- Construtor
   MKSCoreMetrics()
   {
      totalProcessCalls = 0;
      totalBricksGenerated = 0;
      totalPricesProcessed = 0;
      avgProcessTimeUs = 0;
      maxProcessTimeUs = 0;
      minProcessTimeUs = 0;
      bullBricks = 0;
      bearBricks = 0;
      reversalCount = 0;
      lastProcessTime = 0;
      startTime = 0;
      bricksPerSecond = 0.0;
      avgBricksPerCall = 0.0;
   }
   
   //--- Reseta métricas
   void Reset()
   {
      totalProcessCalls = 0;
      totalBricksGenerated = 0;
      totalPricesProcessed = 0;
      avgProcessTimeUs = 0;
      maxProcessTimeUs = 0;
      minProcessTimeUs = 0;
      bullBricks = 0;
      bearBricks = 0;
      reversalCount = 0;
      lastProcessTime = 0;
      startTime = TimeCurrent();
      bricksPerSecond = 0.0;
      avgBricksPerCall = 0.0;
   }
   
   //--- Atualiza taxas calculadas
   void UpdateRates()
   {
      // Calcula bricks por segundo
      if(lastProcessTime > 0 && startTime > 0)
      {
         int elapsedSec = (int)(lastProcessTime - startTime);
         if(elapsedSec > 0)
            bricksPerSecond = (double)totalBricksGenerated / elapsedSec;
      }
      
      // Calcula média de bricks por chamada
      if(totalProcessCalls > 0)
         avgBricksPerCall = (double)totalBricksGenerated / totalProcessCalls;
   }
};

//=====================================================================
// SEÇÃO 2: CLASSE CORE PRINCIPAL
//=====================================================================

// 2.1 - Motor matemático Renko (motor puro, stateless externally)
class CMKSRenkoCore
{
private:
   //=================================================================
   // 2.2 - VARIÁVEIS DE CONFIGURAÇÃO
   //=================================================================
   
   MKSRenkoConfig  m_config;           // Configuração Renko
   MKSRenkoState   m_state;            // Estado interno
   MKSRenkoBrick   m_bricks[];         // Array de bricks completados
   MKSCoreMetrics  m_metrics;          // Métricas de performance
   
   //--- Parâmetros calculados (cache)
   double          m_sz;               // Tamanho do brick (em preço)
   double          m_revSz;            // Tamanho de reversão
   int             m_digits;           // Dígitos de precisão
   double          m_pO;               // % de abertura (continuation)
   double          m_pRO;              // % de abertura (reversal)
   bool            m_showWicks;        // Se true, mostra wicks
   bool            m_initialized;      // Se true, core foi inicializado
   
   //--- Performance tracking
   bool            m_trackPerformance; // Se true, rastreia performance
   
   //=================================================================
   // 2.3 - MÉTODOS PRIVADOS DE CRIAÇÃO DE BRICKS
   //=================================================================
   
   // Adiciona brick completado ao array
   void PushBrick(MKSRenkoBrick &brick)
   {
      int size = ArraySize(m_bricks);
      ArrayResize(m_bricks, size + 1, 512);  // Reserve com 512 de incremento
      m_bricks[size] = brick;
      m_state.count = size + 1;
      
      // Atualiza métricas
      m_metrics.totalBricksGenerated++;
      
      if(brick.IsBull())
         m_metrics.bullBricks++;
      else
         m_metrics.bearBricks++;
      
      // Detecta reversão
      if(size > 0 && m_bricks[size - 1].direction != brick.direction)
         m_metrics.reversalCount++;
   }
   
   // Cria brick bullish completado
   void MakeBull(double openP, double closeP, datetime time, int spread = 0)
   {
      MKSRenkoBrick brick;
      
      // Normaliza preços
      brick.open  = NormalizeDouble(openP, m_digits);
      brick.close = NormalizeDouble(closeP, m_digits);
      
      // Calcula high/low com ou sem wicks
      if(m_showWicks)
      {
         brick.high = NormalizeDouble(MathMax(closeP, m_state.wickHigh), m_digits);
         brick.low  = NormalizeDouble(MathMin(openP, m_state.wickLow), m_digits);
      }
      else
      {
         brick.high = brick.close;
         brick.low  = brick.open;
      }
      
      brick.direction = MKS_BULL;
      brick.time      = time;
      brick.isForming = false;
      brick.spread    = spread;  // V3.0.1 BUG FIX: Armazena spread histórico
      
      // Adiciona ao array
      PushBrick(brick);
      
      // Atualiza estado
      m_state.prevClose = brick.close;
      m_state.prevDir   = MKS_BULL;
      m_state.wickHigh  = brick.close;
      m_state.wickLow   = brick.close;
   }
   
   // Cria brick bearish completado
   void MakeBear(double openP, double closeP, datetime time, int spread = 0)
   {
      MKSRenkoBrick brick;
      
      // Normaliza preços
      brick.open  = NormalizeDouble(openP, m_digits);
      brick.close = NormalizeDouble(closeP, m_digits);
      
      // Calcula high/low com ou sem wicks
      if(m_showWicks)
      {
         brick.high = NormalizeDouble(MathMax(openP, m_state.wickHigh), m_digits);
         brick.low  = NormalizeDouble(MathMin(closeP, m_state.wickLow), m_digits);
      }
      else
      {
         brick.high = brick.open;
         brick.low  = brick.close;
      }
      
      brick.direction = MKS_BEAR;
      brick.time      = time;
      brick.isForming = false;
      brick.spread    = spread;  // V3.0.1 BUG FIX: Armazena spread histórico
      
      // Adiciona ao array
      PushBrick(brick);
      
      // Atualiza estado
      m_state.prevClose = brick.close;
      m_state.prevDir   = MKS_BEAR;
      m_state.wickHigh  = brick.close;
      m_state.wickLow   = brick.close;
   }
   
   // Atualiza estado do brick em formação
   void UpdateForming(double price, datetime time)
   {
      double C = m_state.prevClose;
      
      // Se ainda não tem prevClose, não há forming brick
      if(C == 0.0)
         return;
      
      // Determina direção e open do forming brick
      double formOpen = 0.0;
      ENUM_MKS_DIRECTION formDir = MKS_NONE;
      
      if(price >= C)
      {
         // Forming brick bullish
         formDir = MKS_BULL;
         
         // Calcula open baseado na direção anterior
         if(m_state.prevDir == MKS_BEAR)
            formOpen = C - m_pRO * m_revSz;  // Reversão
         else if(m_state.prevDir == MKS_BULL)
            formOpen = C - m_pO * m_sz;      // Continuação
         else
            formOpen = C;                     // Primeiro brick
      }
      else
      {
         // Forming brick bearish
         formDir = MKS_BEAR;
         
         // Calcula open baseado na direção anterior
         if(m_state.prevDir == MKS_BULL)
            formOpen = C + m_pRO * m_revSz;  // Reversão
         else if(m_state.prevDir == MKS_BEAR)
            formOpen = C + m_pO * m_sz;      // Continuação
         else
            formOpen = C;                     // Primeiro brick
      }
      
      formOpen = NormalizeDouble(formOpen, m_digits);
      
      // Atualiza estado do forming brick
      m_state.formOpen  = formOpen;
      m_state.formClose = price;
      m_state.formDir   = formDir;
      
      // Calcula body high/low
      double bodyHigh = MathMax(formOpen, price);
      double bodyLow  = MathMin(formOpen, price);
      
      // Adiciona wicks se habilitado
      if(m_showWicks)
      {
         m_state.formHigh = NormalizeDouble(MathMax(bodyHigh, m_state.wickHigh), m_digits);
         m_state.formLow  = NormalizeDouble(MathMin(bodyLow, m_state.wickLow), m_digits);
      }
      else
      {
         m_state.formHigh = NormalizeDouble(bodyHigh, m_digits);
         m_state.formLow  = NormalizeDouble(bodyLow, m_digits);
      }
   }

public:
   //=================================================================
   // 2.4 - CONSTRUTOR E DESTRUTOR
   //=================================================================
   
   // Construtor
   CMKSRenkoCore()
   {
      m_sz = 0.0;
      m_revSz = 0.0;
      m_digits = 0;
      m_pO = 0.0;
      m_pRO = 0.0;
      m_showWicks = true;
      m_initialized = false;
      m_trackPerformance = true;
      ArrayFree(m_bricks);
      m_metrics.Reset();
   }
   
   //=================================================================
   // 2.5 - INICIALIZAÇÃO E CONFIGURAÇÃO
   //=================================================================
   
   // Inicializa Core com configuração
   bool Init(MKSRenkoConfig &cfg, double sz, int digits, MKSError &error)
   {
      // Valida brick size
      if(sz <= 0.0)
      {
         error.Set(MKS_ERROR_INVALID_BRICK_SIZE, "Brick size deve ser > 0",
                  StringFormat("sz=%.6f", sz));
         return false;
      }
      
      // Valida digits
      if(digits < 0)
      {
         error.Set(MKS_ERROR_INVALID_CONFIG, "Digits deve ser >= 0",
                  StringFormat("digits=%d", digits));
         return false;
      }
      
      // Valida configuração
      string validationError = "";
      if(!cfg.Validate(validationError))
      {
         error.Set(MKS_ERROR_INVALID_CONFIG, validationError, "Config validation failed");
         return false;
      }
      
      // Salva configuração
      m_config = cfg;
      m_sz = NormalizeDouble(sz, digits);
      m_digits = digits;
      m_showWicks = cfg.showWicks;
      
      // Valida sz normalizado
      if(m_sz <= 0.0)
      {
         error.Set(MKS_ERROR_INVALID_BRICK_SIZE, "sz=0 após normalização",
                  StringFormat("original=%.6f digits=%d", sz, digits));
         return false;
      }
      
      // Calcula reversal size
      double revPct = cfg.revSizePct;
      if(revPct <= 0.0) revPct = 100.0;
      m_revSz = NormalizeDouble(m_sz * revPct / 100.0, digits);
      if(m_revSz <= 0.0) m_revSz = m_sz;
      
      // Calcula percentuais de abertura
      m_pO = MKS_PO(cfg);
      m_pRO = MKS_PRO(cfg);
      
      // Reseta estado
      Reset();
      
      // Marca como inicializado
      m_initialized = true;
      
      // Log de sucesso
      CLogger::Info("Core", StringFormat("v3.0 Init OK | sz=%.6f | revSz=%.6f | pO=%.2f | pRO=%.2f | digits=%d",
                                        m_sz, m_revSz, m_pO, m_pRO, m_digits));
      
      return true;
   }
   
   // Reseta estado (limpa bricks, mas mantém configuração)
   void Reset()
   {
      ArrayFree(m_bricks);
      ArrayResize(m_bricks, 0, 1024);  // Pre-aloca 1024 slots
      
      m_state.prevClose  = 0.0;
      m_state.prevDir    = MKS_NONE;
      m_state.wickHigh   = 0.0;
      m_state.wickLow    = 0.0;
      m_state.count      = 0;
      m_state.formOpen   = 0.0;
      m_state.formHigh   = 0.0;
      m_state.formLow    = 0.0;
      m_state.formClose  = 0.0;
      m_state.formDir    = MKS_NONE;
      
      m_metrics.Reset();
   }
   
   // Habilita/desabilita tracking de performance
   void SetPerformanceTracking(bool enable)
   {
      m_trackPerformance = enable;
   }
   
   // Atualiza brick size dinamicamente (SEM resetar estado)
   bool UpdateBrickSize(double newSz, MKSError &error)
   {
      if(newSz <= 0.0)
      {
         error.Set(MKS_ERROR_INVALID_BRICK_SIZE, "Novo brick size inválido",
                  StringFormat("newSz=%.6f", newSz));
         return false;
      }
      
      m_sz = NormalizeDouble(newSz, m_digits);
      
      if(m_sz <= 0.0)
      {
         error.Set(MKS_ERROR_INVALID_BRICK_SIZE, "sz=0 após normalização",
                  StringFormat("original=%.6f digits=%d", newSz, m_digits));
         return false;
      }
      
      // Recalcula reversal size
      double revPct = m_config.revSizePct;
      if(revPct <= 0.0) revPct = 100.0;
      m_revSz = NormalizeDouble(m_sz * revPct / 100.0, m_digits);
      if(m_revSz <= 0.0) m_revSz = m_sz;
      
      CLogger::Debug("Core", StringFormat("BrickSize atualizado: %.6f → %.6f", BrickSize(), m_sz));
      
      return true;
   }
   
   //=================================================================
   // 2.6 - PROCESSAMENTO DE PREÇO (CORE DO ALGORITMO RENKO)
   //=================================================================
   
   // Processa um preço e retorna número de bricks gerados
   int ProcessPrice(double price, datetime time, int spread = 0)
   {
      // Valida inicialização
      if(!m_initialized)
         return 0;
      
      // Inicia timer de performance (se habilitado)
      uint startTimeUs = 0;
      if(m_trackPerformance)
         startTimeUs = (uint)GetMicrosecondCount();  // Cast explícito ulong → uint
      
      // Normaliza preço
      price = NormalizeDouble(price, m_digits);
      
      // Incrementa contador de preços processados
      m_metrics.totalPricesProcessed++;
      m_metrics.lastProcessTime = time;
      
      // Se é o primeiro preço, inicializa estado
      if(m_state.prevDir == MKS_NONE && m_state.prevClose == 0.0)
      {
         m_state.prevClose = price;
         m_state.wickHigh  = price;
         m_state.wickLow   = price;
         UpdateForming(price, time);
         
         // Finaliza timer
         if(m_trackPerformance)
         {
            uint elapsedUs = (uint)(GetMicrosecondCount() - startTimeUs);  // Cast explícito
            m_metrics.totalProcessCalls++;
            m_metrics.avgProcessTimeUs = elapsedUs;  // Primeira chamada
            m_metrics.minProcessTimeUs = elapsedUs;
            m_metrics.maxProcessTimeUs = elapsedUs;
         }
         
         return 0;
      }
      
      // Atualiza wicks acumulados
      if(price > m_state.wickHigh) m_state.wickHigh = price;
      if(price < m_state.wickLow)  m_state.wickLow  = price;
      
      // Loop de geração de bricks (pode gerar múltiplos)
      int generated = 0;
      bool newBrick = true;
      
      while(newBrick)
      {
         newBrick = false;
         double C = m_state.prevClose;
         
         //--- CASO 1: Primeiro brick (sem direção definida) ---
         if(m_state.prevDir == MKS_NONE)
         {
            // Bull?
            if(price >= C + m_sz)
            {
               MakeBull(C, C + m_sz, time, spread);
               generated++;
               newBrick = true;  // Pode gerar mais bricks
            }
            // Bear?
            else if(price <= C - m_sz)
            {
               MakeBear(C, C - m_sz, time, spread);
               generated++;
               newBrick = true;  // Pode gerar mais bricks
            }
         }
         //--- CASO 2: Último brick foi BULL ---
         else if(m_state.prevDir == MKS_BULL)
         {
            // Continuação bull?
            if(price >= C + m_sz * (1.0 - m_pO))
            {
               double openNew  = C - m_pO * m_sz;
               double closeNew = openNew + m_sz;
               MakeBull(openNew, closeNew, time, spread);
               generated++;
               newBrick = true;
            }
            // Reversão para bear?
            else if(price <= C - m_revSz * (1.0 - m_pRO))
            {
               double openNew  = C + m_pRO * m_revSz;
               double closeNew = openNew - m_revSz;
               MakeBear(openNew, closeNew, time, spread);
               generated++;
               newBrick = true;
            }
         }
         //--- CASO 3: Último brick foi BEAR ---
         else if(m_state.prevDir == MKS_BEAR)
         {
            // Continuação bear?
            if(price <= C - m_sz * (1.0 - m_pO))
            {
               double openNew  = C + m_pO * m_sz;
               double closeNew = openNew - m_sz;
               MakeBear(openNew, closeNew, time, spread);
               generated++;
               newBrick = true;
            }
            // Reversão para bull?
            else if(price >= C + m_revSz * (1.0 - m_pRO))
            {
               double openNew  = C - m_pRO * m_revSz;
               double closeNew = openNew + m_revSz;
               MakeBull(openNew, closeNew, time, spread);
               generated++;
               newBrick = true;
            }
         }
      }
      
      // Atualiza wicks após geração de bricks
      if(price > m_state.wickHigh) m_state.wickHigh = price;
      if(price < m_state.wickLow)  m_state.wickLow  = price;
      
      // Atualiza forming brick
      UpdateForming(price, time);
      
      // Finaliza timer de performance
      if(m_trackPerformance)
      {
         uint elapsedUs = (uint)(GetMicrosecondCount() - startTimeUs);  // Cast explícito
         m_metrics.totalProcessCalls++;
         
         // Atualiza média (running average)
         if(m_metrics.totalProcessCalls > 1)
         {
            m_metrics.avgProcessTimeUs = (uint)(
               ((double)m_metrics.avgProcessTimeUs * (m_metrics.totalProcessCalls - 1) + elapsedUs) 
               / m_metrics.totalProcessCalls
            );
         }
         else
         {
            m_metrics.avgProcessTimeUs = elapsedUs;
         }
         
         // Atualiza min/max
         if(m_metrics.minProcessTimeUs == 0 || elapsedUs < m_metrics.minProcessTimeUs)
            m_metrics.minProcessTimeUs = elapsedUs;
         
         if(elapsedUs > m_metrics.maxProcessTimeUs)
            m_metrics.maxProcessTimeUs = elapsedUs;
         
         // Atualiza taxas calculadas (a cada 100 chamadas para não sobrecarregar)
         if(m_metrics.totalProcessCalls % 100 == 0)
            m_metrics.UpdateRates();
      }
      
      return generated;
   }
   
   //=================================================================
   // 2.7 - ACESSO A BRICKS
   //=================================================================
   
   // Retorna brick específico por índice (0-based)
   bool GetBrick(int index, MKSRenkoBrick &brick)
   {
      if(index < 0 || index >= ArraySize(m_bricks))
         return false;
      
      brick = m_bricks[index];
      return true;
   }
   
   // Retorna brick em formação
   bool GetForming(MKSRenkoBrick &brick)
   {
      if(m_state.formDir == MKS_NONE)
         return false;
      
      brick.open      = m_state.formOpen;
      brick.high      = m_state.formHigh;
      brick.low       = m_state.formLow;
      brick.close     = m_state.formClose;
      brick.direction = m_state.formDir;
      brick.time      = 0;  // Forming bricks não têm tempo definido
      brick.isForming = true;
      
      return true;
   }
   
   // Copia range de bricks para array destino
   int CopyBricks(MKSRenkoBrick &dest[], int start, int count)
   {
      int total = ArraySize(m_bricks);
      
      // Valida parâmetros
      if(start < 0) start = 0;
      if(start >= total) return 0;
      if(count <= 0) return 0;
      
      // Ajusta count se ultrapassar disponível
      int available = total - start;
      if(count > available) count = available;
      
      // Redimensiona destino
      ArrayResize(dest, count);
      
      // Copia bricks
      for(int i = 0; i < count; i++)
         dest[i] = m_bricks[start + i];
      
      return count;
   }
   
   // Retorna total de bricks completados
   int Count()
   {
      return m_state.count;
   }
   
   // Retorna brick size atual
   double BrickSize()
   {
      return m_sz;
   }
   
   // Retorna reversal size atual
   double ReversalSize()
   {
      return m_revSz;
   }
   
   // Copia estado interno
   void GetState(MKSRenkoState &outState)
   {
      outState = m_state;
   }
   
   // Define estado de sincronização (usado pelo LiveEngine)
   void SetSyncState(double prevClose, ENUM_MKS_DIRECTION prevDir)
   {
      m_state.prevClose = prevClose;
      m_state.prevDir   = prevDir;
      m_state.wickHigh  = prevClose;
      m_state.wickLow   = prevClose;
      
      CLogger::Debug("Core", StringFormat("SyncState set | prevClose=%.6f | prevDir=%d",
                                         prevClose, prevDir));
   }
   
   //=================================================================
   // 2.8 - MÉTRICAS E DIAGNÓSTICO
   //=================================================================
   
   // Retorna métricas de performance
   void GetMetrics(MKSCoreMetrics &metrics)
   {
      m_metrics.UpdateRates();  // Atualiza antes de retornar
      metrics = m_metrics;
   }
   
   // Imprime relatório de performance
   void PrintPerformanceReport()
   {
      m_metrics.UpdateRates();
      
      Print("========================================");
      Print("CORE PERFORMANCE REPORT");
      Print("========================================");
      Print("Total Process Calls: ", m_metrics.totalProcessCalls);
      Print("Total Prices Processed: ", m_metrics.totalPricesProcessed);
      Print("Total Bricks Generated: ", m_metrics.totalBricksGenerated);
      Print("  - Bull Bricks: ", m_metrics.bullBricks);
      Print("  - Bear Bricks: ", m_metrics.bearBricks);
      Print("  - Reversals: ", m_metrics.reversalCount);
      Print("----------------------------------------");
      Print("Avg Process Time: ", m_metrics.avgProcessTimeUs, " μs");
      Print("Min Process Time: ", m_metrics.minProcessTimeUs, " μs");
      Print("Max Process Time: ", m_metrics.maxProcessTimeUs, " μs");
      Print("----------------------------------------");
      Print("Bricks Per Second: ", DoubleToString(m_metrics.bricksPerSecond, 2));
      Print("Avg Bricks Per Call: ", DoubleToString(m_metrics.avgBricksPerCall, 2));
      Print("========================================");
   }
   
   // Imprime configuração atual
   void PrintConfiguration()
   {
      Print("========================================");
      Print("CORE CONFIGURATION");
      Print("========================================");
      Print("Initialized: ", m_initialized ? "YES" : "NO");
      Print("Brick Size: ", DoubleToString(m_sz, m_digits));
      Print("Reversal Size: ", DoubleToString(m_revSz, m_digits));
      Print("Digits: ", m_digits);
      Print("PO (Continuation %): ", DoubleToString(m_pO * 100, 1), "%");
      Print("PRO (Reversal %): ", DoubleToString(m_pRO * 100, 1), "%");
      Print("Show Wicks: ", m_showWicks ? "YES" : "NO");
      Print("Performance Tracking: ", m_trackPerformance ? "ON" : "OFF");
      Print("----------------------------------------");
      Print("Preset: ", EnumToString(m_config.preset));
      Print("Size Mode: ", EnumToString(m_config.sizeMode));
      Print("Data Source: ", EnumToString(m_config.dataSource));
      Print("========================================");
   }
};

#endif