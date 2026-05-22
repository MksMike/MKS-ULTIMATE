//+------------------------------------------------------------------+
//| ProgressPanel.mqh                                            |
//| MKS Framework - V5.0 Research Engine                             |
//| Descricao: Painel de progresso para Generator                 |
//| Instalacao: MQL5/Include/MKS-V5.0/UI/                          |
//| Build: V5.0 (2026-04-07)                                         |
//+------------------------------------------------------------------+

#property copyright   "MKS Framework"
#property version     "3.20"

//=====================================================================
// CLASSE: PAINEL DE PROGRESSO
//=====================================================================

class CProgressPanel
{
private:
   // Identificadores únicos dos objetos gráficos
   string m_prefix;
   long   m_chartId;
   
   // Dimensões do painel
   int    m_x;
   int    m_y;
   int    m_width;
   int    m_height;
   
   // Estado atual
   string m_currentStep;
   double m_progress;
   uint   m_startTime;
   
   // Estatísticas
   int    m_itemsProcessed;
   int    m_itemsTotal;
   
   //==================================================================
   // MÉTODO PRIVADO: Criar objeto gráfico
   //==================================================================
   
   void CreateObject(string name, ENUM_OBJECT objType)
   {
      string fullName = m_prefix + name;
      
      if(ObjectFind(m_chartId, fullName) >= 0)
         ObjectDelete(m_chartId, fullName);
      
      ObjectCreate(m_chartId, fullName, objType, 0, 0, 0);
   }
   
   //==================================================================
   // MÉTODO PRIVADO: Desenhar fundo do painel
   //==================================================================
   
   void DrawBackground()
   {
      CreateObject("BG", OBJ_RECTANGLE_LABEL);
      
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_XDISTANCE, m_x);
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_YDISTANCE, m_y);
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_XSIZE, m_width);
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_YSIZE, m_height);
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_BGCOLOR, clrBlack);
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_WIDTH, 2);
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_BACK, false);
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_HIDDEN, true);
   }
   
   //==================================================================
   // MÉTODO PRIVADO: Criar label de texto
   //==================================================================
   
   void CreateLabel(string name, int xOffset, int yOffset, string text, color clr, int fontSize = 10)
   {
      CreateObject(name, OBJ_LABEL);
      
      ObjectSetInteger(m_chartId, m_prefix + name, OBJPROP_XDISTANCE, m_x + xOffset);
      ObjectSetInteger(m_chartId, m_prefix + name, OBJPROP_YDISTANCE, m_y + yOffset);
      ObjectSetInteger(m_chartId, m_prefix + name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, m_prefix + name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(m_chartId, m_prefix + name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chartId, m_prefix + name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(m_chartId, m_prefix + name, OBJPROP_BACK, false);
      ObjectSetInteger(m_chartId, m_prefix + name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, m_prefix + name, OBJPROP_HIDDEN, true);
      ObjectSetString(m_chartId, m_prefix + name, OBJPROP_TEXT, text);
      ObjectSetString(m_chartId, m_prefix + name, OBJPROP_FONT, "Consolas");
   }
   
   //==================================================================
   // MÉTODO PRIVADO: Atualizar barra de progresso
   //==================================================================
   
   void UpdateProgressBar()
   {
      // Fundo da barra (cinza)
      CreateObject("ProgressBG", OBJ_RECTANGLE_LABEL);
      ObjectSetInteger(m_chartId, m_prefix + "ProgressBG", OBJPROP_XDISTANCE, m_x + 15);
      ObjectSetInteger(m_chartId, m_prefix + "ProgressBG", OBJPROP_YDISTANCE, m_y + 80);
      ObjectSetInteger(m_chartId, m_prefix + "ProgressBG", OBJPROP_XSIZE, m_width - 30);
      ObjectSetInteger(m_chartId, m_prefix + "ProgressBG", OBJPROP_YSIZE, 25);
      ObjectSetInteger(m_chartId, m_prefix + "ProgressBG", OBJPROP_BGCOLOR, clrDimGray);
      ObjectSetInteger(m_chartId, m_prefix + "ProgressBG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chartId, m_prefix + "ProgressBG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chartId, m_prefix + "ProgressBG", OBJPROP_BACK, false);
      ObjectSetInteger(m_chartId, m_prefix + "ProgressBG", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, m_prefix + "ProgressBG", OBJPROP_HIDDEN, true);
      
      // Barra de progresso (verde)
      int progressWidth = (int)((m_width - 30) * (m_progress / 100.0));
      
      if(progressWidth > 0)
      {
         CreateObject("ProgressBar", OBJ_RECTANGLE_LABEL);
         ObjectSetInteger(m_chartId, m_prefix + "ProgressBar", OBJPROP_XDISTANCE, m_x + 15);
         ObjectSetInteger(m_chartId, m_prefix + "ProgressBar", OBJPROP_YDISTANCE, m_y + 80);
         ObjectSetInteger(m_chartId, m_prefix + "ProgressBar", OBJPROP_XSIZE, progressWidth);
         ObjectSetInteger(m_chartId, m_prefix + "ProgressBar", OBJPROP_YSIZE, 25);
         ObjectSetInteger(m_chartId, m_prefix + "ProgressBar", OBJPROP_BGCOLOR, clrLimeGreen);
         ObjectSetInteger(m_chartId, m_prefix + "ProgressBar", OBJPROP_BORDER_TYPE, BORDER_FLAT);
         ObjectSetInteger(m_chartId, m_prefix + "ProgressBar", OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, m_prefix + "ProgressBar", OBJPROP_BACK, false);
         ObjectSetInteger(m_chartId, m_prefix + "ProgressBar", OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, m_prefix + "ProgressBar", OBJPROP_HIDDEN, true);
      }
      
      // Texto da porcentagem
      string pctText = StringFormat("%.1f%%", m_progress);
      CreateLabel("ProgressPct", (m_width / 2) - 20, 83, pctText, clrWhite, 11);
   }

public:
   //==================================================================
   // CONSTRUTOR
   //==================================================================
   
   CProgressPanel()
   {
      m_prefix = "MKS_Progress_";
      m_chartId = 0;
      m_x = 20;
      m_y = 50;
      m_width = 550;  // Largura aumentada de 400 para 550
      m_height = 180;
      m_progress = 0;
      m_itemsProcessed = 0;
      m_itemsTotal = 0;
      m_startTime = GetTickCount();
      m_currentStep = "Inicializando...";
   }
   
   //==================================================================
   // MÉTODO: Inicializar painel
   //==================================================================
   
   void Init(long chartId = 0, int posX = 20, int posY = 50)
   {
      m_chartId = (chartId == 0) ? ChartID() : chartId;
      m_x = posX;
      m_y = posY;
      m_startTime = GetTickCount();
      
      // Desenha todos os componentes
      DrawBackground();
      
      // Título
      CreateLabel("Title", 15, 10, "MKS GENERATOR v3.2", clrYellow, 14);
      
      // Status inicial
      CreateLabel("Status", 15, 35, "Status: Inicializando...", clrWhite, 10);
      
      // Barra de progresso
      UpdateProgressBar();
      
      // Estatísticas
      CreateLabel("Items", 15, 115, "Processados: 0 / 0", clrLightGray, 9);
      CreateLabel("Time", 15, 135, "Tempo: 0.0 seg", clrLightGray, 9);
      CreateLabel("Speed", 15, 155, "Velocidade: -- items/seg", clrLightGray, 9);
      
      ChartRedraw(m_chartId);
   }
   
   //==================================================================
   // MÉTODO: Atualizar status
   //==================================================================
   
   void UpdateStatus(string step, double progressPct = -1, int processed = -1, int total = -1)
   {
      m_currentStep = step;
      
      if(progressPct >= 0)
         m_progress = progressPct;
      
      if(processed >= 0)
         m_itemsProcessed = processed;
      
      if(total >= 0)
         m_itemsTotal = total;
      
      // Atualiza labels
      ObjectSetString(m_chartId, m_prefix + "Status", OBJPROP_TEXT, "Status: " + m_currentStep);
      
      // Atualiza barra de progresso
      UpdateProgressBar();
      
      // Estatísticas
      string itemsText = StringFormat("Processados: %d / %d", m_itemsProcessed, m_itemsTotal);
      ObjectSetString(m_chartId, m_prefix + "Items", OBJPROP_TEXT, itemsText);
      
      // Tempo decorrido
      uint elapsed = GetTickCount() - m_startTime;
      double seconds = elapsed / 1000.0;
      string timeText = StringFormat("Tempo: %.1f seg", seconds);
      ObjectSetString(m_chartId, m_prefix + "Time", OBJPROP_TEXT, timeText);
      
      // Velocidade
      string speedText = "Velocidade: -- items/seg";
      if(m_itemsProcessed > 0 && seconds > 0)
      {
         double speed = m_itemsProcessed / seconds;
         speedText = StringFormat("Velocidade: %.1f items/seg", speed);
      }
      ObjectSetString(m_chartId, m_prefix + "Speed", OBJPROP_TEXT, speedText);
      
      ChartRedraw(m_chartId);
   }
   
   //==================================================================
   // MÉTODO: Finalizar (mostrar sucesso)
   //==================================================================
   
   void Finish(string finalMessage = "Concluído com sucesso!")
   {
      m_progress = 100.0;
      m_currentStep = finalMessage;
      
      // Atualiza status final
      ObjectSetString(m_chartId, m_prefix + "Status", OBJPROP_TEXT, "Status: " + finalMessage);
      ObjectSetInteger(m_chartId, m_prefix + "Status", OBJPROP_COLOR, clrLimeGreen);
      
      // Atualiza barra (100%)
      UpdateProgressBar();
      
      // Tempo final
      uint elapsed = GetTickCount() - m_startTime;
      double seconds = elapsed / 1000.0;
      string timeText = StringFormat("Tempo total: %.1f seg", seconds);
      ObjectSetString(m_chartId, m_prefix + "Time", OBJPROP_TEXT, timeText);
      
      ChartRedraw(m_chartId);
   }
   
   //==================================================================
   // MÉTODO: Mostrar erro
   //==================================================================
   
   void ShowError(string errorMessage)
   {
      m_currentStep = "ERRO: " + errorMessage;
      
      ObjectSetString(m_chartId, m_prefix + "Status", OBJPROP_TEXT, m_currentStep);
      ObjectSetInteger(m_chartId, m_prefix + "Status", OBJPROP_COLOR, clrRed);
      
      // Muda cor do fundo para vermelho escuro
      ObjectSetInteger(m_chartId, m_prefix + "BG", OBJPROP_BGCOLOR, clrMaroon);
      
      ChartRedraw(m_chartId);
   }
   
   //==================================================================
   // MÉTODO: Limpar painel
   //==================================================================
   
   void Clear()
   {
      ObjectDelete(m_chartId, m_prefix + "BG");
      ObjectDelete(m_chartId, m_prefix + "Title");
      ObjectDelete(m_chartId, m_prefix + "Status");
      ObjectDelete(m_chartId, m_prefix + "ProgressBG");
      ObjectDelete(m_chartId, m_prefix + "ProgressBar");
      ObjectDelete(m_chartId, m_prefix + "ProgressPct");
      ObjectDelete(m_chartId, m_prefix + "Items");
      ObjectDelete(m_chartId, m_prefix + "Time");
      ObjectDelete(m_chartId, m_prefix + "Speed");
      
      ChartRedraw(m_chartId);
   }
   
   //==================================================================
   // DESTRUTOR
   //==================================================================
   
   ~CProgressPanel()
   {
      // Não limpa automaticamente - deixa visível após script terminar
      // Para limpar, chame Clear() manualmente
   }
};