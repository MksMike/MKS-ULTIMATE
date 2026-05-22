//+------------------------------------------------------------------+
//| MKS-Renko-LiveEngine.mq5                                     |
//| MKS Framework - V5.0 Research Engine                             |
//| Descricao: Motor real-time de atualizacao Renko               |
//| Instalacao: MQL5/Indicators/MKS-V5.0/                          |
//| Build: V5.0 (2026-04-07)                                         |
//+------------------------------------------------------------------+

#property copyright          "MKS Framework"
#property version            "3.00"
#property description        "LiveEngine v3.0 - OnTimer + Watchdog + Gap detection"
#property indicator_chart_window
#property indicator_plots    0

#include <MKS-V5.0/Core/MKS-Renko-Types.mqh>
#include <MKS-V5.0/Core/MKS-Renko-Core.mqh>
#include <MKS-V5.0/Core/Logger.mqh>

//=====================================================================
// SEÇÃO 1: CONSTANTES
//=====================================================================

// 1.1 - Configurações de timing e segurança
#define TIMER_INTERVAL_MS 250           // 4x por segundo (Gemini fix)
#define WATCHDOG_TIMEOUT_SEC 300        // 5 minutos sem ticks = alerta
#define HEALTH_CHECK_INTERVAL_SEC 60    // Verifica CS a cada 60s
#define MAX_CONNECTION_ERRORS 10        // Erros antes de alerta
#define QUICK_HISTORY_HOURS 1           // 1 hora de histórico rápido
#define THROTTLE_MS 300                 // Throttle forming/bid-ask updates
#define GAP_DETECTION_MIN 10            // Gap > 10 minutos dispara preenchimento

//=====================================================================
// SEÇÃO 2: INPUTS
//=====================================================================

// 2.1 - Configuração básica
input string InpSymbol        = "";                  // Símbolo base (vazio = chart atual)
input ENUM_MKS_PRESET InpPreset = MKS_PRESET_MEDIAN; // Preset Renko
input double InpBrickSize     = 3.0;                 // Tamanho do brick
input ENUM_MKS_SIZE_MODE InpSizeMode = MKS_SIZE_PRICE; // Modo de tamanho

// 2.2 - Configuração de reversão (apenas se Custom)
input double InpOpenPct       = 0.50;                // % Abertura continuação
input double InpRevOpenPct    = 0.50;                // % Abertura reversão
input double InpRevSizePct    = 100.0;               // % Tamanho reversão

// 2.3 - Fonte de dados e período
input ENUM_MKS_DATA_SOURCE InpDataSource = MKS_SOURCE_TICKS; // Fonte de dados
input int    InpDays          = 30;                  // Dias de histórico

// 2.4 - Visualização
input bool   InpShowWicks     = true;                // Mostrar wicks

// 2.5 - Parâmetros ATR (se SIZE_ATR)
input int    InpAtrPeriod     = 14;                  // Período ATR
input double InpAtrFactor     = 1.5;                 // Multiplicador ATR

// 2.6 - Parâmetros PERCENT (se SIZE_PERCENT)
input double InpPercentFactor = 0.5;                 // Fator %

//=====================================================================
// SEÇÃO 3: VARIÁVEIS GLOBAIS
//=====================================================================

// 3.1 - Core e configuração
CMKSRenkoCore  g_core;
MKSRenkoConfig g_cfg;
string         g_csName       = "";
string         g_symbol       = "";
double         g_sz           = 0.0;
int            g_digits       = 0;
int            g_lastPubCount = 0;
datetime       g_lastTime     = 0;
bool           g_ready        = false;
long           g_csChartId    = 0;

// 3.2 - Watchdog e health check
datetime       g_lastTickTime        = 0;
datetime       g_lastHealthCheck     = 0;
int            g_connectionErrors    = 0;
bool           g_watchdogTriggered   = false;

// 3.3 - Performance throttling
uint           g_lastFormingMs = 0;
uint           g_lastBidAskMs  = 0;
int            g_totalPubSession = 0;
int            g_liveTicks     = 0;

// 3.4 - Visual objects
string         g_bidLineName   = "MKS_BidLine";
string         g_askLineName   = "MKS_AskLine";
string         g_statusLabel   = "MKS_StatusLabel";

//=====================================================================
// SEÇÃO 4: FUNÇÕES DE STATUS VISUAL
//=====================================================================

// 4.1 - Mostra status no canto inferior esquerdo
void ShowStatus(string text)
{
   long chart = ChartID();
   
   if(ObjectFind(chart, g_statusLabel) < 0)
   {
      ObjectCreate(chart, g_statusLabel, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(chart, g_statusLabel, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(chart, g_statusLabel, OBJPROP_XDISTANCE, 15);
      ObjectSetInteger(chart, g_statusLabel, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(chart, g_statusLabel, OBJPROP_FONTSIZE, 14);
      ObjectSetString(chart, g_statusLabel, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(chart, g_statusLabel, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(chart, g_statusLabel, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(chart, g_statusLabel, OBJPROP_HIDDEN, true);
   }
   
   ObjectSetString(chart, g_statusLabel, OBJPROP_TEXT, text);
   // ChartRedraw não é permitido em indicadores - MT5 atualiza automaticamente
}

// 4.2 - Remove status
void RemoveStatus()
{
   long chart = ChartID();
   if(ObjectFind(chart, g_statusLabel) >= 0)
   {
      ObjectDelete(chart, g_statusLabel);
      // ChartRedraw não é permitido em indicadores
   }
}

//=====================================================================
// SEÇÃO 5: CUSTOM SYMBOL MANAGEMENT
//=====================================================================

// 5.1 - Cria Custom Symbol
bool CreateCustomSymbol(MKSError &error)
{
   CLogger::Enter("LiveEngine", "CreateCustomSymbol");
   CLogger::Info("LiveEngine", StringFormat("Criando CS: %s", g_csName));
   
   if(!CustomSymbolCreate(g_csName, "MKS", g_symbol))
   {
      error.Set(MKS_ERROR_CUSTOM_SYMBOL_FAILED,
               "CustomSymbolCreate falhou",
               StringFormat("erro=%d", GetLastError()));
      return false;
   }
   
   // Define descrição
   CustomSymbolSetString(g_csName, SYMBOL_DESCRIPTION, "MKS Renko - " + g_symbol);
   
   // Configura sessões 24/7
   for(int day = 0; day < 7; day++)
   {
      CustomSymbolSetSessionTrade(g_csName, (ENUM_DAY_OF_WEEK)day, 0, 0, 86400);
      CustomSymbolSetSessionQuote(g_csName, (ENUM_DAY_OF_WEEK)day, 0, 0, 86400);
   }
   
   // Seleciona símbolo
   SymbolSelect(g_csName, true);
   
   CLogger::Info("LiveEngine", "CS criado com sucesso");
   CLogger::Exit("LiveEngine", "CreateCustomSymbol");
   return true;
}

// 5.2 - Preenche MqlRates com dados do brick
void MKS_FillRate(MqlRates &rate, MKSRenkoBrick &brick, datetime timestamp)
{
   // Timestamp e OHLC
   rate.time  = timestamp;
   rate.open  = brick.open;
   rate.high  = brick.high;
   rate.low   = brick.low;
   rate.close = brick.close;
   
   // tick_volume variável baseado no range
   double range = brick.high - brick.low;
   double tickSize = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickSize > 0.0)
      rate.tick_volume = (long)MathMax(4, range / tickSize);
   else
      rate.tick_volume = 4;
   
   // spread real do símbolo
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   
   if(tickSize > 0.0 && bid > 0.0 && ask > 0.0)
      rate.spread = (int)MathRound((ask - bid) / tickSize);
   else
      rate.spread = 0;
   
   // CRÍTICO: real_volume armazena o timestamp REAL do brick
   rate.real_volume = (long)brick.time;
}

//=====================================================================
// SEÇÃO 6: HISTÓRICO RÁPIDO
//=====================================================================

// 6.1 - Gera histórico rápido (1 hora)
void GenerateQuickHistory()
{
   CLogger::Enter("LiveEngine", "GenerateQuickHistory");
   CLogger::Info("LiveEngine", StringFormat("Gerando histórico rápido (%d hora)", QUICK_HISTORY_HOURS));
   
   datetime to   = TimeCurrent();
   datetime from = to - QUICK_HISTORY_HOURS * 3600;
   
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   
   int copied = CopyRates(g_symbol, PERIOD_M1, from, to, rates);
   
   if(copied <= 0)
   {
      CLogger::Warn("LiveEngine", "Sem barras M1 na última hora");
      CLogger::Exit("LiveEngine", "GenerateQuickHistory");
      return;
   }
   
   CLogger::Debug("LiveEngine", StringFormat("Processando %d barras M1", copied));
   
   // Processa cada barra M1 (OHLC sequence)
   for(int i = 0; i < copied; i++)
   {
      datetime t = rates[i].time;
      
      // Se barra bullish: O→L→H→C
      if(rates[i].close >= rates[i].open)
      {
         g_core.ProcessPrice(rates[i].open,  t);
         g_core.ProcessPrice(rates[i].low,   t);
         g_core.ProcessPrice(rates[i].high,  t);
         g_core.ProcessPrice(rates[i].close, t);
      }
      // Se barra bearish: O→H→L→C
      else
      {
         g_core.ProcessPrice(rates[i].open,  t);
         g_core.ProcessPrice(rates[i].high,  t);
         g_core.ProcessPrice(rates[i].low,   t);
         g_core.ProcessPrice(rates[i].close, t);
      }
   }
   
   int total = g_core.Count();
   
   if(total <= 0)
   {
      CLogger::Warn("LiveEngine", "Nenhum brick gerado");
      CLogger::Exit("LiveEngine", "GenerateQuickHistory");
      return;
   }
   
   // Prepara rates para publicação
   MqlRates pubRates[];
   ArrayResize(pubRates, total);
   
   MKSRenkoBrick brick;
   datetime baseTime = 0;
   
   for(int i = 0; i < total; i++)
   {
      if(!g_core.GetBrick(i, brick))
         continue;
      
      if(i == 0)
         baseTime = brick.time;
      
      datetime newTime = baseTime + i * 60;
      
      MKS_FillRate(pubRates[i], brick, newTime);
   }
   
   // Publica
   int published = CustomRatesUpdate(g_csName, pubRates);
   
   g_lastTime     = pubRates[total - 1].time;
   g_lastPubCount = g_core.Count();
   
   CLogger::Info("LiveEngine", StringFormat("Histórico rápido: %d bricks publicados", published));
   CLogger::Exit("LiveEngine", "GenerateQuickHistory");
}

//=====================================================================
// SEÇÃO 7: SINCRONIZAÇÃO COM CS EXISTENTE
//=====================================================================

// 7.1 - Sincroniza com Custom Symbol existente
void SyncWithExisting()
{
   CLogger::Enter("LiveEngine", "SyncWithExisting");
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // V3 FIX CRÍTICO: Usa D'2099.12.31' em vez de TimeCurrent() + 86400
   // Isso permite ler TODOS os dados do CS, independente de timestamps futuros
   int copied = CopyRates(g_csName, PERIOD_M1, 0, 2, rates);
   
   if(copied <= 0)
   {
      CLogger::Warn("LiveEngine", "CS vazio - gerando histórico");
      GenerateQuickHistory();
      CLogger::Exit("LiveEngine", "SyncWithExisting");
      return;
   }
   
   // Extrai prevClose e prevDir do último brick
   double prevClose = rates[0].close;
   ENUM_MKS_DIRECTION prevDir = MKS_BULL;
   
   if(rates[0].close > rates[0].open)
      prevDir = MKS_BULL;
   else if(rates[0].close < rates[0].open)
      prevDir = MKS_BEAR;
   else if(copied >= 2)
      prevDir = (rates[1].close >= rates[1].open) ? MKS_BULL : MKS_BEAR;
   
   // Define estado de sincronização no Core
   g_core.SetSyncState(prevClose, prevDir);
   
   // Lê TODOS os rates do CS (V3 FIX: usa D'2099.12.31')
   MqlRates allRates[];
   ArraySetAsSeries(allRates, false);
   int total = CopyRates(g_csName, PERIOD_M1, D'2000.01.01', D'2099.12.31', allRates);
   
   if(total > 0)
   {
      g_lastPubCount = 0;  // Reseta - não queremos duplicar
      g_lastTime     = allRates[total - 1].time;
      
      // Detecta gap
      datetime now = TimeCurrent();
      double gapMinutes = (double)(now - g_lastTime) / 60.0;
      
      if(gapMinutes > GAP_DETECTION_MIN)
      {
         // Verifica se mercado estava aberto (gap real vs weekend/holiday)
         MqlRates gapTest[];
         int gapBars = CopyRates(g_symbol, PERIOD_M1, g_lastTime, now, gapTest);
         
         if(gapBars > 0)
         {
            // Gap REAL: mercado estava aberto
            CLogger::Warn("LiveEngine", StringFormat("Gap REAL detectado (%.1f min) - preenchendo",
                                                     gapMinutes));
            FillGap(g_lastTime, now);
         }
         else
         {
            // Gap FALSO: mercado fechado
            CLogger::Info("LiveEngine", StringFormat("Gap de %.1f min (mercado FECHADO) - ignorado",
                                                     gapMinutes));
         }
      }
      else if(g_lastTime > now)
      {
         CLogger::Info("LiveEngine", StringFormat("CS timestamp %.1f min à frente",
                                                   (double)(g_lastTime - now) / 60.0));
      }
   }
   
   CLogger::Info("LiveEngine", StringFormat("Sincronizado - %d barras | prevClose=%.6f | prevDir=%s",
                                            total, prevClose, EnumToString(prevDir)));
   CLogger::Exit("LiveEngine", "SyncWithExisting");
}

// 7.2 - Preenche gap detectado
void FillGap(datetime from, datetime to)
{
   CLogger::Enter("LiveEngine", "FillGap");
   
   double gapMinutes = (double)(to - from) / 60.0;
   
   CLogger::Info("LiveEngine", "========================================");
   CLogger::Info("LiveEngine", StringFormat("Preenchendo gap de %.1f minutos", gapMinutes));
   CLogger::Info("LiveEngine", StringFormat("De:  %s", TimeToString(from)));
   CLogger::Info("LiveEngine", StringFormat("Até: %s", TimeToString(to)));
   
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   
   int copied = CopyRates(g_symbol, PERIOD_M1, from, to, rates);
   
   if(copied <= 0)
   {
      CLogger::Warn("LiveEngine", "Sem M1 disponíveis (mercado fechado?)");
      CLogger::Info("LiveEngine", "========================================");
      CLogger::Exit("LiveEngine", "FillGap");
      return;
   }
   
   CLogger::Debug("LiveEngine", StringFormat("Processando %d barras M1 do gap", copied));
   
   int bricksBeforeGap = g_core.Count();
   
   // Processa cada barra M1
   for(int i = 0; i < copied; i++)
   {
      datetime t = rates[i].time;
      
      if(rates[i].close >= rates[i].open)
      {
         g_core.ProcessPrice(rates[i].open,  t);
         g_core.ProcessPrice(rates[i].low,   t);
         g_core.ProcessPrice(rates[i].high,  t);
         g_core.ProcessPrice(rates[i].close, t);
      }
      else
      {
         g_core.ProcessPrice(rates[i].open,  t);
         g_core.ProcessPrice(rates[i].high,  t);
         g_core.ProcessPrice(rates[i].low,   t);
         g_core.ProcessPrice(rates[i].close, t);
      }
   }
   
   int bricksAfterGap = g_core.Count();
   int newBricks = bricksAfterGap - bricksBeforeGap;
   
   if(newBricks > 0)
   {
      PublishNewBricks();
      
      CLogger::Info("LiveEngine", StringFormat("Gap preenchido: %d barras M1 → %d bricks",
                                               copied, newBricks));
   }
   else
   {
      CLogger::Info("LiveEngine", "Nenhum brick gerado (movimento insuficiente)");
   }
   
   CLogger::Info("LiveEngine", "========================================");
   CLogger::Exit("LiveEngine", "FillGap");
}

//=====================================================================
// SEÇÃO 8: PUBLICAÇÃO DE BRICKS
//=====================================================================

// 8.1 - Publica novos bricks
void PublishNewBricks()
{
   int coreCount = g_core.Count();
   int newCount  = coreCount - g_lastPubCount;
   
   if(newCount <= 0)
      return;
   
   MqlRates rates[];
   ArrayResize(rates, newCount);
   MKSRenkoBrick brick;
   
   for(int i = 0; i < newCount; i++)
   {
      if(!g_core.GetBrick(g_lastPubCount + i, brick))
         continue;
      
      datetime newTime = (g_lastTime > 0)
                         ? g_lastTime + (datetime)(i + 1)  // V3.0.1 BUG FIX: 1 segundo (não 60)
                         : TimeCurrent() + (datetime)i;
      
      MKS_FillRate(rates[i], brick, newTime);
   }
   
   int result = CustomRatesUpdate(g_csName, rates);
   
   if(result > 0)
   {
      g_lastTime          = rates[newCount - 1].time;
      g_lastPubCount      = coreCount;
      g_totalPubSession  += newCount;
      
      if(g_totalPubSession <= 1 || g_totalPubSession % 10 == 0)
         CLogger::Info("LiveEngine", StringFormat("+%d bricks | sessão: %d | total: %d",
                                                  newCount, g_totalPubSession, g_lastPubCount));
   }
   else
   {
      CLogger::Error("LiveEngine", StringFormat("CustomRatesUpdate falhou - erro %d", GetLastError()));
      g_connectionErrors++;
   }
}

// 8.2 - Atualiza forming bar
void UpdateFormingBar(double price, datetime tickTime)
{
   MKSRenkoBrick forming;
   if(!g_core.GetForming(forming))
      return;
   
   MqlRates formRate[1];
   datetime formTime = (g_lastTime > 0) ? g_lastTime + 1 : tickTime;  // V3.0.1 BUG FIX: 1 segundo
   
   MKS_FillRate(formRate[0], forming, formTime);
   
   CustomRatesUpdate(g_csName, formRate);
}

//=====================================================================
// SEÇÃO 9: GRÁFICO E VISUAL
//=====================================================================

// 9.1 - Encontra gráfico do CS
void FindCustomChart()
{
   g_csChartId = 0;
   long chartId = ChartFirst();
   
   while(chartId >= 0)
   {
      if(ChartSymbol(chartId) == g_csName)
      {
         g_csChartId = chartId;
         return;
      }
      chartId = ChartNext(chartId);
   }
}

// 9.2 - Abre gráfico do CS
void OpenCustomChart()
{
   CLogger::Enter("LiveEngine", "OpenCustomChart");
   
   long chartId = ChartOpen(g_csName, PERIOD_M1);
   
   if(chartId > 0)
   {
      ChartSetInteger(chartId, CHART_MODE, CHART_CANDLES);
      ChartSetInteger(chartId, CHART_AUTOSCROLL, true);
      ChartSetInteger(chartId, CHART_SHIFT, true);
      // ChartRedraw não é permitido em indicadores
      
      CLogger::Info("LiveEngine", StringFormat("Gráfico aberto: %s (ID: %d)", g_csName, chartId));
   }
   else
   {
      CLogger::Warn("LiveEngine", "Falha ao abrir gráfico");
   }
   
   CLogger::Exit("LiveEngine", "OpenCustomChart");
}

// 9.3 - Atualiza linhas Bid/Ask no CS
void UpdateBidAskLines()
{
   if(g_csChartId == 0 || ChartSymbol(g_csChartId) != g_csName)
   {
      FindCustomChart();
      if(g_csChartId == 0) return;
   }
   
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   
   if(bid <= 0 || ask <= 0) return;
   
   // Linha Bid
   if(ObjectFind(g_csChartId, g_bidLineName) < 0)
   {
      ObjectCreate(g_csChartId, g_bidLineName, OBJ_HLINE, 0, 0, bid);
      ObjectSetInteger(g_csChartId, g_bidLineName, OBJPROP_COLOR, clrLime);
      ObjectSetInteger(g_csChartId, g_bidLineName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(g_csChartId, g_bidLineName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(g_csChartId, g_bidLineName, OBJPROP_BACK, true);
      ObjectSetInteger(g_csChartId, g_bidLineName, OBJPROP_SELECTABLE, false);
      ObjectSetString(g_csChartId, g_bidLineName, OBJPROP_TEXT, "Bid");
   }
   else
      ObjectSetDouble(g_csChartId, g_bidLineName, OBJPROP_PRICE, bid);
   
   // Linha Ask
   if(ObjectFind(g_csChartId, g_askLineName) < 0)
   {
      ObjectCreate(g_csChartId, g_askLineName, OBJ_HLINE, 0, 0, ask);
      ObjectSetInteger(g_csChartId, g_askLineName, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(g_csChartId, g_askLineName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(g_csChartId, g_askLineName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(g_csChartId, g_askLineName, OBJPROP_BACK, true);
      ObjectSetInteger(g_csChartId, g_askLineName, OBJPROP_SELECTABLE, false);
      ObjectSetString(g_csChartId, g_askLineName, OBJPROP_TEXT, "Ask");
   }
   else
      ObjectSetDouble(g_csChartId, g_askLineName, OBJPROP_PRICE, ask);
   
   // ChartRedraw não é permitido em indicadores
}

// 9.4 - Publica objeto hidden com metadados do framework para o Panel
// BUG FIX Cowork-V4.5: o Panel (DetectFramework) espera encontrar este objeto
// no grafico onde o LiveEngine esta carregado. Sem ele, o fallback do Panel
// nao consegue ler Preset/PO/PRO/BrickSize e a aba Framework fica incompleta.
//
// Formato do texto: "CSName|preset|brickSize|sizeMode|pO|pRO|revSizePct|dataSource|wicks|sz"
// Objeto OBJ_LABEL posicionado fora da area visivel (x=-1000, y=-1000),
// cor=clrNONE, fonte 1pt, nao selecionavel, background=true.
void PublishInfoObject()
{
   string name = "MKS_LiveEngine_CSName";

   // Monta payload no formato exato que DetectFramework() parseia (10 campos)
   string infoText = StringFormat("%s|%d|%s|%d|%s|%s|%s|%d|%s|%s",
      g_csName,
      (int)g_cfg.preset,
      DoubleToString(g_cfg.brickSize, 8),
      (int)g_cfg.sizeMode,
      DoubleToString(MKS_PO(g_cfg), 4),
      DoubleToString(MKS_PRO(g_cfg), 4),
      DoubleToString(g_cfg.revSizePct, 2),
      (int)g_cfg.dataSource,
      (g_cfg.showWicks ? "1" : "0"),
      DoubleToString(g_sz, g_digits)
   );

   // Cria o objeto na primeira chamada; atualiza apenas o texto nas demais
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, -1000); // Fora da area visivel
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, -1000);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 1);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrNONE);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      CLogger::Info("LiveEngine", StringFormat("InfoObject criado: %s", infoText));
   }

   ObjectSetString(0, name, OBJPROP_TEXT, infoText);
}

// 9.5 - Remove objeto de handshake ao descarregar o indicador
void RemoveInfoObject()
{
   ObjectDelete(0, "MKS_LiveEngine_CSName");
}

//=====================================================================
// SEÇÃO 10: WATCHDOG E HEALTH CHECK
//=====================================================================

// 10.1 - Verifica watchdog (timeout de ticks)
void CheckWatchdog()
{
   if(g_lastTickTime == 0)
      return;
   
   datetime now = TimeCurrent();
   int elapsedSec = (int)(now - g_lastTickTime);
   
   if(elapsedSec > WATCHDOG_TIMEOUT_SEC && !g_watchdogTriggered)
   {
      CLogger::Warn("LiveEngine", StringFormat("WATCHDOG: Sem ticks há %d segundos", elapsedSec));
      g_watchdogTriggered = true;
   }
   else if(elapsedSec <= WATCHDOG_TIMEOUT_SEC && g_watchdogTriggered)
   {
      CLogger::Info("LiveEngine", "WATCHDOG: Ticks retomados");
      g_watchdogTriggered = false;
   }
}

// 10.2 - Health check do CS
void HealthCheck()
{
   datetime now = TimeCurrent();
   
   if(now - g_lastHealthCheck < HEALTH_CHECK_INTERVAL_SEC)
      return;
   
   g_lastHealthCheck = now;
   
   // Verifica se CS ainda existe
   bool isCustom = false;
   if(!SymbolExist(g_csName, isCustom))
   {
      CLogger::Error("LiveEngine", "HEALTH: Custom Symbol não existe mais!");
      return;
   }
   
   // Verifica erros de conexão
   if(g_connectionErrors > MAX_CONNECTION_ERRORS)
   {
      CLogger::Error("LiveEngine", StringFormat("HEALTH: %d erros de conexão", g_connectionErrors));
   }
   
   // Log de debug periódico
   CLogger::Debug("LiveEngine", StringFormat("HEALTH: CS=%s | Bricks=%d | Erros=%d",
                                             g_csName, g_lastPubCount, g_connectionErrors));
}

//=====================================================================
// SEÇÃO 11: ONINIT
//=====================================================================

// 11.1 - Inicialização
int OnInit()
{
   uint startMs = GetTickCount();
   
   // Inicializa logger
   CLogger::Init(LOG_LEVEL_INFO, true, "MKS_LiveEngine.log");
   
   Print("========================================");
   Print("MKS LIVEENGINE v3.0 INICIANDO");
   Print("========================================");
   
   // Valida símbolo
   g_symbol = (InpSymbol == "" || InpSymbol == NULL) ? Symbol() : InpSymbol;
   
   if(!SymbolSelect(g_symbol, true))
   {
      CLogger::Fatal("LiveEngine", StringFormat("Símbolo %s não encontrado", g_symbol));
      return INIT_FAILED;
   }
   
   CLogger::Info("LiveEngine", StringFormat("Símbolo base: %s", g_symbol));
   
   // Cria configuração
   g_cfg.version        = 3;
   g_cfg.preset         = InpPreset;
   g_cfg.brickSize      = InpBrickSize;
   g_cfg.sizeMode       = InpSizeMode;
   g_cfg.openPct        = InpOpenPct;
   g_cfg.revOpenPct     = InpRevOpenPct;
   g_cfg.revSizePct     = InpRevSizePct;
   g_cfg.dataSource     = InpDataSource;
   g_cfg.days           = InpDays;
   g_cfg.showWicks      = InpShowWicks;
   g_cfg.atrPeriod      = InpAtrPeriod;
   g_cfg.atrFactor      = InpAtrFactor;
   g_cfg.percentFactor  = InpPercentFactor;
   
   // Gera nome do CS
   g_csName = MKS_SymbolName(g_symbol, g_cfg);
   CLogger::Info("LiveEngine", StringFormat("Custom Symbol: %s", g_csName));
   
   // Calcula brick size
   MKSError error;
   g_sz = MKS_CalcBrickSize(g_symbol, g_cfg, error);
   
   if(g_sz <= 0.0 || error.HasError())
   {
      CLogger::Fatal("LiveEngine", StringFormat("Brick size inválido: %s", error.ToString()));
      return INIT_FAILED;
   }
   
   CLogger::Info("LiveEngine", StringFormat("Brick size: %.6f", g_sz));

   // BUG FIX Cowork-V4.5: publica objeto hidden com metadados para o Panel
   // Deve ser chamado APÓS g_sz e g_csName estarem calculados e validados
   g_digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   PublishInfoObject();

   // Inicializa Core
   
   if(!g_core.Init(g_cfg, g_sz, g_digits, error))
   {
      CLogger::Fatal("LiveEngine", StringFormat("Core.Init falhou: %s", error.ToString()));
      return INIT_FAILED;
   }
   
   // Verifica se CS existe
   bool isCustom  = false;
   bool csExists  = SymbolExist(g_csName, isCustom);
   bool csHasData = false;
   
   if(csExists)
   {
      MqlRates checkRates[];
      csHasData = (CopyRates(g_csName, PERIOD_M1, 0, 1, checkRates) > 0);
   }
   
   // Cria ou sincroniza CS
   if(!csExists)
   {
      ShowStatus("SINCRONIZANDO RENKO...");
      CLogger::Info("LiveEngine", "CS não existe - criando");
      
      if(!CreateCustomSymbol(error))
      {
         CLogger::Fatal("LiveEngine", StringFormat("CreateCustomSymbol falhou: %s", error.ToString()));
         return INIT_FAILED;
      }
      
      GenerateQuickHistory();
   }
   else if(!csHasData)
   {
      ShowStatus("SINCRONIZANDO RENKO...");
      CLogger::Info("LiveEngine", "CS vazio - gerando histórico");
      
      GenerateQuickHistory();
   }
   else
   {
      CLogger::Info("LiveEngine", "CS com dados - sincronizando");
      SyncWithExisting();
   }
   
   // Marca como pronto
   g_ready = true;
   g_liveTicks = 0;
   g_lastTickTime = TimeCurrent();
   g_lastHealthCheck = TimeCurrent();
   
   // Encontra ou abre gráfico
   FindCustomChart();
   if(g_csChartId == 0)
      OpenCustomChart();
   FindCustomChart();
   
   // V3 CRÍTICO: Inicia timer (Gemini fix para OnTick não funcionar em Custom Symbols)
   EventSetMillisecondTimer(TIMER_INTERVAL_MS);
   
   ShowStatus("100% SINCRONIZADO");
   
   uint elapsed = GetTickCount() - startMs;
   
   Print("========================================");
   Print("MKS LIVEENGINE v3.0 ATIVO");
   Print("========================================");
   Print("Symbol: ", g_symbol, " → ", g_csName);
   Print("Brick Size: ", DoubleToString(g_sz, g_digits));
   Print("Preset: ", EnumToString(g_cfg.preset), " | PO=", DoubleToString(MKS_PO(g_cfg)*100, 0), "% | PRO=", DoubleToString(MKS_PRO(g_cfg)*100, 0), "%");
   Print("Bricks: ", g_lastPubCount, " | LastTime: ", TimeToString(g_lastTime));
   Print("Init: ", elapsed, " ms");
   Print("Timer: ", TIMER_INTERVAL_MS, " ms (OnTimer mode)");
   Print("========================================");
   
   CLogger::Info("LiveEngine", "Inicialização completa com sucesso");
   
   return INIT_SUCCEEDED;
}

//=====================================================================
// SEÇÃO 11.5: DUMMY ONCALCULATE (Obrigatório para compilar Indicadores)
//=====================================================================
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // Não fazemos NADA aqui. 
   // Toda a inteligência do LiveEngine roda no OnTimer() para não depender de ticks.
   return(rates_total);
}


//=====================================================================
// SEÇÃO 12: ONTIMER (GEMINI FIX CRÍTICO)
//=====================================================================

// 12.1 - OnTimer (em vez de OnCalculate/OnTick)
// CRÍTICO: Custom Symbols NÃO disparam OnTick em demo/live
// Solução: OnTimer com EventSetMillisecondTimer
void OnTimer()
{
   if(!g_ready)
      return;
   
   g_liveTicks++;
   if(g_liveTicks == 50)
      RemoveStatus();
   
   // Pega último tick
   MqlTick lastTick;
   if(!SymbolInfoTick(g_symbol, lastTick))
      return;
   
   double price = (lastTick.last > 0.0) ? lastTick.last : lastTick.bid;
   if(price <= 0.0)
      return;
   
   datetime tickTime = lastTick.time;
   
   // Atualiza watchdog
   g_lastTickTime = tickTime;
   
   // Processa preço
   int newBricks = g_core.ProcessPrice(price, tickTime);
   
   // Publica novos bricks
   if(newBricks > 0)
      PublishNewBricks();
   
   // Throttling para forming bar e bid/ask
   uint nowMs = GetTickCount();
   
   if(nowMs - g_lastFormingMs >= THROTTLE_MS)
   {
      UpdateFormingBar(price, tickTime);
      g_lastFormingMs = nowMs;
   }
   
   if(nowMs - g_lastBidAskMs >= THROTTLE_MS)
   {
      UpdateBidAskLines();
      g_lastBidAskMs = nowMs;
   }
   
   // Watchdog e health check
   CheckWatchdog();
   HealthCheck();
}

//=====================================================================
// SEÇÃO 13: ONDEINIT
//=====================================================================

// 13.1 - Deinicialização
void OnDeinit(const int reason)
{
   // Mata timer
   EventKillTimer();

   // BUG FIX Cowork-V4.5: remove objeto de handshake para que o Panel saiba
   // que o LiveEngine foi descarregado (sem o delete, o Panel leria dados stale)
   RemoveInfoObject();

   // Remove status
   RemoveStatus();
   
   // Remove linhas bid/ask
   if(g_csChartId > 0)
   {
      ObjectDelete(g_csChartId, g_bidLineName);
      ObjectDelete(g_csChartId, g_askLineName);
      // ChartRedraw não é permitido em indicadores
      
      // Fecha gráfico se foi por mudança de parâmetros ou recompilação
      if(reason == REASON_PARAMETERS || reason == REASON_RECOMPILE)
      {
         ChartClose(g_csChartId);
         CLogger::Info("LiveEngine", StringFormat("Gráfico CS fechado: %s", g_csName));
      }
   }
   
   Print("========================================");
   Print("MKS LIVEENGINE v3.0 ENCERRADO");
   Print("========================================");
   Print("Motivo: ", reason);
   Print("CS: ", g_csName, " | Bricks: ", g_lastPubCount);
   Print("Sessão: ", g_totalPubSession, " bricks publicados");
   Print("========================================");
   
   CLogger::Info("LiveEngine", StringFormat("Deinit completo - motivo: %d", reason));
}