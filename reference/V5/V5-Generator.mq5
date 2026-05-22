//+------------------------------------------------------------------+
//| MKS-Renko-Generator.mq5                                          |
//| MKS Framework - V5.0 Research Engine                             |
//| Descricao: Gerador de historico Renko via Custom Symbols         |
//| Instalacao: MQL5/Scripts/MKS-V5.0/                               |
//| Build: V5.0 (2026-04-11)                                         |
//+------------------------------------------------------------------+

#property copyright   "MKS Framework"
#property version     "3.20"
#property description "Generator v3.2 - Progress Panel + Paginacao + ATR + Naming"
#property script_show_inputs

#include <MKS-V5.0/Core/MKS-Renko-Types.mqh>
#include <MKS-V5.0/Core/MKS-Renko-Core.mqh>
#include <MKS-V5.0/Core/Logger.mqh>
#include <MKS-V5.0/UI/ProgressPanel.mqh>

//=====================================================================
// SEÇÃO 1: INPUTS DO SCRIPT
//=====================================================================

// 1.1 - Configuração básica
input string InpSymbol        = "";                  // Símbolo base (vazio = chart atual)
input ENUM_MKS_PRESET InpPreset = MKS_PRESET_MEDIAN; // Preset Renko
input double InpBrickSize     = 3.0;                 // Tamanho do brick
input ENUM_MKS_SIZE_MODE InpSizeMode = MKS_SIZE_PRICE; // Modo de tamanho

// 1.2 - Configuração de reversão (apenas se Custom)
input double InpOpenPct       = 0.50;                // % Abertura continuação
input double InpRevOpenPct    = 0.50;                // % Abertura reversão
input double InpRevSizePct    = 100.0;               // % Tamanho reversão

// 1.3 - Fonte de dados e período
input ENUM_MKS_DATA_SOURCE InpDataSource = MKS_SOURCE_TICKS; // Fonte de dados
input int    InpDays          = 30;                  // Dias de histórico

// 1.4 - Visualização
input bool   InpShowWicks     = true;                // Mostrar wicks

// 1.5 - Parâmetros ATR (se SIZE_ATR)
input int    InpAtrPeriod     = 14;                  // Período ATR
input double InpAtrFactor     = 1.5;                 // Multiplicador ATR

// 1.6 - Parâmetros PERCENT (se SIZE_PERCENT)
input double InpPercentFactor = 0.5;                 // Fator %

//=====================================================================
// SEÇÃO 2: VARIÁVEIS GLOBAIS
//=====================================================================

// 2.1 - Handle ATR persistente (se modo ATR)
int g_atrHandle = INVALID_HANDLE;

// 2.2 - Painel de progresso visual
CProgressPanel g_progressPanel;

//=====================================================================
// SEÇÃO 3: FUNÇÕES AUXILIARES
//=====================================================================

// 3.1 - Cria ou limpa Custom Symbol
bool CreateOrCleanCustomSymbol(string csName, string baseSymbol)
{
   CLogger::Enter("Generator", "CreateOrCleanCustomSymbol");
   
   bool isCustom = false;
   
   // Verifica se CS já existe
   if(SymbolExist(csName, isCustom))
   {
      CLogger::Info("Generator", StringFormat("CS %s existe - limpando dados", csName));
      
      // Remove todos os rates existentes
      int deleted = CustomRatesDelete(csName, 0, D'2099.12.31');
      CLogger::Info("Generator", StringFormat("%d rates removidos", deleted));
      
      // Configura sessões 24/7
      for(int day = 0; day < 7; day++)
      {
         CustomSymbolSetSessionTrade(csName, (ENUM_DAY_OF_WEEK)day, 0, 0, 86400);
         CustomSymbolSetSessionQuote(csName, (ENUM_DAY_OF_WEEK)day, 0, 0, 86400);
      }
      
      // Seleciona símbolo
      SymbolSelect(csName, true);
      
      CLogger::Exit("Generator", "CreateOrCleanCustomSymbol");
      return true;
   }
   
   // Cria novo Custom Symbol
   CLogger::Info("Generator", StringFormat("Criando novo CS: %s", csName));
   
   if(!CustomSymbolCreate(csName, "MKS", baseSymbol))
   {
      CLogger::Error("Generator", StringFormat("CustomSymbolCreate falhou - erro %d", GetLastError()));
      return false;
   }
   
   // Define descrição
   CustomSymbolSetString(csName, SYMBOL_DESCRIPTION, "MKS Renko - " + baseSymbol);
   
   // Configura sessões 24/7
   for(int day = 0; day < 7; day++)
   {
      CustomSymbolSetSessionTrade(csName, (ENUM_DAY_OF_WEEK)day, 0, 0, 86400);
      CustomSymbolSetSessionQuote(csName, (ENUM_DAY_OF_WEEK)day, 0, 0, 86400);
   }
   
   // Seleciona símbolo
   SymbolSelect(csName, true);
   
   CLogger::Info("Generator", StringFormat("CS criado: %s (base: %s)", csName, baseSymbol));
   CLogger::Exit("Generator", "CreateOrCleanCustomSymbol");
   
   return true;
}

// 3.2 - Preenche MqlRates com dados do brick (V3: real_volume = brick.time)
void MKS_FillRate(MqlRates &rate, MKSRenkoBrick &brick, datetime timestamp, string symbol)
{
   // Timestamp e OHLC
   rate.time  = timestamp;
   rate.open  = brick.open;
   rate.high  = brick.high;
   rate.low   = brick.low;
   rate.close = brick.close;
   
   // tick_volume variável baseado no range
   double range = brick.high - brick.low;
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickSize > 0.0)
      rate.tick_volume = (long)MathMax(4, range / tickSize);
   else
      rate.tick_volume = 4;
   
   // V3.0.1 BUG FIX: Usa spread armazenado no brick (histórico)
   rate.spread = brick.spread;
   
   // V3 CRÍTICO: real_volume armazena o timestamp REAL do brick
   rate.real_volume = (long)brick.time;
}

//=====================================================================
// SEÇÃO 4: PROCESSAMENTO DE DADOS
//=====================================================================

// 4.1 - Processa ticks com paginação segura (chunks de 1 DIA)
int ProcessTicks(string symbol, datetime from, datetime to, CMKSRenkoCore &core, 
                 MKSRenkoConfig &cfg, int &outDaysFound)
{
   CLogger::Enter("Generator", "ProcessTicks");
   
   int totalProcessed = 0;
   int totalDays = 0;
   
   datetime currentDay = from - (from % 86400);
   
   CLogger::Info("Generator", "Processando ticks em chunks de 1 dia (Proteção de RAM)");
   
   while(currentDay < to)
   {
      datetime nextDay = currentDay + 86400;
      datetime chunkEnd = (nextDay > to) ? to : nextDay;
      
      ulong fromMsc = (ulong)currentDay * 1000;
      ulong toMsc = (ulong)chunkEnd * 1000 - 1;
      
      MqlTick ticks[];
      int copied = CopyTicksRange(symbol, ticks, COPY_TICKS_ALL, fromMsc, toMsc);
      
      if(copied > 0)
      {
         totalDays++;
         
         CLogger::Info("Generator", StringFormat("Chunk %s | %d ticks em memória",
                                                 TimeToString(currentDay, TIME_DATE), copied));
         
         datetime lastRecalcDate = 0;
         
         for(int i = 0; i < copied; i++)
         {
            double price = (ticks[i].last > 0.0) ? ticks[i].last : ticks[i].bid;
            if(price <= 0.0) continue;
            
            // Lógica do ATR Dinâmico
            if(cfg.sizeMode == MKS_SIZE_ATR && g_atrHandle != INVALID_HANDLE)
            {
               datetime tickDate = ticks[i].time - (ticks[i].time % 86400);
               
               if(tickDate != lastRecalcDate)
               {
                  int shift = iBarShift(symbol, PERIOD_D1, tickDate);
                  
                  if(shift >= 0)
                  {
                     double atrBuf[];
                     if(CopyBuffer(g_atrHandle, 0, shift, 1, atrBuf) > 0)
                     {
                        double newSz = cfg.atrFactor * atrBuf[0];
                        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
                        newSz = NormalizeDouble(newSz, digits);
                        
                        if(newSz > 0.0)
                        {
                           MKSError error;
                           core.UpdateBrickSize(newSz, error);
                        }
                     }
                  }
                  lastRecalcDate = tickDate;
               }
            }
            
            // Spread real histórico
            double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
            int spread = 0;
            if(tickSize > 0 && ticks[i].ask > 0 && ticks[i].bid > 0)
               spread = (int)MathRound((ticks[i].ask - ticks[i].bid) / tickSize);
            
            core.ProcessPrice(price, ticks[i].time, spread);
            totalProcessed++;
            
            if(totalProcessed % 500000 == 0)
            {
               double elapsed = (double)(currentDay - from);
               double total = (double)(to - from);
               double pct = 30.0 + (elapsed / total * 40.0); 
               g_progressPanel.UpdateStatus("Processando ticks (XAUUSD Heavy Data)...", pct, totalProcessed, 0);
            }
         }
         
         ArrayFree(ticks); 
      }
      else
      {
         CLogger::Warn("Generator", StringFormat("Chunk %s: sem ticks (fim de semana ou sem liquidez)",
                                                 TimeToString(currentDay, TIME_DATE)));
      }
      
      currentDay = nextDay; 
   }
   
   outDaysFound = totalDays;
   
   CLogger::Info("Generator", StringFormat("TOTAL: %d ticks processados em %d dias uteis", totalProcessed, totalDays));
   CLogger::Exit("Generator", "ProcessTicks");
   
   return totalProcessed;
}

// 4.2 - Processa barras M1
int ProcessM1(string symbol, datetime from, datetime to, CMKSRenkoCore &core)
{
   CLogger::Enter("Generator", "ProcessM1");
   
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   
   int copied = CopyRates(symbol, PERIOD_M1, from, to, rates);
   
   if(copied <= 0)
   {
      CLogger::Error("Generator", StringFormat("Sem barras M1 para %s", symbol));
      return -1;
   }
   
   CLogger::Info("Generator", StringFormat("%d barras M1 carregadas", copied));
   
   int processed = 0;
   
   for(int i = 0; i < copied; i++)
   {
      datetime t = rates[i].time;
      
      if(rates[i].close >= rates[i].open)
      {
         core.ProcessPrice(rates[i].open,  t);
         core.ProcessPrice(rates[i].low,   t);
         core.ProcessPrice(rates[i].high,  t);
         core.ProcessPrice(rates[i].close, t);
      }
      else
      {
         core.ProcessPrice(rates[i].open,  t);
         core.ProcessPrice(rates[i].high,  t);
         core.ProcessPrice(rates[i].low,   t);
         core.ProcessPrice(rates[i].close, t);
      }
      
      processed += 4;
      
      if(i > 0 && i % 10000 == 0)
      {
         CLogger::Debug("Generator", StringFormat("M1: %d/%d (%.1f%%)", 
                                                  i, copied, i * 100.0 / copied));
         
         double pct = 30.0 + ((double)i / copied * 40.0);
         g_progressPanel.UpdateStatus("Processando barras M1...", pct, i, copied);
      }
   }
   
   CLogger::Info("Generator", StringFormat("M1 processadas: %d | preços: %d", copied, processed));
   CLogger::Exit("Generator", "ProcessM1");
   
   return processed;
}

// 4.3 - Carrega e processa dados (ticks ou M1)
int LoadAndProcess(string symbol, MKSRenkoConfig &cfg, CMKSRenkoCore &core)
{
   CLogger::Enter("Generator", "LoadAndProcess");
   
   datetime to   = TimeCurrent();
   datetime from = (cfg.days > 0) ? to - cfg.days * 86400 : D'2000.01.01';
   
   int requestedDays = (cfg.days > 0) ? cfg.days : 3650;
   
   if(cfg.dataSource == MKS_SOURCE_TICKS)
   {
      int daysFound = 0;
      int tickCount = ProcessTicks(symbol, from, to, core, cfg, daysFound);
      
      if(tickCount > 0 && daysFound >= requestedDays / 2)
      {
         CLogger::Info("Generator", StringFormat("Ticks cobrem %d/%d dias - usando ticks",
                                                 daysFound, requestedDays));
         CLogger::Exit("Generator", "LoadAndProcess");
         return tickCount;
      }
      
      if(tickCount > 0)
      {
         CLogger::Warn("Generator", StringFormat("Ticks cobrem apenas %d/%d dias - fallback M1",
                                                 daysFound, requestedDays));
         core.Reset();
      }
      else
      {
         CLogger::Warn("Generator", "Sem ticks disponíveis - fallback M1");
      }
   }
   
   int result = ProcessM1(symbol, from, to, core);
   CLogger::Exit("Generator", "LoadAndProcess");
   
   return result;
}

//=====================================================================
// SEÇÃO 5: PUBLICAÇÃO DE BRICKS
//=====================================================================

// 5.1 - Publica bricks no Custom Symbol
int PublishBricks(string csName, CMKSRenkoCore &core, string symbol)
{
   CLogger::Enter("Generator", "PublishBricks");
   
   int total = core.Count();
   
   if(total <= 0)
   {
      CLogger::Warn("Generator", "Nenhum brick gerado");
      return 0;
   }
   
   CLogger::Info("Generator", StringFormat("Preparando %d bricks para publicação", total));
   
   // Prepara array de rates
   MqlRates rates[];
   ArrayResize(rates, total, 1024);
   
   MKSRenkoBrick brick;
   datetime prevTime = 0;
   
   // Converte bricks para MqlRates
   for(int i = 0; i < total; i++)
   {
      if(!core.GetBrick(i, brick))
         continue;
      
      datetime newTime = brick.time;
      
      // Garante intervalo mínimo de 60 segundos entre bricks
      if(i > 0 && newTime - prevTime < 60)
         newTime = prevTime + 60;
      
      prevTime = newTime;
      
      // Preenche rate (V3: real_volume = brick.time)
      MKS_FillRate(rates[i], brick, newTime, symbol);
   }
   
   // Publica em batches de 5000
   int published = 0;
   int batchSize = 5000;
   
   for(int start = 0; start < total; start += batchSize)
   {
      int count = MathMin(batchSize, total - start);
      
      MqlRates batch[];
      ArrayResize(batch, count);
      for(int j = 0; j < count; j++)
         batch[j] = rates[start + j];
      
      int result = CustomRatesUpdate(csName, batch);
      
      if(result > 0)
      {
         published += result;
      }
      else
      {
         CLogger::Error("Generator", StringFormat("Lote %d falhou - erro %d",
                                                  start / batchSize + 1, GetLastError()));
         break;
      }
      
      if((start / batchSize) % 10 == 0 && start > 0)
      {
         CLogger::Debug("Generator", StringFormat("Lotes: %d/%d (%.1f%%)",
                                                  start / batchSize,
                                                  (total / batchSize) + 1,
                                                  ((double)start / total) * 100.0));
         
         double pct = 70.0 + ((double)published / total * 25.0);
         g_progressPanel.UpdateStatus("Publicando bricks no Custom Symbol...", pct, published, total);
      }
   }
   
   CLogger::Info("Generator", StringFormat("Publicados %d/%d rates em %s", 
                                           published, total, csName));
   CLogger::Exit("Generator", "PublishBricks");
   
   return published;
}

//=====================================================================
// SEÇÃO 6: ABERTURA DE GRÁFICO
//=====================================================================

// 6.1 - Abre gráfico do Custom Symbol
void OpenCustomChart(string csName)
{
   CLogger::Enter("Generator", "OpenCustomChart");
   
   long chartId = ChartOpen(csName, PERIOD_M1);
   
   if(chartId > 0)
   {
      ChartSetInteger(chartId, CHART_MODE, CHART_CANDLES);
      ChartSetInteger(chartId, CHART_AUTOSCROLL, true);
      ChartSetInteger(chartId, CHART_SHIFT, true);
      ChartRedraw(chartId);
      
      CLogger::Info("Generator", StringFormat("Gráfico aberto: %s (ID: %d)", csName, chartId));
   }
   else
   {
      CLogger::Warn("Generator", "Falha ao abrir gráfico");
   }
   
   CLogger::Exit("Generator", "OpenCustomChart");
}

//=====================================================================
// SEÇÃO 7: FUNÇÃO PRINCIPAL
//=====================================================================

// 7.1 - OnStart (entrada do script)
void OnStart()
{
   uint startMs = GetTickCount();
   
   g_progressPanel.Init(ChartID(), 20, 50);
   g_progressPanel.UpdateStatus("Inicializando Generator...", 0);
   
   CLogger::Init(LOG_LEVEL_INFO, true, "MKS_Generator.log");
   
   Print("========================================");
   Print("MKS GENERATOR v3.2 INICIANDO");
   Print("========================================");
   
   //=================================================================
   // 7.2 - VALIDAÇÃO DE SÍMBOLO BASE
   //=================================================================
   
   string symbol = (InpSymbol == "" || InpSymbol == NULL) ? Symbol() : InpSymbol;
   
   if(!SymbolSelect(symbol, true))
   {
      g_progressPanel.ShowError(StringFormat("Símbolo %s não encontrado", symbol));
      CLogger::Fatal("Generator", StringFormat("Símbolo %s não encontrado", symbol));
      Sleep(3000);
      g_progressPanel.Clear();
      return;
   }
   
   CLogger::Info("Generator", StringFormat("Símbolo base: %s", symbol));
   g_progressPanel.UpdateStatus("Símbolo validado: " + symbol, 5);
   
   //=================================================================
   // 7.3 - CRIAÇÃO DA CONFIGURAÇÃO
   //=================================================================
   
   MKSRenkoConfig cfg;
   cfg.version        = 3;
   cfg.preset         = InpPreset;
   cfg.brickSize      = InpBrickSize;
   cfg.sizeMode       = InpSizeMode;
   cfg.openPct        = InpOpenPct;
   cfg.revOpenPct     = InpRevOpenPct;
   cfg.revSizePct     = InpRevSizePct;
   cfg.dataSource     = InpDataSource;
   cfg.days           = InpDays;
   cfg.showWicks      = InpShowWicks;
   cfg.atrPeriod      = InpAtrPeriod;
   cfg.atrFactor      = InpAtrFactor;
   cfg.percentFactor  = InpPercentFactor;
   
   string validationError = "";
   if(!cfg.Validate(validationError))
   {
      g_progressPanel.ShowError("Config inválida: " + validationError);
      CLogger::Fatal("Generator", StringFormat("Configuração inválida: %s", validationError));
      Sleep(3000);
      g_progressPanel.Clear();
      return;
   }
   
   CLogger::Info("Generator", StringFormat("Config: preset=%s | size=%.2f | mode=%s | days=%d",
                                           EnumToString(cfg.preset),
                                           cfg.brickSize,
                                           EnumToString(cfg.sizeMode),
                                           cfg.days));
   
   g_progressPanel.UpdateStatus("Configuração validada", 10);
   
   //=================================================================
   // 7.4 - CRIAÇÃO DO CUSTOM SYMBOL
   //=================================================================
   
   string csName = MKS_SymbolName(symbol, cfg);
   
   CLogger::Info("Generator", StringFormat("Custom Symbol: %s", csName));
   
   g_progressPanel.UpdateStatus("Preparando Custom Symbol...", 15);
   
   if(!CreateOrCleanCustomSymbol(csName, symbol))
   {
      g_progressPanel.ShowError("Falha ao preparar Custom Symbol");
      CLogger::Fatal("Generator", "Falha ao preparar Custom Symbol");
      Sleep(3000);
      g_progressPanel.Clear();
      return;
   }
   
   g_progressPanel.UpdateStatus("Custom Symbol pronto: " + csName, 20);
   
   //=================================================================
   // 7.5 - CÁLCULO DE BRICK SIZE E CRIAÇÃO DO CORE
   //=================================================================
   
   if(cfg.sizeMode == MKS_SIZE_ATR)
   {
      g_atrHandle = iATR(symbol, PERIOD_D1, cfg.atrPeriod);
      
      if(g_atrHandle == INVALID_HANDLE)
      {
         CLogger::Fatal("Generator", "Falha ao criar ATR handle");
         return;
      }
      
      CLogger::Info("Generator", StringFormat("ATR handle criado - handle=%d", g_atrHandle));
   }
   
   MKSError error;
   double sz = MKS_CalcBrickSize(symbol, cfg, error);
   
   if(sz <= 0.0 || error.HasError())
   {
      CLogger::Fatal("Generator", StringFormat("Brick size inválido: %s", error.ToString()));
      
      if(g_atrHandle != INVALID_HANDLE)
         IndicatorRelease(g_atrHandle);
      
      return;
   }
   
   CLogger::Info("Generator", StringFormat("Brick size calculado: %.6f", sz));
   
   g_progressPanel.UpdateStatus("Brick size calculado", 25);
   
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   
   CMKSRenkoCore core;
   
   if(!core.Init(cfg, sz, digits, error))
   {
      CLogger::Fatal("Generator", StringFormat("Core.Init falhou: %s", error.ToString()));
      
      if(g_atrHandle != INVALID_HANDLE)
         IndicatorRelease(g_atrHandle);
      
      return;
   }
   
   //=================================================================
   // 7.6 - PROCESSAMENTO DE DADOS
   //=================================================================
   
   g_progressPanel.UpdateStatus("Iniciando processamento de dados...", 30);
   
   int totalProcessed = LoadAndProcess(symbol, cfg, core);
   
   if(g_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandle);
      g_atrHandle = INVALID_HANDLE;
      CLogger::Info("Generator", "ATR handle liberado");
   }
   
   if(totalProcessed < 0)
   {
      CLogger::Fatal("Generator", "LoadAndProcess falhou");
      return;
   }
   
   //=================================================================
   // 7.7 - PUBLICAÇÃO E FINALIZAÇÃO
   //=================================================================
   
   g_progressPanel.UpdateStatus("Publicando bricks...", 70, 0, core.Count());
   
   int published = PublishBricks(csName, core, symbol);
   
   if(published <= 0)
   {
      CLogger::Error("Generator", "Nenhum brick publicado");
      return;
   }
   
   g_progressPanel.UpdateStatus("Abrindo gráfico...", 95);
   OpenCustomChart(csName);
   
   g_progressPanel.Finish(StringFormat("Completo! %d bricks gerados", published));
   Sleep(3000);
   g_progressPanel.Clear();
   
   // Relatório final
   uint elapsed = GetTickCount() - startMs;
   
   Print("========================================");
   Print("MKS GENERATOR v3.2 COMPLETO");
   Print("========================================");
   Print("Custom Symbol  : ", csName);
   Print("Ativo base     : ", symbol);
   Print("Brick Size     : ", DoubleToString(sz, digits));
   Print("Preset         : ", EnumToString(cfg.preset), " | PO=", DoubleToString(MKS_PO(cfg)*100, 0), "% | PRO=", DoubleToString(MKS_PRO(cfg)*100, 0), "%");
   Print("Show Wicks     : ", cfg.showWicks ? "TRUE" : "FALSE");
   Print("Preços proc.   : ", totalProcessed);
   Print("Bricks gerados : ", core.Count());
   Print("Rates publicados: ", published);
   Print("Tempo total    : ", elapsed, " ms (", DoubleToString(elapsed / 1000.0, 1), " seg)");
   Print("========================================");
   
   //--- DIAGNOSTICO
   Print("");
   Print("============ DIAGNOSTICO RENKO ============");
   Print("Tipo esperado: ", (MKS_PO(cfg) > 0.01) ? "MEDIAN RENKO (PO>0)" : "NORMAL RENKO (PO=0)");
   PrintFormat("PO  = %.4f (%.0f%%)", MKS_PO(cfg), MKS_PO(cfg)*100);
   PrintFormat("PRO = %.4f (%.0f%%)", MKS_PRO(cfg), MKS_PRO(cfg)*100);
   PrintFormat("Wicks = %s", cfg.showWicks ? "ON" : "OFF");
   Print("");
   
   int diagCount = MathMin(core.Count(), 10);
   Print("--- Primeiros ", diagCount, " bricks ---");
   
   MKSRenkoBrick diagBrick;
   double prevClose = 0;
   
   for(int d = 0; d < diagCount; d++)
   {
      if(!core.GetBrick(d, diagBrick)) continue;
      
      string dir = (diagBrick.close > diagBrick.open) ? "BULL" : "BEAR";
      bool hasWick = (diagBrick.high != MathMax(diagBrick.open, diagBrick.close)) ||
                     (diagBrick.low  != MathMin(diagBrick.open, diagBrick.close));
      
      string overlapStr = "";
      if(d > 0 && prevClose > 0)
      {
         double gap = MathAbs(diagBrick.open - prevClose);
         if(gap < 0.001)
            overlapStr = " [NORMAL: open=prevClose]";
         else
            overlapStr = StringFormat(" [MEDIAN: gap=%.2f]", gap);
      }
      
      PrintFormat("  [%d] %s O=%.2f H=%.2f L=%.2f C=%.2f %s%s",
         d, dir, diagBrick.open, diagBrick.high, diagBrick.low, diagBrick.close,
         hasWick ? "WICK!" : "noWick", overlapStr);
      
      prevClose = diagBrick.close;
   }
   Print("============================================");
   
   core.PrintPerformanceReport();
   CLogger::Info("Generator", "Execução finalizada com sucesso");
}