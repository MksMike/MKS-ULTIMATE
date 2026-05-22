//+------------------------------------------------------------------+
//| MKS-PanelBridge.mqh                                              |
//| MKS Framework - V5.0 Research Engine                             |
//| Descricao: Ponte de comunicacao EA-SANDBOX ↔ UniversalPanel     |
//|            via GlobalVariables (assincrono, sem bloqueio)        |
//| Instalacao: MQL5/Include/MKS-V5.0/UI/                            |
//| Build: V5.0 (2026-04-07)                                         |
//+------------------------------------------------------------------+

#ifndef __MKS_PANEL_BRIDGE_MQH__
#define __MKS_PANEL_BRIDGE_MQH__

//=====================================================================
// SEÇÃO 1: PREFIXO E CONSTANTES
//=====================================================================

#define GV_PREFIX "MKS_SANDBOX_"
#define MAX_STRATEGIES 4

//=====================================================================
// SEÇÃO 2: ESTRUTURAS DE DADOS
//=====================================================================

struct StrategyMetrics
{
   string name;
   int    nameIdx;  // 0=TrendFollow, 1=MeanReversion, 2=Breakout, 3=ScalpBricks
   bool   active;
   int    trades;
   double profit;
   int    wins;
   int    losses;
   
   void Reset()
   {
      trades = 0;
      profit = 0;
      wins = 0;
      losses = 0;
   }
};

//=====================================================================
// SEÇÃO 3: CLASSE PANELBRIDGE
//=====================================================================

class CPanelBridge
{
private:
   bool m_initialized;
   datetime m_lastUpdate;

public:
   CPanelBridge()
   {
      m_initialized = false;
      m_lastUpdate = 0;
   }
   
   ~CPanelBridge()
   {
      Shutdown();
   }
   
   void Init()
   {
      GlobalVariableSet(GV_PREFIX + "RUNNING", 1.0);
      
      m_initialized = true;
      m_lastUpdate = TimeCurrent();
      
      Print("[PanelBridge] ✓ Inicializado - UniversalPanel pode ler dados");
   }
   
   void Shutdown()
   {
      if (!m_initialized) return;
      
      GlobalVariableDel(GV_PREFIX + "RUNNING");
      ClearAllVariables();
      
      m_initialized = false;
      
      Print("[PanelBridge] ✓ Desligado - dados removidos");
   }
   
   void PublishGlobalData(double startEquity, double currentEquity, double dailyPL, 
                          int brickCount, int totalTrades, bool stressLabActive)
   {
      if (!m_initialized) return;
      
      GlobalVariableSet(GV_PREFIX + "START_EQUITY", startEquity);
      GlobalVariableSet(GV_PREFIX + "CURRENT_EQUITY", currentEquity);
      GlobalVariableSet(GV_PREFIX + "DAILY_PL", dailyPL);
      GlobalVariableSet(GV_PREFIX + "BRICK_COUNT", (double)brickCount);
      GlobalVariableSet(GV_PREFIX + "TOTAL_TRADES", (double)totalTrades);
      GlobalVariableSet(GV_PREFIX + "STRESSLAB", stressLabActive ? 1.0 : 0.0);
      
      m_lastUpdate = TimeCurrent();
   }
   
   void PublishStrategy(int strategyIndex, const StrategyMetrics &metrics)
   {
      if (!m_initialized) return;
      
      if (strategyIndex < 0 || strategyIndex >= MAX_STRATEGIES)
      {
         Print("[PanelBridge] ✗ ERRO: índice inválido: ", strategyIndex);
         return;
      }
      
      string prefix = GV_PREFIX + "STRAT_" + IntegerToString(strategyIndex) + "_";
      
      GlobalVariableSet(prefix + "ACTIVE", metrics.active ? 1.0 : 0.0);
      GlobalVariableSet(prefix + "NAME_IDX", (double)metrics.nameIdx);
      GlobalVariableSet(prefix + "TRADES", (double)metrics.trades);
      GlobalVariableSet(prefix + "PROFIT", metrics.profit);
      GlobalVariableSet(prefix + "WINS", (double)metrics.wins);
      GlobalVariableSet(prefix + "LOSSES", (double)metrics.losses);
   }
   
   int GetStrategyIndex(string name)
   {
      if (name == "TrendFollow" || StringFind(name, "Trend") >= 0)
         return 0;
      else if (name == "MeanReversion" || StringFind(name, "Mean") >= 0)
         return 1;
      else if (name == "Breakout" || StringFind(name, "Break") >= 0)
         return 2;
      else if (name == "ScalpBricks" || StringFind(name, "Scalp") >= 0)
         return 3;
      
      return -1;
   }
   
   void ClearAllVariables()
   {
      GlobalVariableDel(GV_PREFIX + "RUNNING");
      GlobalVariableDel(GV_PREFIX + "START_EQUITY");
      GlobalVariableDel(GV_PREFIX + "CURRENT_EQUITY");
      GlobalVariableDel(GV_PREFIX + "DAILY_PL");
      GlobalVariableDel(GV_PREFIX + "BRICK_COUNT");
      GlobalVariableDel(GV_PREFIX + "TOTAL_TRADES");
      GlobalVariableDel(GV_PREFIX + "STRESSLAB");
      
      for (int i = 0; i < MAX_STRATEGIES; i++)
      {
         string prefix = GV_PREFIX + "STRAT_" + IntegerToString(i) + "_";
         
         GlobalVariableDel(prefix + "ACTIVE");
         GlobalVariableDel(prefix + "NAME_IDX");
         GlobalVariableDel(prefix + "TRADES");
         GlobalVariableDel(prefix + "PROFIT");
         GlobalVariableDel(prefix + "WINS");
         GlobalVariableDel(prefix + "LOSSES");
      }
   }
   
   void PrintStatus()
   {
      Print("========================================");
      Print("PANELBRIDGE STATUS");
      Print("========================================");
      Print("Initialized: ", m_initialized ? "YES" : "NO");
      Print("Last Update: ", TimeToString(m_lastUpdate));
      Print("Running Flag: ", GlobalVariableCheck(GV_PREFIX + "RUNNING") ? "SET" : "NOT SET");
      Print("========================================");
   }
};

#endif