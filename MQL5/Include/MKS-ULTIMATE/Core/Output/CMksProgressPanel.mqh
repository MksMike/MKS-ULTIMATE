//+------------------------------------------------------------------+
//| @file           : CMksProgressPanel.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Output
//| @responsibility : Painel de status do Producer no chart do ativo
//|                   base. Modo init (durante setup + fill histórico):
//|                   spinner animado + barra de progresso + contadores.
//|                   Modo live (após CS aberto): dados essenciais
//|                   (símbolo, CS, geração, último brick, sync).
//|                   Estilo SaaS Navy/Slate (paleta V5-Dashboard).
//|                   Não-existe em backtest (guard externo).
//| @depends_on     : (nativo MQL5 — ChartObjectCreate, ObjectSet*)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Output/CMksProgressPanel.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_OUTPUT_CMKSPROGRESSPANEL_MQH
#define MKS_ULTIMATE_CORE_OUTPUT_CMKSPROGRESSPANEL_MQH

// Paleta SaaS Navy/Slate — derivada do V5-Dashboard.mq5 (linhas 44-92).
// Aplicada conforme regras 7 e 8 da ADR-022 (camada visual UX/UI).
#define MKS_PANEL_COLOR_BG_MAIN     C'15,17,23'
#define MKS_PANEL_COLOR_BG_CARD     C'22,27,38'
#define MKS_PANEL_COLOR_BG_HEADER   C'18,20,28'
#define MKS_PANEL_COLOR_BG_BAR      C'35,40,55'
#define MKS_PANEL_COLOR_BORDER      C'70,75,90'
#define MKS_PANEL_COLOR_TEXT_TITLE  C'230,235,245'
#define MKS_PANEL_COLOR_TEXT_LIGHT  C'200,205,215'
#define MKS_PANEL_COLOR_TEXT_DIM    C'110,115,135'
#define MKS_PANEL_COLOR_ACCENT_BLUE C'0,150,255'
#define MKS_PANEL_COLOR_ACCENT_GREEN C'0,200,120'
#define MKS_PANEL_COLOR_ACCENT_RED  C'230,60,60'
#define MKS_PANEL_COLOR_SPINNER     C'0,200,120'

#define MKS_PANEL_PREFIX  "MKS_PANEL_"
#define MKS_PANEL_WIDTH   320
#define MKS_PANEL_X       20
#define MKS_PANEL_Y       30

// Estado interno do painel.
enum ENUM_MKS_PANEL_MODE
{
   MKS_PANEL_MODE_NONE  = 0,
   MKS_PANEL_MODE_INIT  = 1,
   MKS_PANEL_MODE_LIVE  = 2,
   MKS_PANEL_MODE_ERROR = 3
};

class CMksProgressPanel
{
private:
   long                  m_chartId;
   ENUM_MKS_PANEL_MODE   m_mode;
   int                   m_spinnerIdx;
   uint                  m_startMs;
   int                   m_height;

   // Spinner Braille (10 frames rotativos). Switch evita array inline
   // dentro de método (limitação MQL5 em static).
   string Spinner(int idx) const
   {
      switch(idx % 10)
      {
         case 0: return "⠋";
         case 1: return "⠙";
         case 2: return "⠹";
         case 3: return "⠸";
         case 4: return "⠼";
         case 5: return "⠴";
         case 6: return "⠦";
         case 7: return "⠧";
         case 8: return "⠇";
         case 9: return "⠏";
      }
      return ".";
   }

   void CreateRect(string name, int x, int y, int w, int h,
                   color bg, color border)
   {
      string full = MKS_PANEL_PREFIX + name;
      if(ObjectFind(m_chartId, full) >= 0)
         ObjectDelete(m_chartId, full);
      ObjectCreate(m_chartId, full, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(m_chartId, full, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chartId, full, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chartId, full, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chartId, full, OBJPROP_YSIZE, h);
      ObjectSetInteger(m_chartId, full, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(m_chartId, full, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chartId, full, OBJPROP_COLOR, border);
      ObjectSetInteger(m_chartId, full, OBJPROP_WIDTH, 1);
      ObjectSetInteger(m_chartId, full, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chartId, full, OBJPROP_BACK, false);
      ObjectSetInteger(m_chartId, full, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, full, OBJPROP_HIDDEN, true);
   }

   // Strings por valor: MQL5 não aceita const & com default literal,
   // nem rvalue (StringFormat, Spinner) em const &.
   void CreateLabel(string name, int x, int y, string text,
                    color clr, int fontSize, string font = "Consolas")
   {
      string full = MKS_PANEL_PREFIX + name;
      if(ObjectFind(m_chartId, full) >= 0)
         ObjectDelete(m_chartId, full);
      ObjectCreate(m_chartId, full, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(m_chartId, full, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chartId, full, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chartId, full, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, full, OBJPROP_FONTSIZE, fontSize);
      ObjectSetInteger(m_chartId, full, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chartId, full, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(m_chartId, full, OBJPROP_BACK, false);
      ObjectSetInteger(m_chartId, full, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, full, OBJPROP_HIDDEN, true);
      ObjectSetString(m_chartId, full, OBJPROP_TEXT, text);
      ObjectSetString(m_chartId, full, OBJPROP_FONT, font);
   }

   // Strings por valor — aceita rvalue de StringFormat etc.
   void UpdateLabel(string name, string text)
   {
      ObjectSetString(m_chartId, MKS_PANEL_PREFIX + name, OBJPROP_TEXT, text);
   }

   void UpdateLabelColor(string name, color clr)
   {
      ObjectSetInteger(m_chartId, MKS_PANEL_PREFIX + name, OBJPROP_COLOR, clr);
   }

   // Apaga todos os objetos com prefixo do painel.
   void ClearAll()
   {
      int total = ObjectsTotal(m_chartId, -1, -1);
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ObjectName(m_chartId, i, -1, -1);
         if(StringFind(name, MKS_PANEL_PREFIX) == 0)
            ObjectDelete(m_chartId, name);
      }
   }

public:
   CMksProgressPanel()
   {
      m_chartId    = 0;
      m_mode       = MKS_PANEL_MODE_NONE;
      m_spinnerIdx = 0;
      m_startMs    = 0;
      m_height     = 0;
   }

   ~CMksProgressPanel() { /* não auto-limpa — caller chama Clear() */ }

   // Cria painel em modo init. Layout fixo, ~280x200px no canto sup esq.
   void InitMode(string symbolBase, string csName, string subtitle)
   {
      m_chartId    = ChartID();
      m_mode       = MKS_PANEL_MODE_INIT;
      m_spinnerIdx = 0;
      m_startMs    = GetTickCount();
      m_height     = 200;

      int x = MKS_PANEL_X, y = MKS_PANEL_Y, w = MKS_PANEL_WIDTH;

      // Fundo principal
      CreateRect("BG", x, y, w, m_height,
                 MKS_PANEL_COLOR_BG_MAIN, MKS_PANEL_COLOR_BORDER);
      // Header (barra superior mais escura, 26px altura)
      CreateRect("BG_HEAD", x, y, w, 26,
                 MKS_PANEL_COLOR_BG_HEADER, MKS_PANEL_COLOR_BORDER);

      // Título — esquerda
      CreateLabel("TITLE", x + 10, y + 6, "MKS-ULTIMATE v6.0.0-alpha",
                  MKS_PANEL_COLOR_TEXT_TITLE, 9, "Segoe UI");
      // Spinner — direita (animado em UpdateProgress)
      CreateLabel("SPIN", x + w - 22, y + 4, Spinner(0),
                  MKS_PANEL_COLOR_SPINNER, 12, "Consolas");

      // Linha 1: símbolo → CS
      string flow = symbolBase + " -> " + csName;
      CreateLabel("FLOW", x + 10, y + 36, flow,
                  MKS_PANEL_COLOR_TEXT_LIGHT, 8, "Consolas");

      // Linha 2: subtítulo (ex.: "Carregando 30 dias de histórico...")
      CreateLabel("SUB", x + 10, y + 56, subtitle,
                  MKS_PANEL_COLOR_TEXT_DIM, 8, "Consolas");

      // Barra de progresso — fundo + preenchimento
      CreateRect("BAR_BG", x + 10, y + 88, w - 20, 16,
                 MKS_PANEL_COLOR_BG_BAR, MKS_PANEL_COLOR_BORDER);
      CreateRect("BAR_FILL", x + 10, y + 88, 0, 16,
                 MKS_PANEL_COLOR_ACCENT_BLUE, MKS_PANEL_COLOR_ACCENT_BLUE);
      CreateLabel("PCT", x + w/2 - 14, y + 89, "0%",
                  MKS_PANEL_COLOR_TEXT_TITLE, 8, "Consolas");

      // Estatísticas — 3 linhas embaixo
      CreateLabel("STAT_TICKS", x + 10, y + 116, "Ticks: 0 / 0",
                  MKS_PANEL_COLOR_TEXT_LIGHT, 8, "Consolas");
      CreateLabel("STAT_BRICKS", x + 10, y + 136, "Bricks: 0",
                  MKS_PANEL_COLOR_TEXT_LIGHT, 8, "Consolas");
      CreateLabel("STAT_TIME", x + 10, y + 156, "Tempo: 0.0s",
                  MKS_PANEL_COLOR_TEXT_DIM, 8, "Consolas");
      CreateLabel("STAT_SPEED", x + 10, y + 176, "Vel: --",
                  MKS_PANEL_COLOR_TEXT_DIM, 8, "Consolas");

      ChartRedraw(m_chartId);
   }

   // Atualiza progresso. Chamado a cada chunk no Producer.OnTimer.
   void UpdateProgress(double pct, long ticksProcessed, long ticksTotal,
                       long bricksEmitted)
   {
      if(m_mode != MKS_PANEL_MODE_INIT) return;

      // Spinner avança
      m_spinnerIdx++;
      UpdateLabel("SPIN", Spinner(m_spinnerIdx));

      // Barra
      if(pct < 0.0) pct = 0.0;
      if(pct > 100.0) pct = 100.0;
      int fillWidth = (int)((MKS_PANEL_WIDTH - 20) * (pct / 100.0));
      ObjectSetInteger(m_chartId, MKS_PANEL_PREFIX + "BAR_FILL",
                       OBJPROP_XSIZE, fillWidth);
      UpdateLabel("PCT", StringFormat("%.0f%%", pct));

      // Stats
      UpdateLabel("STAT_TICKS",
                  StringFormat("Ticks: %s / %s",
                               FormatThousands(ticksProcessed),
                               FormatThousands(ticksTotal)));
      UpdateLabel("STAT_BRICKS",
                  StringFormat("Bricks: %s", FormatThousands(bricksEmitted)));

      uint elapsed = GetTickCount() - m_startMs;
      double seconds = elapsed / 1000.0;
      UpdateLabel("STAT_TIME", StringFormat("Tempo: %.1fs", seconds));

      if(ticksProcessed > 0 && seconds > 0.1)
      {
         double speed = ticksProcessed / seconds;
         UpdateLabel("STAT_SPEED",
                     StringFormat("Vel: %s tps", FormatThousands((long)speed)));
      }

      ChartRedraw(m_chartId);
   }

   // Atualiza apenas o subtítulo (ex.: "Criando Custom Symbol...").
   void UpdateSubtitle(string text)
   {
      if(m_mode != MKS_PANEL_MODE_INIT) return;
      UpdateLabel("SUB", text);
      m_spinnerIdx++;
      UpdateLabel("SPIN", Spinner(m_spinnerIdx));
      ChartRedraw(m_chartId);
   }

   // Transiciona para modo live. Apaga progresso/spinner/stats de fill,
   // redesenha layout compacto com dados operacionais.
   // Strings por valor para aceitar rvalues (StringFormat, helpers).
   void LiveMode(string symbolBase, string csName,
                 string typeName, double sizePts,
                 const datetime generatedAt)
   {
      m_mode   = MKS_PANEL_MODE_LIVE;
      m_height = 160;

      // Apaga objetos de init que não pertencem ao live
      ObjectDelete(m_chartId, MKS_PANEL_PREFIX + "BAR_BG");
      ObjectDelete(m_chartId, MKS_PANEL_PREFIX + "BAR_FILL");
      ObjectDelete(m_chartId, MKS_PANEL_PREFIX + "PCT");
      ObjectDelete(m_chartId, MKS_PANEL_PREFIX + "STAT_TIME");
      ObjectDelete(m_chartId, MKS_PANEL_PREFIX + "STAT_SPEED");

      // Redimensiona background
      ObjectSetInteger(m_chartId, MKS_PANEL_PREFIX + "BG",
                       OBJPROP_YSIZE, m_height);

      // Substitui spinner por bolinha verde fixa "● operando"
      UpdateLabel("SPIN", "●");

      // Atualiza subtítulo
      UpdateLabel("SUB", StringFormat("Type: %s   Size: %.1fpts",
                                       typeName, sizePts));

      // Adiciona "Gerado em ..."
      MqlDateTime dt;
      TimeToStruct(generatedAt, dt);
      string genStr = StringFormat("Gerado: %04d-%02d-%02d %02d:%02d:%02d",
                                    dt.year, dt.mon, dt.day,
                                    dt.hour, dt.min, dt.sec);
      CreateLabel("GEN", MKS_PANEL_X + 10, MKS_PANEL_Y + 76, genStr,
                  MKS_PANEL_COLOR_TEXT_DIM, 8, "Consolas");

      // Reposiciona/recria STAT_BRICKS, STAT_TICKS para modo live
      UpdateLabel("STAT_TICKS", "Ticks/s: --");
      ObjectSetInteger(m_chartId, MKS_PANEL_PREFIX + "STAT_TICKS",
                       OBJPROP_YDISTANCE, MKS_PANEL_Y + 100);

      UpdateLabel("STAT_BRICKS", "Bricks: 0");
      ObjectSetInteger(m_chartId, MKS_PANEL_PREFIX + "STAT_BRICKS",
                       OBJPROP_YDISTANCE, MKS_PANEL_Y + 120);

      // Linha extra: sync status
      CreateLabel("STAT_SYNC", MKS_PANEL_X + 10, MKS_PANEL_Y + 140,
                  "Sync: -/- ", MKS_PANEL_COLOR_ACCENT_GREEN, 8, "Consolas");

      ChartRedraw(m_chartId);
   }

   // Atualiza dados live. Chamado a baixa frequência (1Hz via OnTimer).
   void UpdateLive(long bricksTotal, long writerCount,
                   string lastBrickInfo, double ticksPerSec)
   {
      if(m_mode != MKS_PANEL_MODE_LIVE) return;

      UpdateLabel("STAT_TICKS",
                  StringFormat("Ticks/s: %.1f", ticksPerSec));
      UpdateLabel("STAT_BRICKS",
                  StringFormat("Bricks: %s | %s",
                               FormatThousands(bricksTotal),
                               lastBrickInfo));

      // Sync ✓ ou ✗
      string syncTxt;
      color syncClr;
      if(bricksTotal == writerCount)
      {
         syncTxt = StringFormat("Sync: %s/%s OK",
                                FormatThousands(bricksTotal),
                                FormatThousands(writerCount));
         syncClr = MKS_PANEL_COLOR_ACCENT_GREEN;
      }
      else
      {
         syncTxt = StringFormat("Sync: %s/%s DRIFT",
                                FormatThousands(bricksTotal),
                                FormatThousands(writerCount));
         syncClr = MKS_PANEL_COLOR_ACCENT_RED;
      }
      UpdateLabel("STAT_SYNC", syncTxt);
      UpdateLabelColor("STAT_SYNC", syncClr);

      ChartRedraw(m_chartId);
   }

   // Sinaliza erro no painel — muda cor do título e mostra mensagem.
   void ShowError(string message)
   {
      m_mode = MKS_PANEL_MODE_ERROR;
      UpdateLabel("TITLE", "MKS-ULTIMATE — ERRO");
      UpdateLabelColor("TITLE", MKS_PANEL_COLOR_ACCENT_RED);
      UpdateLabel("SUB", message);
      UpdateLabelColor("SUB", MKS_PANEL_COLOR_ACCENT_RED);
      UpdateLabel("SPIN", "X");
      UpdateLabelColor("SPIN", MKS_PANEL_COLOR_ACCENT_RED);
      ChartRedraw(m_chartId);
   }

   // Apaga todo o painel. Chamado em OnDeinit do Producer.
   void Clear()
   {
      ClearAll();
      m_mode = MKS_PANEL_MODE_NONE;
      ChartRedraw(m_chartId);
   }

   ENUM_MKS_PANEL_MODE Mode() const { return m_mode; }

private:
   // Formata número com separador de milhar (12345 → "12,345").
   static string FormatThousands(long n)
   {
      string s = (string)n;
      string sign = "";
      if(StringGetCharacter(s, 0) == '-')
      {
         sign = "-";
         s = StringSubstr(s, 1);
      }
      int len = StringLen(s);
      if(len <= 3) return sign + s;
      string out = "";
      int rem = len % 3;
      if(rem > 0) out = StringSubstr(s, 0, rem);
      for(int i = rem; i < len; i += 3)
      {
         if(StringLen(out) > 0) out += ",";
         out += StringSubstr(s, i, 3);
      }
      return sign + out;
   }
};

#endif // MKS_ULTIMATE_CORE_OUTPUT_CMKSPROGRESSPANEL_MQH
