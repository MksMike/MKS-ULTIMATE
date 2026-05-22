//+------------------------------------------------------------------+
//| MKS-Dashboard-Pro.mq5                                            |
//| MKS Framework - V5.0 [Indicator]                                 |
//| Descricao: Dashboard institucional SaaS multi-aba profissional   |
//| Instalacao: MQL5/Indicators/MKS-V5.0/MKS-Dashboard-Pro.mq5        |
//| Build: V5.0 (2026-04-08)                                        |
//+------------------------------------------------------------------+

//=====================================================================
// [1] PROPRIEDADES E INCLUDES
// Define tipo de indicador overlay no grafico principal,
// sem plots visuais (somente objetos graficos).
//=====================================================================

#property copyright          "MKS Framework"                          // copyright do framework
#property version            "5.00"                                   // versao do indicador
#property description        "MKS Dashboard Pro — Painel institucional SaaS"  // descricao curta
#property description        "Design moderno com cards, sombras e 5 abas"     // descricao complementar
#property indicator_chart_window                                      // overlay no grafico principal
#property indicator_plots    0                                        // sem buffers de plot

#include <MKS-V5.0/Core/MKS-Renko-Types.mqh>                           // tipos, enums, structs do framework


//=====================================================================
// [2] INPUTS DO USUARIO
// Parametros ajustaveis pelo usuario na janela de propriedades.
//=====================================================================

input int    InpFontSize      = 9;                                    // Tamanho base da fonte (7-16)
input int    InpTimezoneShift = 9;                                    // Fuso horario (horas vs UTC, ex: 9=Japao)
input double InpCommission    = 7.0;                                  // Comissao por lote por lado ($)
input int    InpPreset        = MKS_PRESET_MEDIAN;                    // Preset Renko (para deteccao do CS)
input double InpBrickSize     = 100;                                  // Brick Size (para deteccao do CS)
input int    InpSizeMode      = MKS_SIZE_TICKS;                       // Modo Size (para deteccao do CS)


//=====================================================================
// [3] PALETA DE CORES — TEMA DARK SaaS INSTITUCIONAL
// Inspirado em dashboards profissionais com tons de navy/slate.
// Cada cor tem comentario de uso para facilitar customizacao futura.
//=====================================================================

//--- Fundos principais ---
#define CLR_BG_MAIN         C'15,17,23'                               // fundo principal do painel (quase preto azulado)
#define CLR_BG_HEADER       C'18,20,28'                               // fundo do header superior
#define CLR_BG_CARD         C'22,27,38'                               // fundo dos cards internos
#define CLR_BG_CARD_HOVER   C'28,34,48'                               // fundo card hover/selecionado
#define CLR_BG_SHADOW       C'8,10,14'                                // sombra dos cards (offset 2px)
#define CLR_BG_INPUT        C'30,35,50'                               // fundo de inputs e campos

//--- Abas ---
#define CLR_TAB_ACTIVE      C'22,27,38'                               // aba ativa = cor do card
#define CLR_TAB_INACTIVE    C'18,20,28'                               // aba inativa = cor do header
#define CLR_TAB_ACCENT      C'0,150,255'                              // linha de acento na aba ativa

//--- Bordas e separadores ---
#define CLR_BORDER          C'40,45,60'                               // borda dos cards
#define CLR_SEPARATOR       C'35,40,55'                               // linhas separadoras horizontais
#define CLR_CARD_EDGE       C'50,55,75'                               // borda sutil do card

//--- Textos ---
#define CLR_TEXT_WHITE       clrWhite                                  // titulos e valores destaque
#define CLR_TEXT_LIGHT       C'200,205,215'                           // texto principal legivel
#define CLR_TEXT_DIM         C'110,115,135'                           // texto secundario / labels
#define CLR_TEXT_MUTED       C'70,75,90'                              // texto muito sutil / placeholders

//--- Cores de acento ---
#define CLR_ACCENT_BLUE     C'0,150,255'                              // acento primario (azul royal)
#define CLR_ACCENT_CYAN     C'0,210,190'                              // acento secundario (teal/cyan)
#define CLR_ACCENT_GREEN    C'0,200,120'                              // positivo / lucro / bull
#define CLR_ACCENT_RED      C'230,60,60'                              // negativo / perda / bear
#define CLR_ACCENT_YELLOW   C'255,200,50'                             // alerta / warning / neutro
#define CLR_ACCENT_ORANGE   C'255,140,50'                             // destaque secundario
#define CLR_ACCENT_PURPLE   C'140,100,255'                            // destaque terciario

//--- Barras de progresso ---
#define CLR_BAR_BG          C'35,40,55'                               // fundo da barra
#define CLR_BAR_GREEN       C'0,180,100'                              // barra positiva
#define CLR_BAR_YELLOW      C'220,180,30'                             // barra alerta
#define CLR_BAR_RED         C'200,50,50'                              // barra critica

//--- Botoes ---
#define CLR_BTN_PRIMARY     C'0,120,230'                              // botao primario
#define CLR_BTN_SECONDARY   C'40,45,65'                               // botao secundario
#define CLR_BTN_DANGER      C'180,40,40'                              // botao perigo/desativar
#define CLR_BTN_SUCCESS     C'0,150,90'                               // botao sucesso/ativar

//--- Status badges ---
#define CLR_BADGE_ACTIVE    C'0,180,100'                              // badge ativo (verde)
#define CLR_BADGE_INACTIVE  C'120,60,60'                              // badge inativo (vermelho escuro)
#define CLR_BADGE_PENDING   C'200,160,30'                             // badge pendente (amarelo)

//--- Prefixo dos objetos graficos ---
#define OBJ_PREFIX          "MKSD_"                                   // prefixo unico para evitar conflitos

//--- Constantes de layout ---
#define MARGIN              16                                        // margem interna padrao (aumentada)
#define CARD_PAD            14                                        // padding interno dos cards (aumentado)
#define CARD_GAP            12                                        // gap entre cards
#define SHADOW_OFFSET       3                                         // offset da sombra dos cards
#define CARD_BORDER_W       1                                         // espessura da borda do card
#define SECTION_TITLE_H     20                                        // altura do titulo de secao
#define TAB_COUNT           5                                         // numero de abas


//=====================================================================
// [4] VARIAVEIS GLOBAIS
// Estado do painel, cache de dados, handles de indicadores.
//=====================================================================

//--- Estado do painel ---
int            g_activeTab     = 0;                                   // indice da aba ativa (0-4)
bool           g_minimized     = false;                               // painel minimizado?
string         g_symbol        = "";                                  // simbolo do grafico
int            g_chartW        = 0;                                   // largura do grafico em pixels
int            g_chartH        = 0;                                   // altura do grafico em pixels
int            g_panelX        = 0;                                   // posicao X do painel
int            g_panelY        = 0;                                   // posicao Y do painel
int            g_panelW        = 620;                                 // largura do painel (aumentada)
int            g_panelH        = 1500;                                // altura total do painel (aumentada)

//--- Fontes calculadas ---
int            g_fontBase      = 9;                                   // fonte base configuravel
int            g_fontTitle     = 13;                                  // fonte de titulos grandes
int            g_fontSection   = 11;                                  // fonte de titulos de secao
int            g_fontNormal    = 9;                                   // fonte normal de texto
int            g_fontSmall     = 8;                                   // fonte pequena
int            g_fontTab       = 8;                                   // fonte das abas
int            g_fontValue     = 11;                                  // fonte de valores grandes

//--- Layout dinamico ---
int            g_headerH       = 65;                                  // altura do header (2 linhas)
int            g_tabH          = 28;                                  // altura da barra de abas
int            g_contentH      = 900;                                 // altura da area de conteudo
int            g_lineH         = 30;                                  // espaco entre linhas normais (aumentado forte)
int            g_lineHSmall    = 26;                                  // espaco entre linhas pequenas (aumentado forte)
int            g_sectionGap    = 30;                                  // espaco entre secoes (aumentado)

//--- Nomes das abas ---
string         g_tabLabels[TAB_COUNT];                                // labels das abas
string         g_tabIcons[TAB_COUNT];                                 // icones das abas (unicode)

//--- Framework Renko ---
bool           g_frameworkOk   = false;                               // framework detectado?
string         g_csName        = "";                                  // nome do Custom Symbol
int            g_fwPreset      = -1;                                  // preset do LiveEngine
double         g_fwBrickSize   = 0;                                   // brick size
int            g_fwSizeMode    = 0;                                   // modo size
double         g_fwPO          = 0;                                   // pO
double         g_fwPRO         = 0;                                   // pRO
double         g_fwRevSizePct  = 100.0;                               // revSizePct
int            g_fwDataSource  = 0;                                   // fonte dados
bool           g_fwWicks       = true;                                // wicks
double         g_fwSz          = 0;                                   // sz em preco

//--- Handles de indicadores ---
int            g_hATR_D1       = INVALID_HANDLE;                      // ATR(21) D1

//--- Contadores ---
int            g_tickCount     = 0;                                   // ticks no minuto atual
int            g_ticksPerMin   = 0;                                   // ticks/min do minuto anterior
datetime       g_lastMinute    = 0;                                   // referencia do minuto

//--- Cache de performance (evita reprocessar se nao ha novos deals) ---
int            g_lastDealCount = -1;                                  // total deals no ultimo check
int            g_intellMinute  = -1;                                  // minuto do ultimo UpdateIntelligence

//--- Persistencia ---
string         g_gvFont        = "MKSD_FontSize";                    // GlobalVariable para fonte
string         g_gvComm        = "MKSD_Commission";                  // GlobalVariable para comissao
string         g_gvTZ          = "MKSD_Timezone";                    // GlobalVariable para fuso
double         g_commission    = 7.0;                                 // comissao por lado
int            g_tzShift       = 9;                                   // offset UTC (default Japao)
string         g_acctCurrency  = "USD";                               // moeda da conta (atualizada no OnInit)

//--- Estrategias do Robo (toggles) ---
#define MAX_STRATEGIES     6                                          // maximo de estrategias
string         g_stratNames[MAX_STRATEGIES];                          // nomes das estrategias
bool           g_stratActive[MAX_STRATEGIES];                         // estado ativo/inativo
int            g_stratCount    = 0;                                   // qtd estrategias registradas

//--- Performance cache (atualizado periodicamente) ---
double         g_eaProfit      = 0;                                   // lucro total EA hoje
double         g_eaLoss        = 0;                                   // perda total EA hoje
int            g_eaWins        = 0;                                   // trades vencedores EA
int            g_eaLosses      = 0;                                   // trades perdedores EA
double         g_manualProfit  = 0;                                   // lucro total manual hoje
double         g_manualLoss    = 0;                                   // perda total manual hoje
int            g_manualWins    = 0;                                   // trades manuais vencedores
int            g_manualLosses  = 0;                                   // trades manuais perdedores

//--- FASE A: Metricas avancadas (calculadas no UpdatePerformanceData) ---
double         g_maxDrawdown   = 0;                                   // drawdown maximo do dia
double         g_curDrawdown   = 0;                                   // drawdown atual
double         g_peakBalance   = 0;                                   // pico de balanco no dia
double         g_recoveryFact  = 0;                                   // fator de recuperacao (net/maxDD)
int            g_consecWins    = 0;                                   // sequencia atual de wins
int            g_consecLosses  = 0;                                   // sequencia atual de losses
double         g_bestTrade     = 0;                                   // melhor trade do dia
double         g_worstTrade    = 0;                                   // pior trade do dia
double         g_avgDuration   = 0;                                   // duracao media em segundos
double         g_totalBalance  = 0;                                   // balanco total da conta
datetime       g_lastTradeTime = 0;                                   // hora do ultimo trade fechado
datetime       g_lastUpdateTime = 0;                                  // hora da ultima atualizacao

//--- FASE C: Inteligencia (calculadas no UpdateIntelligenceData) ---
double         g_sessionProfit[4];                                    // lucro por sessao [Sydney,Tokyo,London,NY]
int            g_sessionTrades[4];                                    // trades por sessao
double         g_weekdayProfit[5];                                    // lucro por dia [Seg-Sex]
int            g_weekdayTrades[5];                                    // trades por dia
double         g_dailyLossLimit = -5000;                              // limite de perda diaria (configuravel)
bool           g_dailyLossAlert = false;                              // alerta ativo?
double         g_qualityScore  = 0;                                   // score 0-100 de qualidade operacional
double         g_avgPnL5d      = 0;                                   // media P&L ultimos 5 dias
double         g_avgPnL20d     = 0;                                   // media P&L ultimos 20 dias

//--- Curva P&L (ultimos N pontos para o grafico) ---
#define PNL_POINTS         48                                         // pontos na curva P&L
double         g_pnlCurve[PNL_POINTS];                               // valores da curva
int            g_pnlCount      = 0;                                   // pontos preenchidos

//--- Filtros da aba Relatorios ---
int            g_reportFilter  = 0;                                   // 0=Hoje, 1=Semana, 2=Mes, 3=Ano

//--- FASE D: SENSORES MKS FRAMEWORK ---
#define SENSOR_COUNT 6                                                 // total de sensores

struct SensorInfo
{
   string name;                                                       // VOL, BB, CE, SLOPE, REV, CONSENSUS
   string displayName;                                                // texto exibido
   string gvKey;                                                      // chave base GlobalVariable
   int    status;                                                     // 0=dev(cinza), 1=notfound(amarelo), 2=loaded(verde)
   bool   enabled;                                                    // toggle ON/OFF
   double value;                                                      // 0-100 score principal
   double signal;                                                     // +1/-1/0
   string valueLbl;                                                   // label "Score", "Dominancia", etc
   string signalLbl;                                                  // "LIBERADO", "BULL", etc
   color  accentClr;                                                  // cor unica do card
};
SensorInfo g_sensors[SENSOR_COUNT];                                   // array de sensores

//--- FASE D: CALENDARIO ECONOMICO REAL (via MT5 Calendar API) ---
#define MAX_CAL_EVENTS 50                                              // maximo de eventos armazenados

struct CalendarEventData
{
   datetime eventTime;                                                // hora raw (servidor)
   string   timeStr;                                                  // "HH:MM" no fuso usuario
   string   currency;                                                 // USD, EUR, JPY, etc
   int      importance;                                               // 1=low 2=med 3=high
   string   name;                                                     // nome do evento
   string   actual;                                                   // valor real publicado
   string   forecast;                                                 // previsto
   string   previous;                                                 // anterior
   bool     actualBetter;                                             // true se actual > forecast
   bool     hasActual;                                                // se ja foi publicado
};
CalendarEventData g_calEvents[MAX_CAL_EVENTS];                        // array de eventos
int                g_calCount         = 0;                            // eventos carregados
datetime           g_calLastUpdate    = 0;                            // timestamp ultima atualizacao
int                g_calMinImportance = 2;                            // filtro: minimo MED (2)


//=====================================================================
// [5] FUNCOES AUXILIARES — OBJETOS GRAFICOS
// Cada funcao cria um tipo de objeto MT5 com prefixo unico.
// Todas configuram HIDDEN=true e SELECTABLE=false para nao
// interferir na interacao do usuario com o grafico.
//=====================================================================

//--- Gera nome completo do objeto com prefixo ---
string N(string name) { return OBJ_PREFIX + name; }                   // shortcut para prefixo

//--- Cria retangulo (card, fundo, separador) ---
void Rect(string name, int x, int y, int w, int h, color bg, color border = CLR_NONE, int borderW = 0)
{
   string obj = N(name);                                              // nome com prefixo
   ObjectCreate(0, obj, OBJ_RECTANGLE_LABEL, 0, 0, 0);              // cria objeto retangulo
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);      // ancora no canto superior esquerdo
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);                  // posicao X
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);                  // posicao Y
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);                      // largura
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);                      // altura
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);                   // cor de fundo
   ObjectSetInteger(0, obj, OBJPROP_BORDER_TYPE, BORDER_FLAT);      // borda plana
   if(border != CLR_NONE)                                            // se tem cor de borda
      ObjectSetInteger(0, obj, OBJPROP_COLOR, border);               // aplica cor da borda
   else
      ObjectSetInteger(0, obj, OBJPROP_COLOR, bg);                   // borda = fundo (invisivel)
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, borderW > 0 ? borderW : 1); // espessura da borda
   ObjectSetInteger(0, obj, OBJPROP_BACK, false);                   // nao fica atras do grafico
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);             // nao selecionavel
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);                  // oculto na lista de objetos
}

//--- Cria label de texto ---
void Label(string name, int x, int y, string text, color clr, int fontSize, string font = "Segoe UI")
{
   string obj = N(name);                                              // nome com prefixo
   ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);                        // cria objeto label
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);      // ancora no canto superior esquerdo
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);                  // posicao X
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);                  // posicao Y
   ObjectSetString(0, obj, OBJPROP_TEXT, text);                      // texto do label
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);                    // cor do texto
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fontSize);            // tamanho da fonte
   ObjectSetString(0, obj, OBJPROP_FONT, font);                     // familia da fonte
   ObjectSetInteger(0, obj, OBJPROP_BACK, false);                   // nao fica atras
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);             // nao selecionavel
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);                  // oculto na lista
}

//--- Cria botao clicavel ---
void Btn(string name, int x, int y, int w, int h, string text, color bg, color txt, int fontSize = 8)
{
   string obj = N(name);                                              // nome com prefixo
   ObjectCreate(0, obj, OBJ_BUTTON, 0, 0, 0);                       // cria objeto botao
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);      // ancora canto superior esquerdo
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, x);                  // posicao X
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, y);                  // posicao Y
   ObjectSetInteger(0, obj, OBJPROP_XSIZE, w);                      // largura
   ObjectSetInteger(0, obj, OBJPROP_YSIZE, h);                      // altura
   ObjectSetString(0, obj, OBJPROP_TEXT, text);                      // texto do botao
   ObjectSetInteger(0, obj, OBJPROP_BGCOLOR, bg);                   // cor de fundo
   ObjectSetInteger(0, obj, OBJPROP_COLOR, txt);                    // cor do texto
   ObjectSetInteger(0, obj, OBJPROP_BORDER_COLOR, CLR_BORDER);      // cor da borda
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fontSize);            // tamanho fonte
   ObjectSetString(0, obj, OBJPROP_FONT, "Segoe UI");               // fonte do botao
   ObjectSetInteger(0, obj, OBJPROP_BACK, false);                   // nao fica atras
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);             // nao selecionavel
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);                  // oculto
   ObjectSetInteger(0, obj, OBJPROP_STATE, false);                  // estado inicial nao pressionado
}

//--- Atualiza texto de um label existente ---
void UpdLabel(string name, string text)
{
   string obj = N(name);                                              // nome com prefixo
   if(ObjectFind(0, obj) >= 0)                                       // se objeto existe
      ObjectSetString(0, obj, OBJPROP_TEXT, text);                   // atualiza texto
}

//--- Atualiza cor de um label existente ---
void UpdColor(string name, color clr)
{
   string obj = N(name);                                              // nome com prefixo
   if(ObjectFind(0, obj) >= 0)                                       // se objeto existe
      ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);                 // atualiza cor
}

//--- Mostra ou oculta um objeto ---
void ShowObj(string name, bool visible)
{
   string obj = N(name);                                              // nome com prefixo
   if(ObjectFind(0, obj) >= 0)                                       // se objeto existe
      ObjectSetInteger(0, obj, OBJPROP_TIMEFRAMES,                   // define visibilidade
         visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
}

//--- Deleta todos os objetos do painel ---
void DeleteAll()
{
   int total = ObjectsTotal(0);                                      // conta objetos no grafico
   for(int i = total - 1; i >= 0; i--)                               // percorre de tras pra frente
   {
      string name = ObjectName(0, i);                                 // nome do objeto
      if(StringFind(name, OBJ_PREFIX) == 0)                          // se tem nosso prefixo
         ObjectDelete(0, name);                                       // deleta
   }
}

//--- Limpa conteudo das abas (prefixo "C_") ---
void ClearContent()
{
   int total = ObjectsTotal(0);                                      // conta objetos
   for(int i = total - 1; i >= 0; i--)                               // percorre de tras pra frente
   {
      string name = ObjectName(0, i);                                 // nome do objeto
      if(StringFind(name, OBJ_PREFIX + "C_") == 0)                  // se eh conteudo de aba
         ObjectDelete(0, name);                                       // deleta
   }
}


//=====================================================================
// [6] FUNCOES AUXILIARES — CARDS E VISUAL
// Sistema de cards com sombra simulada para efeito SaaS.
// Card = sombra (rect escuro offset) + fundo + borda superior acento.
//=====================================================================

//--- Cria um card com sombra e borda ---
void Card(string name, int x, int y, int w, int h, bool accentTop = false, color accentClr = CLR_ACCENT_BLUE)
{
   //--- Sombra (retangulo mais escuro offset para baixo e direita) ---
   Rect(name + "_shd", x + SHADOW_OFFSET, y + SHADOW_OFFSET, w, h, CLR_BG_SHADOW);  // sombra

   //--- Fundo do card ---
   Rect(name + "_bg", x, y, w, h, CLR_BG_CARD, CLR_BORDER, CARD_BORDER_W);          // card principal

   //--- Linha de acento no topo do card (2px de altura) ---
   if(accentTop)                                                      // se quer linha de acento
      Rect(name + "_acc", x + 1, y + 1, w - 2, 2, accentClr);      // linha colorida no topo
}

//--- Cria um titulo de secao com linha de acento abaixo ---
void SectionTitle(string name, int x, int y, string text, color clr = CLR_ACCENT_BLUE, int width = 0)
{
   Label(name + "_txt", x, y, text, clr, g_fontSection, "Segoe UI Semibold");  // texto do titulo
   int lineW = (width > 0) ? width : g_panelW - 2 * MARGIN;                     // largura da linha
   Rect(name + "_line", x, y + g_fontSection + 4, lineW, 1, clr);              // linha de acento
}

//--- Cria um par label/valor alinhado ---
void LabelValue(string name, int x, int y, string label, string value,
                color lblClr = CLR_TEXT_DIM, color valClr = CLR_TEXT_LIGHT,
                int valX = 0)
{
   int vx = (valX > 0) ? valX : x + 180;                            // posicao X do valor (aumentada)
   Label(name + "_l", x, y, label, lblClr, g_fontSmall, "Segoe UI");           // label
   Label(name + "_v", vx, y, value, valClr, g_fontNormal, "Segoe UI");        // valor
}

//--- Cria badge de status (pequeno retangulo com texto) ---
void Badge(string name, int x, int y, string text, color bg, color txt = CLR_TEXT_WHITE)
{
   int w = StringLen(text) * 7 + 12;                                 // largura estimada
   Rect(name + "_bg", x, y, w, 18, bg);                             // fundo do badge
   Label(name + "_txt", x + 6, y + 2, text, txt, g_fontSmall - 1, "Segoe UI Semibold");  // texto
}

//--- Cria barra de progresso horizontal ---
void ProgressBar(string name, int x, int y, int w, int h, double pct, color fillClr = CLR_BAR_GREEN)
{
   Rect(name + "_bg", x, y, w, h, CLR_BAR_BG);                     // fundo da barra
   int fillW = (int)MathMax(1, MathMin(w, w * pct / 100.0));        // largura proporcional
   Rect(name + "_fill", x, y, fillW, h, fillClr);                   // preenchimento
}


//=====================================================================
// [7] FUNCOES AUXILIARES — FORMATACAO
// Formata precos, inteiros e datas no padrao brasileiro.
//=====================================================================

//--- Formata preco: 71000.25 -> "71.000,25" ---
string FmtPrice(double value, int digits)
{
   string raw = DoubleToString(MathAbs(value), digits);              // converte para string
   string sign = (value < 0.0) ? "-" : "";                          // sinal negativo se necessario

   int dotPos = StringFind(raw, ".");                                // posicao do ponto decimal
   string intPart = "", decPart = "";                                // partes inteira e decimal

   if(dotPos >= 0)                                                   // se tem ponto decimal
   {
      intPart = StringSubstr(raw, 0, dotPos);                        // parte inteira
      decPart = StringSubstr(raw, dotPos + 1);                       // parte decimal
   }
   else intPart = raw;                                               // sem decimal

   string formatted = "";                                            // resultado formatado
   int len = StringLen(intPart);                                     // tamanho da parte inteira

   for(int i = 0; i < len; i++)                                     // percorre cada digito
   {
      int posFromRight = len - i;                                    // posicao da direita
      if(i > 0 && posFromRight % 3 == 0) formatted += ".";          // separador de milhar
      formatted += StringSubstr(intPart, i, 1);                     // adiciona digito
   }

   if(decPart != "") return sign + formatted + "," + decPart;       // com decimal
   return sign + formatted;                                          // sem decimal
}

//--- Formata inteiro com separador de milhar ---
string FmtInt(int value)
{
   string raw = IntegerToString(MathAbs(value));                     // converte para string
   string sign = (value < 0) ? "-" : "";                            // sinal negativo
   string formatted = "";                                            // resultado
   int len = StringLen(raw);                                         // tamanho

   for(int i = 0; i < len; i++)                                     // percorre digitos
   {
      int posFromRight = len - i;                                    // posicao da direita
      if(i > 0 && posFromRight % 3 == 0) formatted += ".";          // separador
      formatted += StringSubstr(raw, i, 1);                         // digito
   }
   return sign + formatted;                                          // resultado final
}

//--- Formata winrate como porcentagem ---
string FmtWinRate(int wins, int total)
{
   if(total == 0) return "0%";                                       // evita divisao por zero
   double rate = (double)wins / total * 100.0;                       // calcula porcentagem
   return DoubleToString(rate, 1) + "%";                             // formata com 1 decimal
}

//--- Retorna hora do servidor ajustada pelo fuso ---
string GetServerTimeFormatted()
{
   datetime serverTime = TimeCurrent();                               // hora do servidor
   datetime adjusted = serverTime + g_tzShift * 3600;                // ajusta fuso horario
   MqlDateTime dt;                                                   // estrutura de data/hora
   TimeToStruct(adjusted, dt);                                       // decompoe
   return StringFormat("%02d:%02d:%02d", dt.hour, dt.min, dt.sec);  // formata 24h
}

//--- Retorna data formatada ---
string GetDateFormatted()
{
   datetime serverTime = TimeCurrent();                               // hora do servidor
   datetime adjusted = serverTime + g_tzShift * 3600;                // ajusta fuso
   MqlDateTime dt;                                                   // estrutura
   TimeToStruct(adjusted, dt);                                       // decompoe
   return StringFormat("%02d/%02d/%04d", dt.day, dt.mon, dt.year);   // formato DD/MM/YYYY
}

//--- Retorna simbolo da moeda da conta (USD, JPY, EUR etc) ---
string GetAccountCurrency()
{
   return AccountInfoString(ACCOUNT_CURRENCY);                        // moeda da conta na corretora
}

//--- Formata valor monetario com SIMBOLO da moeda (¥, $, etc) ---
string FmtMoney(double value)
{
   int decimals = 2;                                                  // default: 2 casas
   if(g_acctCurrency == "JPY" || g_acctCurrency == "KRW" ||
      g_acctCurrency == "HUF" || g_acctCurrency == "VND")
      decimals = 0;                                                   // moedas sem centavos

   string raw = DoubleToString(MathAbs(value), decimals);
   string sign = (value < 0.0) ? "-" : (value > 0.0) ? "+" : "";

   //--- Separa parte inteira e decimal ---
   int dotPos = StringFind(raw, ".");
   string intPart = (dotPos >= 0) ? StringSubstr(raw, 0, dotPos) : raw;
   string decPart = (dotPos >= 0) ? StringSubstr(raw, dotPos + 1) : "";

   //--- Separador de milhar ---
   string formatted = "";
   int len = StringLen(intPart);
   for(int i = 0; i < len; i++)
   {
      int posFromRight = len - i;
      if(i > 0 && posFromRight % 3 == 0) formatted += ",";
      formatted += StringSubstr(intPart, i, 1);
   }

   //--- Monta com decimal ---
   string result = sign + formatted;
   if(decPart != "") result += "." + decPart;

   //--- Simbolo da moeda (ao inves do codigo) ---
   string sym = g_acctCurrency;                                      // fallback: codigo
   if(g_acctCurrency == "JPY") sym = "\x00A5";                      // ¥
   else if(g_acctCurrency == "USD") sym = "$";                       // $
   else if(g_acctCurrency == "EUR") sym = "\x20AC";                  // €
   else if(g_acctCurrency == "GBP") sym = "\x00A3";                  // £
   else if(g_acctCurrency == "BRL") sym = "R$";                      // R$
   else if(g_acctCurrency == "CHF") sym = "CHF";                     // CHF
   else if(g_acctCurrency == "AUD") sym = "A$";                      // A$
   else if(g_acctCurrency == "CAD") sym = "C$";                      // C$

   return result + " " + sym;                                        // ex: "+1,234 ¥" ou "-5,678.90 $"
}


//=====================================================================
// [8] DETECCAO DE SESSOES DE MERCADO
// Retorna dados das 4 sessoes principais com horarios UTC.
//=====================================================================

struct SessionInfo                                                   // informacoes de uma sessao
{
   string name;                                                      // nome da sessao
   int    openHour;                                                  // hora UTC de abertura
   int    closeHour;                                                 // hora UTC de fechamento
   color  clr;                                                       // cor da sessao
   bool   isActive;                                                  // esta ativa agora?
};

//--- Preenche informacoes das sessoes (usando hora ajustada pelo fuso) ---
void GetSessions(SessionInfo &sessions[])
{
   ArrayResize(sessions, 4);                                         // 4 sessoes
   datetime now = TimeCurrent() + g_tzShift * 3600;                  // hora ajustada pelo fuso (Japao)
   MqlDateTime dt;                                                   // estrutura de data/hora
   TimeToStruct(now, dt);                                            // decompoe
   int h = dt.hour;                                                  // hora atual no fuso configurado

   //--- Horarios convertidos para o fuso local (UTC + g_tzShift) ---
   //--- Os horarios abaixo sao em UTC, convertemos para o fuso ---

   //--- Sydney (UTC 22:00-07:00 = JST 07:00-16:00) ---
   int sydOpen  = (22 + g_tzShift) % 24;                            // abertura no fuso local
   int sydClose = (7  + g_tzShift) % 24;                            // fechamento no fuso local
   sessions[0].name      = "SYDNEY";
   sessions[0].openHour  = sydOpen;
   sessions[0].closeHour = sydClose;
   sessions[0].clr       = CLR_ACCENT_ORANGE;
   sessions[0].isActive  = (sydOpen > sydClose) ? (h >= sydOpen || h < sydClose) : (h >= sydOpen && h < sydClose);

   //--- Tokyo (UTC 00:00-09:00 = JST 09:00-18:00) ---
   int tokOpen  = (0 + g_tzShift) % 24;
   int tokClose = (9 + g_tzShift) % 24;
   sessions[1].name      = "TOKYO";
   sessions[1].openHour  = tokOpen;
   sessions[1].closeHour = tokClose;
   sessions[1].clr       = CLR_ACCENT_RED;
   sessions[1].isActive  = (tokOpen > tokClose) ? (h >= tokOpen || h < tokClose) : (h >= tokOpen && h < tokClose);

   //--- London (UTC 08:00-17:00 = JST 17:00-02:00) ---
   int lonOpen  = (8  + g_tzShift) % 24;
   int lonClose = (17 + g_tzShift) % 24;
   sessions[2].name      = "LONDON";
   sessions[2].openHour  = lonOpen;
   sessions[2].closeHour = lonClose;
   sessions[2].clr       = CLR_ACCENT_BLUE;
   sessions[2].isActive  = (lonOpen > lonClose) ? (h >= lonOpen || h < lonClose) : (h >= lonOpen && h < lonClose);

   //--- New York (UTC 13:00-22:00 = JST 22:00-07:00) ---
   int nyOpen  = (13 + g_tzShift) % 24;
   int nyClose = (22 + g_tzShift) % 24;
   sessions[3].name      = "NEW YORK";
   sessions[3].openHour  = nyOpen;
   sessions[3].closeHour = nyClose;
   sessions[3].clr       = CLR_ACCENT_CYAN;
   sessions[3].isActive  = (nyOpen > nyClose) ? (h >= nyOpen || h < nyClose) : (h >= nyOpen && h < nyClose);
}

//--- Calcula tempo restante em hh:mm ate um horario alvo ---
string GetTimeRemaining(int targetHour, int currentHour, int currentMin)
{
   int diffH = targetHour - currentHour;                             // diferenca em horas
   if(diffH < 0) diffH += 24;                                       // ajusta positivo
   int diffM = 60 - currentMin;                                     // minutos restantes da hora atual
   if(diffM == 60) { diffM = 0; }                                   // se exato
   else { diffH--; if(diffH < 0) diffH = 23; }                     // desconta 1h pelos minutos
   return StringFormat("%02d:%02d", diffH, diffM);                   // formata hh:mm
}

//--- Monta texto completo das sessoes para exibicao no dashboard ---
string BuildSessionText()
{
   SessionInfo sessions[];                                            // array de sessoes
   GetSessions(sessions);                                             // preenche

   datetime now = TimeCurrent() + g_tzShift * 3600;                  // hora no fuso
   MqlDateTime dt;
   TimeToStruct(now, dt);
   int curH = dt.hour;                                               // hora atual
   int curM = dt.min;                                                // minuto atual

   //--- Monta texto das sessoes ativas ---
   string activeText = "";
   for(int i = 0; i < 4; i++)
   {
      if(sessions[i].isActive)
      {
         string rem = GetTimeRemaining(sessions[i].closeHour, curH, curM);
         if(activeText != "") activeText += "  |  ";
         activeText += sessions[i].name + " termina em " + rem;
      }
   }

   //--- Encontra proxima sessao a abrir ---
   string nextText = "";
   int bestDiff = 999;
   for(int i = 0; i < 4; i++)
   {
      if(!sessions[i].isActive)
      {
         int diff = sessions[i].openHour - curH;
         if(diff < 0) diff += 24;
         if(diff < bestDiff)
         {
            bestDiff = diff;
            string opens = GetTimeRemaining(sessions[i].openHour, curH, curM);
            nextText = "Proxima: " + sessions[i].name + " em " + opens;
         }
      }
   }

   //--- Combina ativas + proxima ---
   if(activeText == "") return "Mercado FECHADO  |  " + nextText;
   if(nextText != "") activeText += "  |  " + nextText;
   return activeText;
}


//=====================================================================
// [9] DETECCAO DO FRAMEWORK RENKO
// Le configuracoes do LiveEngine via objeto escondido no grafico.
// Fallback: busca Custom Symbol por prefixo no Market Watch.
//=====================================================================

void DetectFramework()
{
   string infoName = "MKS_LiveEngine_CSName";                        // nome do objeto info

   if(ObjectFind(0, infoName) >= 0)                                  // se objeto existe
   {
      string infoText = ObjectGetString(0, infoName, OBJPROP_TEXT); // le texto do objeto
      string parts[];                                                // array para split
      int count = StringSplit(infoText, '|', parts);                 // split por pipe

      if(count >= 10)                                                // formato completo
      {
         g_csName       = parts[0];                                  // nome do CS
         g_fwPreset     = (int)StringToInteger(parts[1]);            // preset
         g_fwBrickSize  = StringToDouble(parts[2]);                  // brick size
         g_fwSizeMode   = (int)StringToInteger(parts[3]);            // modo size
         g_fwPO         = StringToDouble(parts[4]);                  // pO
         g_fwPRO        = StringToDouble(parts[5]);                  // pRO
         g_fwRevSizePct = StringToDouble(parts[6]);                  // revSizePct
         g_fwDataSource = (int)StringToInteger(parts[7]);            // fonte dados
         g_fwWicks      = (parts[8] == "1");                         // wicks
         g_fwSz         = StringToDouble(parts[9]);                  // sz
         g_frameworkOk  = true;                                      // framework OK
         return;
      }
      else if(count >= 1 && parts[0] != "")                         // formato antigo
      {
         g_csName      = parts[0];                                   // so nome
         g_frameworkOk = true;                                       // OK
         return;
      }
   }

   //--- Fallback: busca por prefixo no Market Watch ---
   string prefix = "MKS_" + g_symbol + "_";                         // prefixo esperado
   string bestCS = "";                                               // melhor CS encontrado
   datetime bestTime = 0;                                            // timestamp mais recente

   int totalSymbols = SymbolsTotal(true);                            // total no Market Watch
   for(int i = 0; i < totalSymbols; i++)                             // percorre todos
   {
      string symName = SymbolName(i, true);                          // nome do simbolo
      if(StringFind(symName, prefix) == 0)                           // se tem prefixo MKS
      {
         MqlRates checkRates[];                                      // buffer para rates
         ArraySetAsSeries(checkRates, true);                         // ordem cronologica
         int copied = CopyRates(symName, PERIOD_M1, 0, 1, checkRates);  // le ultima barra
         if(copied > 0 && checkRates[0].time > bestTime)             // mais recente?
         {
            bestTime = checkRates[0].time;                           // atualiza melhor
            bestCS   = symName;                                      // atualiza CS
         }
         else if(bestCS == "" && copied <= 0) bestCS = symName;      // unico disponivel
      }
   }

   if(bestCS != "") { g_csName = bestCS; g_frameworkOk = true; }    // encontrou
   else { g_csName = ""; g_frameworkOk = false; }                    // nao encontrou
}


//=====================================================================
// [10] COLETA DE DADOS DE PERFORMANCE
// Varre HistoryDealSelect para calcular P&L do dia, separando
// trades do EA (com magic number) e trades manuais (magic=0).
//=====================================================================

void UpdatePerformanceData()
{
   //--- Reseta contadores basicos ---
   g_eaProfit = 0; g_eaLoss = 0; g_eaWins = 0; g_eaLosses = 0;
   g_manualProfit = 0; g_manualLoss = 0; g_manualWins = 0; g_manualLosses = 0;

   //--- Reseta metricas avancadas ---
   g_bestTrade = 0; g_worstTrade = 0;
   g_consecWins = 0; g_consecLosses = 0;
   g_avgDuration = 0; g_maxDrawdown = 0; g_curDrawdown = 0;
   g_totalBalance = AccountInfoDouble(ACCOUNT_BALANCE);              // balanco atual

   //--- Periodo: desde meia-noite do servidor ---
   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   dtNow.hour = 0; dtNow.min = 0; dtNow.sec = 0;
   datetime startOfDay = StructToTime(dtNow);

   //--- Seleciona historico de deals do dia ---
   if(!HistorySelect(startOfDay, TimeCurrent())) return;

   int totalDeals = HistoryDealsTotal();
   double runningPnL = 0;                                             // P&L acumulado para drawdown
   g_peakBalance = 0;                                                 // pico do P&L acumulado
   double totalDuration = 0;                                          // duracao total em segundos
   int closedTrades = 0;                                              // total de trades fechados
   int lastResult = 0;                                                // 1=win, -1=loss
   int currentStreak = 0;                                             // sequencia atual

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

      string dealSymbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      if(dealSymbol != g_symbol) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP);
      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);

      //--- Classificacao EA vs Manual ---
      if(magic > 0)
      {
         if(profit >= 0) { g_eaProfit += profit; g_eaWins++; }
         else            { g_eaLoss += profit; g_eaLosses++; }
      }
      else
      {
         if(profit >= 0) { g_manualProfit += profit; g_manualWins++; }
         else            { g_manualLoss += profit; g_manualLosses++; }
      }

      //--- Melhor e pior trade ---
      if(profit > g_bestTrade)  g_bestTrade = profit;
      if(profit < g_worstTrade) g_worstTrade = profit;

      //--- Sequencia consecutiva wins/losses ---
      int thisResult = (profit >= 0) ? 1 : -1;
      if(thisResult == lastResult) currentStreak++;
      else                         currentStreak = 1;
      lastResult = thisResult;

      //--- Drawdown (P&L acumulado) ---
      runningPnL += profit;
      if(runningPnL > g_peakBalance) g_peakBalance = runningPnL;
      double dd = g_peakBalance - runningPnL;
      if(dd > g_maxDrawdown) g_maxDrawdown = dd;

      //--- Duracao do trade (via posicao no historico) ---
      long posID = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      if(posID > 0 && HistorySelectByPosition(posID))
      {
         int dCount = HistoryDealsTotal();
         if(dCount >= 2)
         {
            ulong openTicket = HistoryDealGetTicket(0);
            ulong closeTicket = HistoryDealGetTicket(dCount - 1);
            if(openTicket > 0 && closeTicket > 0)
            {
               datetime openTime = (datetime)HistoryDealGetInteger(openTicket, DEAL_TIME);
               datetime closeTime = (datetime)HistoryDealGetInteger(closeTicket, DEAL_TIME);
               totalDuration += (double)(closeTime - openTime);
               closedTrades++;
               if(closeTime > g_lastTradeTime) g_lastTradeTime = closeTime;
            }
         }
         //--- Re-seleciona o periodo do dia (HistorySelectByPosition muda a selecao) ---
         HistorySelect(startOfDay, TimeCurrent());
      }
   }

   //--- Sequencia final ---
   if(lastResult == 1) { g_consecWins = currentStreak; g_consecLosses = 0; }
   else if(lastResult == -1) { g_consecLosses = currentStreak; g_consecWins = 0; }

   //--- Drawdown atual ---
   double netPnL = g_eaProfit + g_eaLoss + g_manualProfit + g_manualLoss;
   g_curDrawdown = g_peakBalance - (runningPnL);
   if(g_curDrawdown < 0) g_curDrawdown = 0;

   //--- Fator de recuperacao ---
   g_recoveryFact = (g_maxDrawdown > 0) ? netPnL / g_maxDrawdown : 0;

   //--- Duracao media ---
   g_avgDuration = (closedTrades > 0) ? totalDuration / closedTrades : 0;

   //--- Timestamp da ultima atualizacao ---
   g_lastUpdateTime = TimeCurrent();
}


//=====================================================================
// [10b] FASE C: COLETA DE DADOS DE INTELIGENCIA
// Analise por sessao, heatmap semanal, quality score, daily loss.
//=====================================================================

void UpdateIntelligenceData()
{
   //--- Reseta arrays ---
   ArrayInitialize(g_sessionProfit, 0.0);
   ArrayInitialize(g_sessionTrades, 0);
   ArrayInitialize(g_weekdayProfit, 0.0);
   ArrayInitialize(g_weekdayTrades, 0);

   //--- Periodo: ultimos 30 dias para historico ---
   datetime endTime = TimeCurrent();
   datetime startTime = endTime - 30 * 86400;                        // 30 dias atras

   if(!HistorySelect(startTime, endTime)) return;

   double dailyPnL[];                                                // P&L por dia
   ArrayResize(dailyPnL, 30);
   ArrayInitialize(dailyPnL, 0.0);

   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

      string dealSym = HistoryDealGetString(ticket, DEAL_SYMBOL);
      if(dealSym != g_symbol) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP);

      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      datetime adjTime = dealTime + g_tzShift * 3600;                // ajusta fuso
      MqlDateTime dt;
      TimeToStruct(adjTime, dt);

      //--- Analise por sessao (baseado na hora do fuso) ---
      int h = dt.hour;
      // Mapeia hora para sessao (usando horarios locais do fuso)
      int sydOpen  = (22 + g_tzShift) % 24, sydClose = (7 + g_tzShift) % 24;
      int tokOpen  = (0 + g_tzShift) % 24,  tokClose = (9 + g_tzShift) % 24;
      int lonOpen  = (8 + g_tzShift) % 24,  lonClose = (17 + g_tzShift) % 24;
      int nyOpen   = (13 + g_tzShift) % 24, nyClose  = (22 + g_tzShift) % 24;

      bool inSyd = (sydOpen > sydClose) ? (h >= sydOpen || h < sydClose) : (h >= sydOpen && h < sydClose);
      bool inTok = (tokOpen > tokClose) ? (h >= tokOpen || h < tokClose) : (h >= tokOpen && h < tokClose);
      bool inLon = (lonOpen > lonClose) ? (h >= lonOpen || h < lonClose) : (h >= lonOpen && h < lonClose);
      bool inNY  = (nyOpen > nyClose)   ? (h >= nyOpen || h < nyClose)   : (h >= nyOpen && h < nyClose);

      if(inSyd) { g_sessionProfit[0] += profit; g_sessionTrades[0]++; }
      if(inTok) { g_sessionProfit[1] += profit; g_sessionTrades[1]++; }
      if(inLon) { g_sessionProfit[2] += profit; g_sessionTrades[2]++; }
      if(inNY)  { g_sessionProfit[3] += profit; g_sessionTrades[3]++; }

      //--- Analise por dia da semana (0=dom, 1=seg... 5=sex) ---
      if(dt.day_of_week >= 1 && dt.day_of_week <= 5)
      {
         g_weekdayProfit[dt.day_of_week - 1] += profit;
         g_weekdayTrades[dt.day_of_week - 1]++;
      }

      //--- P&L por dia (para media) ---
      int daysAgo = (int)((endTime - dealTime) / 86400);
      if(daysAgo >= 0 && daysAgo < 30)
         dailyPnL[daysAgo] += profit;
   }

   //--- Media P&L ultimos 5 e 20 dias ---
   double sum5 = 0, sum20 = 0;
   int cnt5 = 0, cnt20 = 0;
   for(int d = 0; d < 30; d++)
   {
      if(d < 5  && dailyPnL[d] != 0) { sum5  += dailyPnL[d]; cnt5++; }
      if(d < 20 && dailyPnL[d] != 0) { sum20 += dailyPnL[d]; cnt20++; }
   }
   g_avgPnL5d  = (cnt5 > 0) ? sum5 / cnt5 : 0;
   g_avgPnL20d = (cnt20 > 0) ? sum20 / cnt20 : 0;

   //--- Daily loss alert ---
   double todayPnL = g_eaProfit + g_eaLoss + g_manualProfit + g_manualLoss;
   g_dailyLossAlert = (todayPnL < g_dailyLossLimit);

   //--- Quality Score (0-100) ---
   // Baseado em: winrate (40%), profit factor (30%), spread/ATR ratio (15%), velocidade (15%)
   int totalTrades = g_eaWins + g_eaLosses + g_manualWins + g_manualLosses;
   double wr = (totalTrades > 0) ? (double)(g_eaWins + g_manualWins) / totalTrades : 0.5;
   double pf = (MathAbs(g_eaLoss + g_manualLoss) > 0) ?
      (g_eaProfit + g_manualProfit) / MathAbs(g_eaLoss + g_manualLoss) : 1.0;

   double wrScore = MathMin(100, wr * 200);                          // 50%wr=100, 0%=0
   double pfScore = MathMin(100, pf * 33.3);                         // PF 3.0=100
   double spdScore = MathMin(100, g_ticksPerMin * 1.5);             // 67 tpm=100
   double spreadScore = 100;                                         // default bom
   double tSize = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tSize > 0)
   {
      double spread = SymbolInfoDouble(g_symbol, SYMBOL_ASK) - SymbolInfoDouble(g_symbol, SYMBOL_BID);
      double atrVal = 0;
      if(g_hATR_D1 != INVALID_HANDLE)
      {
         double buf[]; ArraySetAsSeries(buf, true);
         if(CopyBuffer(g_hATR_D1, 0, 0, 1, buf) > 0) atrVal = buf[0];
      }
      if(atrVal > 0) spreadScore = MathMin(100, (1.0 - spread / atrVal) * 100);
   }

   g_qualityScore = wrScore * 0.40 + pfScore * 0.30 + spreadScore * 0.15 + spdScore * 0.15;
   if(g_qualityScore > 100) g_qualityScore = 100;
   if(g_qualityScore < 0) g_qualityScore = 0;
}


//=====================================================================
// [10c] FASE D: SENSORES MKS FRAMEWORK
// Integracao com sensores via GlobalVariables. Cada sensor e um
// card independente no dashboard com barra gradiente termometro.
//=====================================================================

//--- Gradiente de cor (0=vermelho -> 100=azul, passando por amarelo/cyan) ---
color GetSensorGradientColor(double value)
{
   if(value < 0)   value = 0;
   if(value > 100) value = 100;

   //--- 5 stops de cor: red -> orange -> yellow -> cyan -> blue ---
   color stops[5];
   stops[0] = C'239,68,68';                                          // red (0%)
   stops[1] = C'249,115,22';                                         // orange (25%)
   stops[2] = C'234,179,8';                                          // yellow (50%)
   stops[3] = C'6,182,212';                                          // cyan (75%)
   stops[4] = C'59,130,246';                                         // blue (100%)

   double pct = value / 100.0;                                       // 0..1
   double segIdx = pct * 4.0;                                        // 0..4
   int idx = (int)MathFloor(segIdx);
   if(idx >= 4) return stops[4];                                     // edge: 100%
   double t = segIdx - idx;                                          // 0..1 dentro do segmento

   //--- Extrai RGB de cada stop ---
   int r1 = (int)(stops[idx] & 0xFF);
   int g1 = (int)((stops[idx] >> 8) & 0xFF);
   int b1 = (int)((stops[idx] >> 16) & 0xFF);
   int r2 = (int)(stops[idx+1] & 0xFF);
   int g2 = (int)((stops[idx+1] >> 8) & 0xFF);
   int b2 = (int)((stops[idx+1] >> 16) & 0xFF);

   //--- Interpolacao linear ---
   int r = (int)(r1 + (r2 - r1) * t);
   int g = (int)(g1 + (g2 - g1) * t);
   int b = (int)(b1 + (b2 - b1) * t);

   return (color)(r | (g << 8) | (b << 16));                        // monta cor final
}

//--- Inicializa o array de sensores ---
void InitSensors()
{
   //--- Sensor 0: Volatilidade ---
   g_sensors[0].name        = "VOL";
   g_sensors[0].displayName = "VOLATILIDADE";
   g_sensors[0].gvKey       = "MKS_SENS_VOL";
   g_sensors[0].status      = 1;                                    // default: nao encontrado
   g_sensors[0].enabled     = true;
   g_sensors[0].value       = 0;
   g_sensors[0].signal      = 0;
   g_sensors[0].valueLbl    = "Score";
   g_sensors[0].signalLbl   = "--";
   g_sensors[0].accentClr   = CLR_ACCENT_YELLOW;

   //--- Sensor 1: Bulls vs Bears ---
   g_sensors[1].name        = "BB";
   g_sensors[1].displayName = "BULLS vs BEARS";
   g_sensors[1].gvKey       = "MKS_SENS_BB";
   g_sensors[1].status      = 1;
   g_sensors[1].enabled     = true;
   g_sensors[1].value       = 50;
   g_sensors[1].signal      = 0;
   g_sensors[1].valueLbl    = "Dominancia";
   g_sensors[1].signalLbl   = "NEUTRO";
   g_sensors[1].accentClr   = CLR_ACCENT_BLUE;

   //--- Sensor 2: Tendencia CE (em desenvolvimento) ---
   g_sensors[2].name        = "CE";
   g_sensors[2].displayName = "TENDENCIA";
   g_sensors[2].gvKey       = "MKS_SENS_CE";
   g_sensors[2].status      = 0;                                    // dev
   g_sensors[2].enabled     = false;
   g_sensors[2].value       = 0;
   g_sensors[2].signal      = 0;
   g_sensors[2].valueLbl    = "Slope";
   g_sensors[2].signalLbl   = "DEV";
   g_sensors[2].accentClr   = CLR_ACCENT_CYAN;

   //--- Sensor 3: Slope Donchian (em desenvolvimento) ---
   g_sensors[3].name        = "SLOPE";
   g_sensors[3].displayName = "SLOPE DONCHIAN";
   g_sensors[3].gvKey       = "MKS_SENS_SLOPE";
   g_sensors[3].status      = 0;                                    // dev
   g_sensors[3].enabled     = false;
   g_sensors[3].value       = 0;
   g_sensors[3].signal      = 0;
   g_sensors[3].valueLbl    = "Width";
   g_sensors[3].signalLbl   = "DEV";
   g_sensors[3].accentClr   = CLR_ACCENT_PURPLE;

   //--- Sensor 4: Reversao REV (em desenvolvimento) ---
   g_sensors[4].name        = "REV";
   g_sensors[4].displayName = "REVERSAO";
   g_sensors[4].gvKey       = "MKS_SENS_REV";
   g_sensors[4].status      = 0;                                    // dev
   g_sensors[4].enabled     = false;
   g_sensors[4].value       = 0;
   g_sensors[4].signal      = 0;
   g_sensors[4].valueLbl    = "Score";
   g_sensors[4].signalLbl   = "DEV";
   g_sensors[4].accentClr   = CLR_ACCENT_ORANGE;

   //--- Sensor 5: Consensus ---
   g_sensors[5].name        = "CONSENSUS";
   g_sensors[5].displayName = "CONSENSUS EA";
   g_sensors[5].gvKey       = "MKS_SENS_CONSENSUS";
   g_sensors[5].status      = 0;                                    // dev (depende dos outros)
   g_sensors[5].enabled     = false;
   g_sensors[5].value       = 0;
   g_sensors[5].signal      = 0;
   g_sensors[5].valueLbl    = "Camadas";
   g_sensors[5].signalLbl   = "--";
   g_sensors[5].accentClr   = CLR_ACCENT_GREEN;

   //--- Carrega toggles persistidos via GlobalVariables ---
   for(int i = 0; i < SENSOR_COUNT; i++)
   {
      string tgKey = OBJ_PREFIX + "TOGGLE_" + g_sensors[i].name;
      if(GlobalVariableCheck(tgKey))
         g_sensors[i].enabled = (GlobalVariableGet(tgKey) > 0.5);
   }
}

//--- Atualiza dados dos sensores via GlobalVariables ---
void UpdateSensorsData()
{
   for(int i = 0; i < SENSOR_COUNT; i++)
   {
      string valKey = g_sensors[i].gvKey + "_VALUE";
      string sigKey = g_sensors[i].gvKey + "_SIGNAL";

      //--- Detecta se esta carregado (GV existe) ---
      if(GlobalVariableCheck(valKey))
      {
         g_sensors[i].status = 2;                                   // verde: carregado
         g_sensors[i].value  = GlobalVariableGet(valKey);
         if(GlobalVariableCheck(sigKey))
            g_sensors[i].signal = GlobalVariableGet(sigKey);

         //--- Atualiza label de sinal baseado no sensor ---
         if(g_sensors[i].name == "VOL")
            g_sensors[i].signalLbl = (g_sensors[i].signal > 0.5) ? "LIBERADO" : "BLOQUEADO";
         else if(g_sensors[i].name == "BB")
         {
            if(g_sensors[i].signal > 0.5)       g_sensors[i].signalLbl = "BULLS";
            else if(g_sensors[i].signal < -0.5) g_sensors[i].signalLbl = "BEARS";
            else                                  g_sensors[i].signalLbl = "NEUTRO";
         }
         else if(g_sensors[i].name == "CE")
         {
            if(g_sensors[i].signal > 0.5)       g_sensors[i].signalLbl = "BULL";
            else if(g_sensors[i].signal < -0.5) g_sensors[i].signalLbl = "BEAR";
            else                                  g_sensors[i].signalLbl = "FLAT";
         }
         else if(g_sensors[i].name == "SLOPE")
         {
            if(g_sensors[i].value < 25)      g_sensors[i].signalLbl = "LATERAL";
            else if(g_sensors[i].value < 50) g_sensors[i].signalLbl = "FRACO";
            else if(g_sensors[i].value < 75) g_sensors[i].signalLbl = "EQUILIB.";
            else                              g_sensors[i].signalLbl = "FORTE";
         }
         else if(g_sensors[i].name == "REV")
         {
            if(g_sensors[i].signal > 0.5)       g_sensors[i].signalLbl = "REV BULL";
            else if(g_sensors[i].signal < -0.5) g_sensors[i].signalLbl = "REV BEAR";
            else                                  g_sensors[i].signalLbl = "NEUTRO";
         }
         else if(g_sensors[i].name == "CONSENSUS")
         {
            if(g_sensors[i].signal > 0.5)       g_sensors[i].signalLbl = "LONG";
            else if(g_sensors[i].signal < -0.5) g_sensors[i].signalLbl = "SHORT";
            else                                  g_sensors[i].signalLbl = "AGUARDANDO";
         }
      }
      else
      {
         //--- Nao encontrado: dev (cinza) ou not found (amarelo) ---
         if(g_sensors[i].name == "CE" || g_sensors[i].name == "SLOPE" ||
            g_sensors[i].name == "REV" || g_sensors[i].name == "CONSENSUS")
            g_sensors[i].status = 0;                                // dev: cinza
         else
            g_sensors[i].status = 1;                                // not found: amarelo
      }
   }
}

//--- Salva toggles ao alterar ---
void SaveSensorToggle(int idx)
{
   if(idx < 0 || idx >= SENSOR_COUNT) return;
   string tgKey = OBJ_PREFIX + "TOGGLE_" + g_sensors[idx].name;
   GlobalVariableSet(tgKey, g_sensors[idx].enabled ? 1.0 : 0.0);
}

//--- Conta sensores habilitados (para calcular layout) ---
int CountEnabledSensors()
{
   int cnt = 0;
   for(int i = 0; i < SENSOR_COUNT; i++)
      if(g_sensors[i].enabled) cnt++;
   return cnt;
}

//--- Desenha um card de sensor (usado na aba Dashboard) ---
void DrawSensorCard(int idx, int cx, int cy, int cw)
{
   if(idx < 0 || idx >= SENSOR_COUNT) return;

   int cardH = (int)(130 * g_fontBase / 9.0);                       // altura maior para acomodar gaps
   string prefix = "C_Sns" + IntegerToString(idx);

   //--- Card com cor unica ---
   Card(prefix + "_c", cx, cy, cw, cardH, true, g_sensors[idx].accentClr);

   int px = cx + CARD_PAD;
   int py = cy + CARD_PAD + 4;

   //--- Dot de status (verde=carregado, amarelo=nao encontrado, cinza=dev) ---
   color statusClr = CLR_TEXT_MUTED;
   if(g_sensors[idx].status == 2)      statusClr = CLR_ACCENT_GREEN;
   else if(g_sensors[idx].status == 1) statusClr = CLR_ACCENT_YELLOW;
   Rect(prefix + "_dot", px, py + 4, 10, 10, statusClr);

   //--- Titulo do sensor ---
   Label(prefix + "_title", px + 16, py, g_sensors[idx].displayName,
      CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");

   //--- Sinal (canto direito) ---
   color sigClr = CLR_TEXT_LIGHT;
   string sigTxt = g_sensors[idx].signalLbl;
   if(sigTxt == "LIBERADO" || sigTxt == "BULL" || sigTxt == "BULLS" ||
      sigTxt == "LONG" || sigTxt == "FORTE" || sigTxt == "REV BULL")
      sigClr = CLR_ACCENT_GREEN;
   else if(sigTxt == "BLOQUEADO" || sigTxt == "BEAR" || sigTxt == "BEARS" ||
           sigTxt == "SHORT" || sigTxt == "LATERAL" || sigTxt == "REV BEAR")
      sigClr = CLR_ACCENT_RED;
   else if(sigTxt == "DEV") sigClr = CLR_TEXT_MUTED;

   int sigW = StringLen(sigTxt) * 7 + 10;
   Label(prefix + "_sig", px + cw - 2 * CARD_PAD - sigW, py + 2,
      sigTxt, sigClr, g_fontSmall, "Segoe UI Bold");

   py += g_fontSection + 20;                                         // gap padrao titulo -> conteudo

   //--- Label do valor + valor numerico (gap horizontal maior) ---
   Label(prefix + "_vlbl", px, py, g_sensors[idx].valueLbl + ":", CLR_TEXT_DIM, g_fontSmall);
   string valTxt = DoubleToString(g_sensors[idx].value, 1) + "%";
   Label(prefix + "_vval", px + 115, py, valTxt, CLR_TEXT_WHITE, g_fontNormal, "Segoe UI Bold");

   py += g_fontNormal + 14;                                          // gap maior antes da barra

   //--- Barra gradiente termometro (vermelho -> azul) ---
   color barClr = GetSensorGradientColor(g_sensors[idx].value);
   ProgressBar(prefix + "_bar", px, py, cw - 2 * CARD_PAD, 12, g_sensors[idx].value, barClr);
}


//=====================================================================
// [10d] FASE D: CALENDARIO ECONOMICO REAL
// Integracao com a MT5 Calendar API para exibir eventos reais.
// Estilo ForexFactory: Time | Cur | Imp | Event | Actual | Fcst | Prev
//=====================================================================

//--- Formata valor de evento (actual/forecast/previous) ---
string FormatCalValue(long raw, int digits, int unit, int mult)
{
   if(raw == LONG_MAX) return "--";                                  // sem valor

   //--- Aplica digits (valor real = raw / 10^digits) ---
   double val = (double)raw;
   for(int i = 0; i < digits; i++) val /= 10.0;

   //--- Sufixo da unidade ---
   string suffix = "";
   if(unit == CALENDAR_UNIT_PERCENT) suffix = "%";
   else if(unit == CALENDAR_UNIT_HOUR) suffix = "h";

   //--- Sufixo do multiplicador (K, M, B, T) ---
   string multSfx = "";
   if(mult == CALENDAR_MULTIPLIER_THOUSANDS) multSfx = "K";
   else if(mult == CALENDAR_MULTIPLIER_MILLIONS)  multSfx = "M";
   else if(mult == CALENDAR_MULTIPLIER_BILLIONS)  multSfx = "B";
   else if(mult == CALENDAR_MULTIPLIER_TRILLIONS) multSfx = "T";

   //--- Decide precisao baseado no digits ---
   int displayDigits = (digits > 2) ? 2 : digits;
   string numStr = DoubleToString(val, displayDigits);

   //--- Remove zeros desnecessarios ---
   if(displayDigits > 0 && StringFind(numStr, ".") >= 0)
   {
      while(StringGetCharacter(numStr, StringLen(numStr) - 1) == '0')
         numStr = StringSubstr(numStr, 0, StringLen(numStr) - 1);
      if(StringGetCharacter(numStr, StringLen(numStr) - 1) == '.')
         numStr = StringSubstr(numStr, 0, StringLen(numStr) - 1);
   }

   return numStr + multSfx + suffix;
}

//--- Atualiza dados do calendario via MT5 API ---
void UpdateCalendarData()
{
   g_calCount = 0;                                                    // zera contador

   //--- Periodo: hoje inteiro (00:00 -> 23:59) ---
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime fromTime = StructToTime(dt);
   datetime toTime = fromTime + 86400;                                // +24h

   //--- Fetch events via Calendar API ---
   MqlCalendarValue values[];
   int count = CalendarValueHistory(values, fromTime, toTime, NULL, NULL);

   if(count <= 0)
   {
      g_calLastUpdate = TimeCurrent();
      return;
   }

   //--- Processa cada evento (filtra por importancia minima) ---
   for(int i = 0; i < count && g_calCount < MAX_CAL_EVENTS; i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event)) continue;

      //--- Filtro: minimo MED importance (pula holidays e LOW) ---
      if((int)event.importance < g_calMinImportance) continue;

      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country)) continue;

      //--- Converte hora para fuso do usuario ---
      datetime adjTime = values[i].time + g_tzShift * 3600;
      MqlDateTime dte;
      TimeToStruct(adjTime, dte);

      g_calEvents[g_calCount].eventTime  = values[i].time;
      g_calEvents[g_calCount].timeStr    = StringFormat("%02d:%02d", dte.hour, dte.min);
      g_calEvents[g_calCount].currency   = country.currency;
      g_calEvents[g_calCount].importance = (int)event.importance;
      g_calEvents[g_calCount].name       = event.name;

      //--- Formata valores ---
      g_calEvents[g_calCount].actual   = FormatCalValue(values[i].actual_value, event.digits, (int)event.unit, (int)event.multiplier);
      g_calEvents[g_calCount].forecast = FormatCalValue(values[i].forecast_value, event.digits, (int)event.unit, (int)event.multiplier);
      g_calEvents[g_calCount].previous = FormatCalValue(values[i].prev_value, event.digits, (int)event.unit, (int)event.multiplier);

      //--- Marca se actual > forecast (para colorir) ---
      g_calEvents[g_calCount].hasActual = (values[i].actual_value != LONG_MAX);
      if(g_calEvents[g_calCount].hasActual && values[i].forecast_value != LONG_MAX)
         g_calEvents[g_calCount].actualBetter = (values[i].actual_value > values[i].forecast_value);
      else
         g_calEvents[g_calCount].actualBetter = false;

      g_calCount++;
   }

   g_calLastUpdate = TimeCurrent();
}


//=====================================================================
// [11] CALCULO DE FONTES E LAYOUT
// Escala todos os tamanhos proporcionalmente ao fontBase.
//=====================================================================

void CalculateFonts()
{
   if(g_fontBase < 6)  g_fontBase = 6;                               // minimo 6
   if(g_fontBase > 16) g_fontBase = 16;                              // maximo 16

   g_fontNormal  = g_fontBase;                                       // fonte normal = base
   g_fontTitle   = g_fontBase + 4;                                   // titulo = base + 4
   g_fontSection = g_fontBase + 2;                                   // secao = base + 2
   g_fontSmall   = g_fontBase - 1;                                   // pequeno = base - 1
   g_fontTab     = g_fontBase - 1;                                   // aba = base - 1
   g_fontValue   = g_fontBase + 2;                                   // valor destaque = base + 2

   double scale = g_fontBase / 9.0;                                  // fator de escala (1.0 para base=9)
   g_panelW     = (int)(620 * scale);                                // largura total escala (620 base)
   g_headerH    = (int)(65 * scale);                                 // header 2 linhas
   g_tabH       = (int)(28 * scale);                                 // abas escala
   g_contentH   = (int)(1400 * scale);                               // conteudo escala (aumentado)
   g_lineH      = (int)(30 * scale);                                 // linha normal escala (forte)
   g_lineHSmall = (int)(26 * scale);                                 // linha pequena escala (forte)
   g_sectionGap = (int)(34 * scale);                                 // gap secao escala (forte)
   g_panelH     = g_headerH + g_tabH + g_contentH;                  // altura total
}

void CalculatePosition()
{
   g_chartW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);       // largura do grafico
   g_chartH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);      // altura do grafico
   g_panelX = 8;                                                     // posicao X fixa
   g_panelY = 4;                                                     // posicao Y fixa
}


//=====================================================================
// [12] CONSTRUCAO DO PAINEL PRINCIPAL
// Monta header, barra de abas e area de conteudo.
//=====================================================================

void BuildPanel()
{
   CalculatePosition();                                               // calcula posicao

   //--- Fundo principal (cobrindo tudo) ---
   Rect("MainBg", g_panelX, g_panelY, g_panelW, g_panelH, CLR_BG_MAIN, CLR_BORDER, 1);  // fundo + borda

   //--- HEADER SUPERIOR (2 linhas: logo+hora | risco+trades+data) ---
   Rect("Header", g_panelX + 1, g_panelY + 1, g_panelW - 2, g_headerH, CLR_BG_HEADER);

   //--- Linha 1: Simbolo (esquerda) | Hora (direita) ---
   Label("HdrLogo", g_panelX + MARGIN, g_panelY + 6,
      g_symbol + "  |  V5.0", CLR_TEXT_LIGHT, g_fontSection, "Segoe UI Semibold");
   Label("HdrTime", g_panelX + g_panelW - 145, g_panelY + 4,
      GetServerTimeFormatted(), CLR_ACCENT_CYAN, g_fontTitle, "Segoe UI Bold");

   //--- Linha 2: Risco + Trades ao vivo + Data ---
   int hdrRow2 = g_panelY + g_fontTitle + 22;

   //--- Indicador visual de risco (drawdown-based) ---
   color riskClr = CLR_ACCENT_GREEN;
   string riskTxt = "LOW RISK";
   if(g_maxDrawdown > 0)
   {
      double ddPctBal = (g_totalBalance > 0) ? g_curDrawdown / g_totalBalance * 100.0 : 0;
      if(ddPctBal > 5.0)       { riskClr = CLR_ACCENT_RED;    riskTxt = "HIGH RISK"; }
      else if(ddPctBal > 2.0)  { riskClr = CLR_ACCENT_YELLOW; riskTxt = "MED RISK"; }
   }
   Rect("HdrRiskDot", g_panelX + MARGIN, hdrRow2 + 3, 10, 10, riskClr);
   Label("HdrRiskTxt", g_panelX + MARGIN + 14, hdrRow2, riskTxt, riskClr, g_fontSmall - 1, "Segoe UI");

   //--- Contador de trades ao vivo ---
   int liveCount = 0;
   for(int p = PositionsTotal() - 1; p >= 0; p--)
      if(PositionGetSymbol(p) == g_symbol) liveCount++;
   Label("HdrLive", g_panelX + MARGIN + 105, hdrRow2,
      "TRADES: " + IntegerToString(liveCount),
      (liveCount > 0) ? CLR_ACCENT_CYAN : CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");

   //--- Quality Score ---
   color qsClr = CLR_ACCENT_GREEN;
   if(g_qualityScore < 40) qsClr = CLR_ACCENT_RED;
   else if(g_qualityScore < 65) qsClr = CLR_ACCENT_YELLOW;
   Label("HdrQS", g_panelX + MARGIN + 200, hdrRow2,
      "QS:" + IntegerToString((int)g_qualityScore), qsClr, g_fontSmall - 1, "Segoe UI Semibold");

   //--- Data (direita, segunda linha) ---
   Label("HdrDate", g_panelX + g_panelW - 145, hdrRow2,
      GetDateFormatted(), CLR_TEXT_DIM, g_fontSmall, "Segoe UI");

   //--- Botao minimizar ---
   Btn("BtnMin", g_panelX + g_panelW - 30, g_panelY + 4, 24, 22,
      "-", CLR_BG_HEADER, CLR_TEXT_DIM, g_fontSection);

   //--- Linha de separacao header/abas ---
   Rect("HdrLine", g_panelX + 1, g_panelY + g_headerH, g_panelW - 2, 1, CLR_SEPARATOR);  // separador

   //--- BARRA DE ABAS ---
   int tabY = g_panelY + g_headerH + 1;                             // Y das abas
   int tabW = g_panelW / TAB_COUNT;                                  // largura de cada aba

   for(int i = 0; i < TAB_COUNT; i++)                                // cria cada aba
   {
      int tabX = g_panelX + i * tabW;                                // X da aba
      color bgClr  = (i == g_activeTab) ? CLR_TAB_ACTIVE : CLR_TAB_INACTIVE;   // cor fundo
      color txtClr = (i == g_activeTab) ? CLR_TEXT_WHITE : CLR_TEXT_DIM;        // cor texto
      Btn("Tab" + IntegerToString(i), tabX, tabY, tabW, g_tabH,
         g_tabLabels[i], bgClr, txtClr, g_fontTab);                  // botao da aba

      //--- Linha de acento embaixo da aba ativa ---
      if(i == g_activeTab)                                            // se aba ativa
         Rect("TabAcc" + IntegerToString(i), tabX + 2, tabY + g_tabH - 2,
            tabW - 4, 2, CLR_ACCENT_BLUE);                          // linha azul
   }

   //--- AREA DE CONTEUDO ---
   int contentY = tabY + g_tabH;                                     // Y do conteudo
   Rect("ContentBg", g_panelX + 1, contentY, g_panelW - 2, g_contentH, CLR_BG_MAIN);  // fundo conteudo

   //--- Desenha conteudo da aba ativa ---
   DrawActiveTab();                                                   // renderiza aba
}


//=====================================================================
// [13] ROTEADOR DE ABAS
// Chama a funcao de desenho da aba correspondente.
//=====================================================================

void DrawActiveTab()
{
   ClearContent();                                                    // limpa conteudo anterior

   int cx = g_panelX + MARGIN;                                       // X do conteudo
   int cy = g_panelY + g_headerH + g_tabH + MARGIN;                 // Y do conteudo
   int cw = g_panelW - 2 * MARGIN;                                  // largura disponivel

   switch(g_activeTab)                                                // roteamento por aba
   {
      case 0: DrawTabDashboard(cx, cy, cw);   break;                 // aba Dashboard
      case 1: DrawTabRobot(cx, cy, cw);        break;                // aba Robo
      case 2: DrawTabMarket(cx, cy, cw);       break;                // aba Mercado
      case 3: DrawTabReports(cx, cy, cw);      break;                // aba Relatorios
      case 4: DrawTabConfig(cx, cy, cw);       break;                // aba Configuracoes
   }
}


//=====================================================================
// [14] ABA DASHBOARD
// Ativo + Spread + BID/ASK + Hora + Curva P&L + EA Stats + Manual.
//=====================================================================

void DrawTabDashboard(int cx, int cy, int cw)
{
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);     // casas decimais
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);              // preco BID
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);              // preco ASK
   double tSize = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);  // tick size
   int spread = (tSize > 0) ? (int)MathRound((ask - bid) / tSize) : 0;  // spread em ticks

   //=== CARD 1: ATIVO + PRECOS + SESSAO + HIGH/LOW ===
   //--- Usa g_acctCurrency global ---                            // moeda da conta (USD, JPY, etc)
   int cardH1 = (int)(155 * g_fontBase / 9.0);                       // altura do card (mais espaco)
   Card("C_CardPrice", cx, cy, cw, cardH1, true, CLR_ACCENT_CYAN); // card com acento cyan

   int px = cx + CARD_PAD;                                           // X interno do card
   int py = cy + CARD_PAD + 4;                                      // Y interno do card

   //--- Nome do ativo (titulo grande) ---
   Label("C_AssetName", px, py, g_symbol, CLR_TEXT_WHITE, g_fontTitle, "Segoe UI Bold");
   py += g_fontTitle + 14;

   //--- Linha de precos: BID (esquerda) | ASK (centro) | SPREAD (direita) ---
   int col1 = px;                                                    // coluna BID
   int col2 = px + (cw - 2 * CARD_PAD) / 3;                        // coluna ASK
   int col3 = px + 2 * (cw - 2 * CARD_PAD) / 3;                   // coluna SPREAD

   Label("C_BidLbl", col1, py, "BID", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI");
   Label("C_BidVal", col1, py + g_fontSmall + 8, FmtPrice(bid, digits), CLR_ACCENT_GREEN, g_fontValue, "Segoe UI Bold");

   Label("C_AskLbl", col2, py, "ASK", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI");
   Label("C_AskVal", col2, py + g_fontSmall + 8, FmtPrice(ask, digits), CLR_ACCENT_RED, g_fontValue, "Segoe UI Bold");

   Label("C_SpreadLbl", col3, py, "SPREAD", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI");
   Label("C_SpreadTxt", col3, py + g_fontSmall + 8, IntegerToString(spread),
      CLR_ACCENT_YELLOW, g_fontValue, "Segoe UI Bold");

   py += g_fontSmall + g_fontValue + 20;                             // mais espaco vertical

   //--- Sessao ativa + proxima (usa BuildSessionText) ---
   Label("C_MktSession", px, py, BuildSessionText(), CLR_TEXT_LIGHT, g_fontSmall, "Segoe UI");
   py += g_lineHSmall;

   //--- Day High / Low ---
   double dayHigh = iHigh(g_symbol, PERIOD_D1, 0);
   double dayLow  = iLow(g_symbol, PERIOD_D1, 0);
   Label("C_MktHigh", px, py, "High: " + FmtPrice(dayHigh, digits), CLR_ACCENT_GREEN, g_fontSmall, "Segoe UI");
   Label("C_MktLow", px + cw / 2, py, "Low: " + FmtPrice(dayLow, digits), CLR_ACCENT_RED, g_fontSmall, "Segoe UI");

   cy += cardH1 + CARD_GAP;

   //=== CARD 2: PERFORMANCE (CURVA P&L) ===
   int chartH = (int)(110 * g_fontBase / 9.0);                      // altura do grafico
   int pnlCardH = chartH + 65;                                      // altura total do card
   Card("C_CardPnL", cx, cy, cw, pnlCardH, true, CLR_ACCENT_GREEN);

   //--- Area do grafico (criado PRIMEIRO para ficar ATRAS do titulo) ---
   int gx = cx + CARD_PAD;
   int gy = cy + CARD_PAD + g_fontSection + 18;                     // Y abaixo do titulo
   int gw = cw - 2 * CARD_PAD;
   int gh = chartH;
   Rect("C_PnlChartBg", gx, gy, gw, gh, C'18,20,28');             // fundo do grafico

   //--- Linha zero ---
   Rect("C_PnlZero", gx, gy + gh / 2, gw, 1, CLR_SEPARATOR);

   //--- Desenha curva P&L ---
   DrawPnLCurve(gx, gy, gw, gh);

   //--- Titulo "PERFORMANCE" (criado DEPOIS do chart bg para ficar NA FRENTE) ---
   int pnlPx = cx + CARD_PAD;
   int pnlPy = cy + CARD_PAD + 2;
   Label("C_PnlTitle", pnlPx, pnlPy,
      "PERFORMANCE", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");

   //--- Valor total P&L (alinhado a direita, usa moeda da conta) ---
   double totalPnL = g_eaProfit + g_eaLoss + g_manualProfit + g_manualLoss;
   color pnlClr = (totalPnL >= 0) ? CLR_ACCENT_GREEN : CLR_ACCENT_RED;
   string pnlText = FmtMoney(totalPnL);                              // FmtMoney ja inclui sinal
   Label("C_PnlValue", pnlPx + cw - 2 * CARD_PAD - 170, pnlPy, pnlText,
      pnlClr, g_fontSection, "Segoe UI Bold");

   cy += pnlCardH + CARD_GAP + 4;                                   // gap extra antes dos stats

   //=== CARDS: EA STATS e MANUAL STATS (lado a lado) ===
   int halfW = (cw - CARD_GAP) / 2;                                 // metade da largura (-gap)
   int statsH = (int)(210 * g_fontBase / 9.0);                      // altura dos cards de stats (aumentada)

   //--- Card EA Stats ---
   Card("C_CardEA", cx, cy, halfW, statsH, true, CLR_ACCENT_BLUE);  // card EA

   px = cx + CARD_PAD; py = cy + CARD_PAD + 2;
   Label("C_EATitle", px, py, "EA TRADES", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   py += g_fontSection + 18;

   int eaTotal = g_eaWins + g_eaLosses;                             // total trades EA
   color eaClr = (g_eaProfit + g_eaLoss >= 0) ? CLR_ACCENT_GREEN : CLR_ACCENT_RED;

   Label("C_EAProfit", px, py, "Ganhos:", CLR_TEXT_DIM, g_fontSmall);
   Label("C_EAProfitV", px + 95, py, FmtMoney(g_eaProfit), CLR_ACCENT_GREEN, g_fontNormal, "Segoe UI Semibold");
   py += g_lineHSmall + 5;

   Label("C_EALoss", px, py, "Perdas:", CLR_TEXT_DIM, g_fontSmall);
   Label("C_EALossV", px + 95, py, FmtMoney(g_eaLoss), CLR_ACCENT_RED, g_fontNormal, "Segoe UI Semibold");
   py += g_lineHSmall + 5;

   Label("C_EANet", px, py, "Liquido:", CLR_TEXT_DIM, g_fontSmall);
   Label("C_EANetV", px + 95, py, FmtMoney(g_eaProfit + g_eaLoss), eaClr, g_fontNormal, "Segoe UI Bold");
   py += g_lineHSmall + 5;

   Label("C_EAWr", px, py, "WinRate:", CLR_TEXT_DIM, g_fontSmall);
   Label("C_EAWrV", px + 95, py, FmtWinRate(g_eaWins, eaTotal) + " (" + IntegerToString(eaTotal) + " trades)", CLR_TEXT_LIGHT, g_fontSmall);
   py += g_lineHSmall + 5;

   //--- Barra winrate EA ---
   double eaWrPct = (eaTotal > 0) ? (double)g_eaWins / eaTotal * 100.0 : 0;
   ProgressBar("C_EABar", px, py + 8, halfW - 2 * CARD_PAD, 12, eaWrPct,
      (eaWrPct >= 50) ? CLR_BAR_GREEN : CLR_BAR_RED);               // barra winrate

   //--- Card Manual Stats ---
   int mx = cx + halfW + CARD_GAP;                                   // X do card manual (usa CARD_GAP)
   Card("C_CardMan", mx, cy, halfW, statsH, true, CLR_ACCENT_PURPLE);  // card manual

   px = mx + CARD_PAD; py = cy + CARD_PAD + 2;
   Label("C_ManTitle", px, py, "MANUAL TRADES", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   py += g_fontSection + 18;

   int manTotal = g_manualWins + g_manualLosses;                     // total manual
   color manClr = (g_manualProfit + g_manualLoss >= 0) ? CLR_ACCENT_GREEN : CLR_ACCENT_RED;

   Label("C_ManProfit", px, py, "Ganhos:", CLR_TEXT_DIM, g_fontSmall);
   Label("C_ManProfitV", px + 95, py, FmtMoney(g_manualProfit), CLR_ACCENT_GREEN, g_fontNormal, "Segoe UI Semibold");
   py += g_lineHSmall + 5;

   Label("C_ManLoss", px, py, "Perdas:", CLR_TEXT_DIM, g_fontSmall);
   Label("C_ManLossV", px + 95, py, FmtMoney(g_manualLoss), CLR_ACCENT_RED, g_fontNormal, "Segoe UI Semibold");
   py += g_lineHSmall + 5;

   Label("C_ManNet", px, py, "Liquido:", CLR_TEXT_DIM, g_fontSmall);
   Label("C_ManNetV", px + 95, py, FmtMoney(g_manualProfit + g_manualLoss), manClr, g_fontNormal, "Segoe UI Bold");
   py += g_lineHSmall + 5;

   Label("C_ManWr", px, py, "WinRate:", CLR_TEXT_DIM, g_fontSmall);
   Label("C_ManWrV", px + 95, py, FmtWinRate(g_manualWins, manTotal) + " (" + IntegerToString(manTotal) + " trades)", CLR_TEXT_LIGHT, g_fontSmall);
   py += g_lineHSmall + 5;

   //--- Barra winrate Manual ---
   double manWrPct = (manTotal > 0) ? (double)g_manualWins / manTotal * 100.0 : 0;
   ProgressBar("C_ManBar", px, py + 8, halfW - 2 * CARD_PAD, 12, manWrPct,
      (manWrPct >= 50) ? CLR_BAR_GREEN : CLR_BAR_RED);

   cy += statsH + CARD_GAP;                                                 // avanca Y

   //=== CARD 6: VOLATILIDADE ===
   int volH = (int)(125 * g_fontBase / 9.0);                         // altura card vol
   Card("C_CardVol", cx, cy, cw, volH, true, CLR_ACCENT_YELLOW);   // card com acento amarelo

   px = cx + CARD_PAD; py = cy + CARD_PAD + 2;
   Label("C_VolTitle", px, py, "VOLATILIDADE", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   py += g_fontSection + 18;

   //--- ATR D1 ---
   double atrVal = 0.0;
   if(g_hATR_D1 != INVALID_HANDLE)
   {
      double buf[]; ArraySetAsSeries(buf, true);
      if(CopyBuffer(g_hATR_D1, 0, 0, 1, buf) > 0) atrVal = buf[0];
   }
   Label("C_VolATR", px, py, "ATR(21) D1: " + FmtPrice(atrVal, digits), CLR_TEXT_DIM, g_fontSmall);

   //--- Range e velocidade ---
   double dayRange = dayHigh - dayLow;
   int rangeTk = (tSize > 0) ? (int)MathRound(dayRange / tSize) : 0;
   Label("C_VolRange", px + cw / 2 - 10, py, "Range: " + FmtPrice(dayRange, digits) + " (" + FmtInt(rangeTk) + "tk)", CLR_TEXT_DIM, g_fontSmall);
   py += g_lineHSmall + 5;

   //--- Velocidade ---
   string speedTxt = "LENTO"; color speedClr = CLR_BAR_GREEN;
   if(g_ticksPerMin > 60)      { speedTxt = "RAPIDO"; speedClr = CLR_BAR_RED; }
   else if(g_ticksPerMin > 25) { speedTxt = "MEDIO";  speedClr = CLR_BAR_YELLOW; }
   Label("C_VolSpeed", px, py, "Ticks/min: " + IntegerToString(g_ticksPerMin) + " (" + speedTxt + ")", speedClr, g_fontSmall);
   py += g_fontSmall + 8;

   //--- Barra de velocidade (abaixo do texto, nao ao lado) ---
   ProgressBar("C_VolBar", px, py, cw - 2 * CARD_PAD, 12,
      MathMin(100, g_ticksPerMin * 100.0 / 120.0), speedClr);

   cy += volH + CARD_GAP;

   //=== SECAO: SENSORES MKS (apenas os habilitados) ===
   int enabledCount = CountEnabledSensors();
   if(enabledCount > 0)
   {
      //--- Titulo da secao ---
      Label("C_SnsTitle", cx, cy, "SENSORES MKS", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
      cy += g_fontSection + 18;

      //--- Grid 2 colunas ---
      int halfW = (cw - CARD_GAP) / 2;
      int snsH = (int)(130 * g_fontBase / 9.0);
      int drawnIdx = 0;

      for(int si = 0; si < SENSOR_COUNT; si++)
      {
         if(!g_sensors[si].enabled) continue;

         int col = drawnIdx % 2;
         int row = drawnIdx / 2;
         int scx = cx + col * (halfW + CARD_GAP);
         int scy = cy + row * (snsH + CARD_GAP);
         DrawSensorCard(si, scx, scy, halfW);
         drawnIdx++;
      }
   }
}

//--- Desenha curva P&L (retangulos de 2px representando pontos) ---
void DrawPnLCurve(int gx, int gy, int gw, int gh)
{
   if(g_pnlCount < 2) return;                                        // precisa de pelo menos 2 pontos

   //--- Encontra min/max para escalar ---
   double minVal = g_pnlCurve[0], maxVal = g_pnlCurve[0];          // inicializa
   for(int i = 1; i < g_pnlCount; i++)                               // percorre pontos
   {
      if(g_pnlCurve[i] < minVal) minVal = g_pnlCurve[i];           // atualiza min
      if(g_pnlCurve[i] > maxVal) maxVal = g_pnlCurve[i];           // atualiza max
   }
   double range = maxVal - minVal;                                   // range total
   if(range < 0.01) range = 1.0;                                    // evita divisao por zero

   //--- Desenha pontos ---
   double stepX = (double)gw / (g_pnlCount - 1);                    // espaco entre pontos
   for(int i = 0; i < g_pnlCount; i++)                               // percorre pontos
   {
      int px = gx + (int)(i * stepX);                                // X do ponto
      double norm = (g_pnlCurve[i] - minVal) / range;               // normaliza 0-1
      int py = gy + gh - (int)(norm * (gh - 4)) - 2;                // Y invertido (0=baixo)
      color ptClr = (g_pnlCurve[i] >= 0) ? CLR_ACCENT_GREEN : CLR_ACCENT_RED;  // cor do ponto
      Rect("C_Pt" + IntegerToString(i), px, py, 3, 3, ptClr);     // ponto 3x3
   }
}


//=====================================================================
// [15] ABA ROBO
// Dados do robo em operacao, estrategias ativas, toggles on/off.
//=====================================================================

void DrawTabRobot(int cx, int cy, int cw)
{
   int innerW = cw - 2 * CARD_PAD;                                  // largura interna util

   //=== CARD 1: STATUS DO ROBO ===
   int statusH = (int)(100 * g_fontBase / 9.0);                     // mais alto
   Card("C_CardRoboSt", cx, cy, cw, statusH, true, CLR_ACCENT_BLUE);

   int px = cx + CARD_PAD, py = cy + CARD_PAD + 4;
   Label("C_RoboTitle", px, py, "STATUS DO ROBO", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");

   //--- Detecta posicoes EA ---
   int eaPositions = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetSymbol(i) == g_symbol)
         if(PositionGetInteger(POSITION_MAGIC) > 0)
            eaPositions++;

   //--- Indicador de status (dot colorido grande, sem texto) ---
   color dotClr = CLR_ACCENT_YELLOW;                                  // default: aguardando
   if(eaPositions > 0) dotClr = CLR_ACCENT_GREEN;                   // operando

   int dotSize = 16;                                                  // tamanho do dot (grande e visivel)
   int dotX = px + innerW - dotSize - 4;                             // alinhado a direita
   int dotY = py + 1;                                                // alinhado com titulo
   Rect("C_RoboSt_dot", dotX, dotY, dotSize, dotSize, dotClr);     // dot colorido

   py += g_fontSection + 24;                                         // 2x espaco apos titulo

   Label("C_RoboPosLbl", px, py, "Posicoes EA abertas: " + IntegerToString(eaPositions), CLR_TEXT_LIGHT, g_fontSmall);
   Label("C_RoboFwLbl", px + cw / 2, py, "Framework: " + (g_frameworkOk ? "OK" : "N/A"),
      g_frameworkOk ? CLR_ACCENT_GREEN : CLR_TEXT_DIM, g_fontSmall);

   cy += statusH + CARD_GAP;

   //=== CARD 2: ESTRATEGIAS ===
   int rowH = (int)(70 * g_fontBase / 9.0);                         // altura por estrategia (3x mais espaco)
   int stratH = (int)(55 * g_fontBase / 9.0) + g_stratCount * rowH;
   if(g_stratCount == 0) stratH = (int)(90 * g_fontBase / 9.0);
   Card("C_CardStrat", cx, cy, cw, stratH, true, CLR_ACCENT_PURPLE);

   px = cx + CARD_PAD; py = cy + CARD_PAD + 4;
   Label("C_StratTitle", px, py, "ESTRATEGIAS", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   py += g_fontSection + 20;                                         // espaco grande

   if(g_stratCount == 0)
   {
      Label("C_StratEmpty", px, py, "Nenhuma estrategia registrada", CLR_TEXT_DIM, g_fontNormal);
      Label("C_StratTip", px, py + g_lineH + 6, "Use RegisterStrategy() no EA para adicionar", CLR_TEXT_MUTED, g_fontSmall);
   }
   else
   {
      for(int i = 0; i < g_stratCount; i++)
      {
         int sy = py + i * rowH;
         string sid = IntegerToString(i);

         //--- Fundo alternado (altura uniforme) ---
         if(i % 2 == 0)
            Rect("C_StratBg" + sid, px - 4, sy - 3, innerW + 8, rowH - 2, C'18,22,32');

         //--- Nome da estrategia ---
         Label("C_StratName" + sid, px + 4, sy + 2, g_stratNames[i], CLR_TEXT_WHITE, g_fontNormal, "Segoe UI Semibold");

         //--- Info (abaixo do nome, 3x espaco) ---
         Label("C_StratInfo" + sid, px + 4, sy + g_fontNormal + 18,
            "Posicoes: 0 | Lucro: " + FmtMoney(0), CLR_TEXT_DIM, g_fontSmall - 1);

         //--- Toggle ON/OFF (botao limpo: verde=ON, vermelho=OFF) ---
         int tgW = 50;
         int tgH = 22;
         int tgX = px + innerW - tgW;
         int tgY = sy + (rowH - tgH) / 2 - 5;
         color tgBg = g_stratActive[i] ? CLR_BTN_SUCCESS : CLR_BTN_DANGER;
         string tgTxt = g_stratActive[i] ? "ON" : "OFF";
         Btn("C_StratToggle" + sid, tgX, tgY, tgW, tgH, tgTxt, tgBg, CLR_TEXT_WHITE, g_fontSmall);
      }
   }

   cy += stratH + CARD_GAP;

   //=== CARD 3: POSICOES ABERTAS ===
   int posH = (int)(220 * g_fontBase / 9.0);                        // mais alto para 3x espaco
   Card("C_CardPos", cx, cy, cw, posH, true, CLR_ACCENT_CYAN);

   px = cx + CARD_PAD; py = cy + CARD_PAD + 4;
   Label("C_PosTitle", px, py, "POSICOES ABERTAS", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   py += g_fontSection + 20;                                         // 3x espaco

   //--- Header ---
   Label("C_PosH1", px, py, "Tipo", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   Label("C_PosH2", px + 50, py, "Volume", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   Label("C_PosH3", px + 115, py, "Abertura", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   Label("C_PosH4", px + 220, py, "Atual", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   Label("C_PosH5", px + 320, py, "P&L", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   Label("C_PosH6", px + 410, py, "Magic", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   py += g_fontSmall + 18;                                          // 4x espaco antes da linha
   Rect("C_PosHLine", px, py, innerW, 1, CLR_SEPARATOR);
   py += 14;                                                         // espaco apos linha

   //--- Lista posicoes ---
   int posCount = 0;
   int digits2 = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   for(int i = PositionsTotal() - 1; i >= 0 && posCount < 5; i--)
   {
      if(PositionGetSymbol(i) != g_symbol) continue;

      string type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      color typeClr = (type == "BUY") ? CLR_ACCENT_GREEN : CLR_ACCENT_RED;
      double vol = PositionGetDouble(POSITION_VOLUME);
      double openP = PositionGetDouble(POSITION_PRICE_OPEN);
      double curP = PositionGetDouble(POSITION_PRICE_CURRENT);
      double pnl = PositionGetDouble(POSITION_PROFIT);
      long magic = PositionGetInteger(POSITION_MAGIC);

      string pid = IntegerToString(posCount);
      Label("C_Pos" + pid + "T", px, py, type, typeClr, g_fontSmall - 1);
      Label("C_Pos" + pid + "V", px + 50, py, DoubleToString(vol, 2), CLR_TEXT_LIGHT, g_fontSmall - 1);
      Label("C_Pos" + pid + "O", px + 115, py, FmtPrice(openP, digits2), CLR_TEXT_LIGHT, g_fontSmall - 1);
      Label("C_Pos" + pid + "C", px + 220, py, FmtPrice(curP, digits2), CLR_TEXT_LIGHT, g_fontSmall - 1);
      color plClr = (pnl >= 0) ? CLR_ACCENT_GREEN : CLR_ACCENT_RED;
      Label("C_Pos" + pid + "P", px + 320, py, FmtMoney(pnl), plClr, g_fontSmall - 1, "Segoe UI Semibold");
      Label("C_Pos" + pid + "M", px + 410, py, IntegerToString(magic), CLR_TEXT_DIM, g_fontSmall - 1);

      py += g_lineH + 8;                                             // 3x espaco entre linhas
      posCount++;
   }

   if(posCount == 0)
      Label("C_PosEmpty", px, py, "Nenhuma posicao aberta", CLR_TEXT_DIM, g_fontSmall);
}


//=====================================================================
// [16] ABA MERCADO
// Sessoes de mercado com horarios + Calendario economico ficticio.
//=====================================================================

void DrawTabMarket(int cx, int cy, int cw)
{
   int innerW = cw - 2 * CARD_PAD;

   //=== CARD 1: SESSOES ===
   int sessH = (int)(220 * g_fontBase / 9.0);                       // mais alto para barras grossas
   Card("C_CardSess", cx, cy, cw, sessH, true, CLR_ACCENT_BLUE);

   int px = cx + CARD_PAD, py = cy + CARD_PAD + 4;
   Label("C_SessTitle", px, py, "SESSOES", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   py += g_fontSection + 20;                                         // espaco grande para nao sobrepor

   SessionInfo sessions[];
   GetSessions(sessions);

   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent() + g_tzShift * 3600, dtNow);
   int currentH = dtNow.hour;
   int currentM = dtNow.min;

   int sessRowH = (int)(46 * g_fontBase / 9.0);                     // altura por sessao

   for(int i = 0; i < 4; i++)
   {
      int rowY = py + i * sessRowH;
      string id = IntegerToString(i);

      //--- Fundo alternado ---
      if(i % 2 == 0)
         Rect("C_SessBg" + id, px - 4, rowY - 2, innerW + 8, sessRowH - 4, C'18,22,32');

      //--- Dot de status 16x16 ---
      color dotClr = sessions[i].isActive ? CLR_BADGE_ACTIVE : CLR_BADGE_INACTIVE;
      Rect("C_SessDot" + id, px, rowY + 2, 16, 16, dotClr);

      //--- Nome da sessao (fonte mais pesada) ---
      Label("C_SessName" + id, px + 22, rowY, sessions[i].name,
         sessions[i].isActive ? CLR_TEXT_WHITE : CLR_TEXT_DIM, g_fontNormal, "Segoe UI Bold");

      //--- Horarios JST ---
      string tzLabel = (g_tzShift == 9) ? "JST" : "UTC" + (g_tzShift >= 0 ? "+" : "") + IntegerToString(g_tzShift);
      string hours = StringFormat("%02d:00 - %02d:00 %s",
         sessions[i].openHour, sessions[i].closeHour, tzLabel);
      Label("C_SessHours" + id, px + 140, rowY, hours, CLR_TEXT_LIGHT, g_fontSmall);

      //--- Status e tempo restante ---
      if(sessions[i].isActive)
      {
         string remaining = GetTimeRemaining(sessions[i].closeHour, currentH, currentM);
         Label("C_SessBdg" + id + "_txt", px + innerW - 100, rowY,
            "OPEN " + remaining, CLR_BADGE_ACTIVE, g_fontSmall, "Segoe UI Semibold");
      }
      else
      {
         string toOpen = GetTimeRemaining(sessions[i].openHour, currentH, currentM);
         Label("C_SessBdg" + id + "_txt", px + innerW - 100, rowY,
            "ABRE " + toOpen, CLR_TEXT_DIM, g_fontSmall, "Segoe UI");
      }

      //--- Barra de progresso 4x mais grossa (12px) ---
      int barY = rowY + g_lineH + 2;
      int barW = innerW - 10;
      double sessPct = 0;
      if(sessions[i].isActive)
      {
         int duration = sessions[i].closeHour - sessions[i].openHour;
         if(duration < 0) duration += 24;
         int elapsed = currentH - sessions[i].openHour;
         if(elapsed < 0) elapsed += 24;
         sessPct = (duration > 0) ? (double)elapsed / duration * 100.0 : 0;
      }
      ProgressBar("C_SessBar" + id, px + 10, barY, barW, 12, sessPct, sessions[i].clr);
   }

   cy += sessH + CARD_GAP;

   //=== CARD 2: CALENDARIO ECONOMICO REAL ===
   int calRowH = (int)(28 * g_fontBase / 9.0);                      // altura por evento
   int calVisible = (g_calCount > 0) ? MathMin(g_calCount, 12) : 1; // cap 12 eventos
   int calH = (int)(90 * g_fontBase / 9.0) + calVisible * calRowH + 14;
   Card("C_CardCal", cx, cy, cw, calH, true, CLR_ACCENT_YELLOW);

   px = cx + CARD_PAD; py = cy + CARD_PAD + 4;
   Label("C_CalTitle", px, py, "CALENDARIO", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");

   //--- Indicador de update (verde se recente) ---
   if(g_calLastUpdate > 0)
   {
      datetime updAdj = g_calLastUpdate + g_tzShift * 3600;
      MqlDateTime dtUpd; TimeToStruct(updAdj, dtUpd);
      string updTxt = StringFormat("Atualizado %02d:%02d", dtUpd.hour, dtUpd.min);
      Label("C_CalUpd", px + innerW - 120, py + 2, updTxt, CLR_TEXT_MUTED, g_fontSmall - 1);
   }
   else
   {
      Label("C_CalUpd", px + innerW - 120, py + 2, "--:--", CLR_TEXT_MUTED, g_fontSmall - 1);
   }

   py += g_fontSection + 18;

   //--- Header row: Hora | Cur | Imp | Evento | Actual | Fcst | Prev ---
   int colTime = 0;
   int colCur  = 42;
   int colImp  = 78;
   int colName = 108;
   int colAct  = innerW - 170;
   int colFcst = innerW - 110;
   int colPrev = innerW - 50;

   Label("C_CalH1", px + colTime, py, "Hora", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   Label("C_CalH2", px + colCur,  py, "Cur",  CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   Label("C_CalH3", px + colImp,  py, "Imp",  CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   Label("C_CalH4", px + colName, py, "Evento", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   Label("C_CalH5", px + colAct,  py, "Act",  CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   Label("C_CalH6", px + colFcst, py, "Fcst", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   Label("C_CalH7", px + colPrev, py, "Prev", CLR_TEXT_DIM, g_fontSmall - 1, "Segoe UI Semibold");
   py += g_fontSmall + 12;

   //--- Linha separadora ---
   Rect("C_CalHLine", px, py, innerW, 1, CLR_SEPARATOR);
   py += 10;

   //--- Estado vazio ---
   if(g_calCount == 0)
   {
      Label("C_CalEmpty", px + innerW / 2 - 120, py + calRowH / 2 - 6,
         "Nenhum evento importante hoje", CLR_TEXT_DIM, g_fontSmall);
   }
   else
   {
      //--- Lista de eventos reais ---
      datetime nowAdj = TimeCurrent() + g_tzShift * 3600;

      for(int i = 0; i < calVisible; i++)
      {
         string id = IntegerToString(i);
         int ry = py + i * calRowH;

         //--- Fundo alternado (ANTES dos textos - z-order) ---
         if(i % 2 == 0)
            Rect("C_CalBg" + id, px - 4, ry - 2, innerW + 8, calRowH - 2, C'18,22,32');

         //--- Cor da importancia ---
         color impClr = CLR_TEXT_DIM;
         string impTxt = "*";
         if(g_calEvents[i].importance == CALENDAR_IMPORTANCE_LOW)
            { impClr = CLR_ACCENT_GREEN;  impTxt = "*"; }
         else if(g_calEvents[i].importance == CALENDAR_IMPORTANCE_MODERATE)
            { impClr = CLR_ACCENT_YELLOW; impTxt = "**"; }
         else if(g_calEvents[i].importance == CALENDAR_IMPORTANCE_HIGH)
            { impClr = CLR_ACCENT_RED;    impTxt = "***"; }

         //--- Hora: cor branco se futuro, dim se passado ---
         datetime eventAdj = g_calEvents[i].eventTime + g_tzShift * 3600;
         color timeClr = (eventAdj > TimeCurrent() + g_tzShift * 3600)
                         ? CLR_TEXT_WHITE : CLR_TEXT_DIM;

         //--- Desenha elementos da linha ---
         Label("C_CalT" + id, px + colTime, ry + 3, g_calEvents[i].timeStr,
            timeClr, g_fontSmall - 1, "Segoe UI Semibold");

         Label("C_CalCur" + id, px + colCur, ry + 3, g_calEvents[i].currency,
            CLR_TEXT_LIGHT, g_fontSmall - 1, "Segoe UI Semibold");

         Label("C_CalImp" + id, px + colImp, ry + 1, impTxt, impClr,
            g_fontNormal + 2, "Segoe UI Bold");

         //--- Nome do evento (truncado para caber) ---
         string evName = g_calEvents[i].name;
         int maxEvLen = 32;
         if(StringLen(evName) > maxEvLen)
            evName = StringSubstr(evName, 0, maxEvLen - 2) + "..";
         Label("C_CalEv" + id, px + colName, ry + 3, evName,
            CLR_TEXT_LIGHT, g_fontSmall - 1);

         //--- Actual (verde/vermelho baseado em comparacao) ---
         color actClr = CLR_TEXT_LIGHT;
         if(g_calEvents[i].hasActual)
            actClr = g_calEvents[i].actualBetter ? CLR_ACCENT_GREEN : CLR_ACCENT_RED;
         Label("C_CalAct" + id, px + colAct, ry + 3, g_calEvents[i].actual,
            actClr, g_fontSmall - 1, g_calEvents[i].hasActual ? "Segoe UI Bold" : "Segoe UI");

         //--- Forecast ---
         Label("C_CalFcst" + id, px + colFcst, ry + 3, g_calEvents[i].forecast,
            CLR_TEXT_DIM, g_fontSmall - 1);

         //--- Previous ---
         Label("C_CalPrev" + id, px + colPrev, ry + 3, g_calEvents[i].previous,
            CLR_TEXT_DIM, g_fontSmall - 1);
      }
   }
}


//=====================================================================
// [17] ABA RELATORIOS
// Performance completa, filtros, dados por estrategia.
//=====================================================================

void DrawTabReports(int cx, int cy, int cw)
{
   int innerW = cw - 2 * CARD_PAD;

   //=== FILTROS (botoes maiores) ===
   int px = cx, py = cy;
   string filters[] = {"Hoje","Semana","Mes","Ano"};
   int btnW = 75;                                                    // mais largo
   int btnH = 28;                                                    // mais alto
   for(int i = 0; i < 4; i++)
   {
      color bg = (i == g_reportFilter) ? CLR_BTN_PRIMARY : CLR_BTN_SECONDARY;
      color txt = (i == g_reportFilter) ? CLR_TEXT_WHITE : CLR_TEXT_DIM;
      Btn("C_Filter" + IntegerToString(i), px + i * (btnW + 6), py, btnW, btnH,
         filters[i], bg, txt, g_fontSmall);
   }

   Btn("C_BtnExport", px + cw - 110, py, 105, btnH, "Exportar PDF", CLR_BTN_SECONDARY, CLR_ACCENT_YELLOW, g_fontSmall);
   py += btnH + 12;

   //=== CARD: RESUMO ===
   int sumH = (int)(210 * g_fontBase / 9.0);                        // mais alto (barras + timestamps)
   Card("C_CardSum", cx, py, cw, sumH, true, CLR_ACCENT_CYAN);

   int sx = cx + CARD_PAD;
   int sy = py + CARD_PAD + 4;
   Label("C_SumTitle", sx, sy, "RESUMO", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   sy += g_fontSection + 20;

   //--- Dados consolidados ---
   double totalProfit = g_eaProfit + g_manualProfit;
   double totalLoss = g_eaLoss + g_manualLoss;
   double netPnL = totalProfit + totalLoss;
   int totalWins = g_eaWins + g_manualWins;
   int totalLosses = g_eaLosses + g_manualLosses;
   int totalTrades = totalWins + totalLosses;
   color netClr = (netPnL >= 0) ? CLR_ACCENT_GREEN : CLR_ACCENT_RED;
   double wrPct = (totalTrades > 0) ? (double)totalWins / totalTrades * 100.0 : 0;
   double profitRatio = (totalProfit + MathAbs(totalLoss) > 0) ? totalProfit / (totalProfit + MathAbs(totalLoss)) * 100 : 50;

   //--- 4 sub-cards (80px com mini barra) ---
   int miniW = (innerW - 24) / 4;
   int miniH = 100;

   //--- Lucro Bruto ---
   Rect("C_SumM1Bg", sx, sy, miniW, miniH, CLR_BG_INPUT);
   Label("C_SumM1L", sx + 6, sy + 6, "Lucro Bruto", CLR_TEXT_DIM, g_fontSmall - 1);
   Label("C_SumM1V", sx + 6, sy + 38, FmtMoney(totalProfit), CLR_ACCENT_GREEN, g_fontSmall, "Segoe UI Bold");
   ProgressBar("C_SumM1Bar", sx + 4, sy + miniH - 18, miniW - 8, 10, profitRatio, CLR_BAR_GREEN);

   //--- Perda Bruta ---
   int m2x = sx + miniW + 8;
   Rect("C_SumM2Bg", m2x, sy, miniW, miniH, CLR_BG_INPUT);
   Label("C_SumM2L", m2x + 6, sy + 6, "Perda Bruta", CLR_TEXT_DIM, g_fontSmall - 1);
   Label("C_SumM2V", m2x + 6, sy + 38, FmtMoney(totalLoss), CLR_ACCENT_RED, g_fontSmall, "Segoe UI Bold");
   ProgressBar("C_SumM2Bar", m2x + 4, sy + miniH - 18, miniW - 8, 10, 100 - profitRatio, CLR_BAR_RED);

   //--- Liquido ---
   int m3x = sx + 2 * (miniW + 8);
   Rect("C_SumM3Bg", m3x, sy, miniW, miniH, CLR_BG_INPUT);
   Label("C_SumM3L", m3x + 6, sy + 6, "Liquido", CLR_TEXT_DIM, g_fontSmall - 1);
   Label("C_SumM3V", m3x + 6, sy + 38, FmtMoney(netPnL), netClr, g_fontSmall, "Segoe UI Bold");
   ProgressBar("C_SumM3Bar", m3x + 4, sy + miniH - 18, miniW - 8, 10,
      MathMin(100, MathAbs(netPnL) / MathMax(1, totalProfit + MathAbs(totalLoss)) * 100),
      (netPnL >= 0) ? CLR_BAR_GREEN : CLR_BAR_RED);

   //--- WinRate ---
   int m4x = sx + 3 * (miniW + 8);
   Rect("C_SumM4Bg", m4x, sy, miniW, miniH, CLR_BG_INPUT);
   Label("C_SumM4L", m4x + 6, sy + 6, "WinRate", CLR_TEXT_DIM, g_fontSmall - 1);
   Label("C_SumM4V", m4x + 6, sy + 38, FmtWinRate(totalWins, totalTrades), CLR_TEXT_WHITE, g_fontSmall, "Segoe UI Bold");
   ProgressBar("C_SumM4Bar", m4x + 4, sy + miniH - 18, miniW - 8, 10, wrPct,
      (wrPct >= 50) ? CLR_BAR_GREEN : CLR_BAR_RED);

   sy += miniH + 8;

   //--- Timestamps (ultimo trade + ultima atualizacao) ---
   string lastTradeTxt = "Ultimo trade: --:--:--";
   if(g_lastTradeTime > 0)
   {
      datetime adjLT = g_lastTradeTime + g_tzShift * 3600;
      MqlDateTime dtLT; TimeToStruct(adjLT, dtLT);
      lastTradeTxt = "Ultimo trade: " + StringFormat("%02d:%02d:%02d", dtLT.hour, dtLT.min, dtLT.sec);
   }
   string lastUpdTxt = "Atualizado: --:--:--";
   if(g_lastUpdateTime > 0)
   {
      datetime adjUp = g_lastUpdateTime + g_tzShift * 3600;
      MqlDateTime dtUp; TimeToStruct(adjUp, dtUp);
      lastUpdTxt = "Atualizado: " + StringFormat("%02d:%02d:%02d", dtUp.hour, dtUp.min, dtUp.sec);
   }
   Label("C_SumTS1", sx, sy, lastTradeTxt, CLR_TEXT_MUTED, g_fontSmall - 1);
   Label("C_SumTS2", sx + innerW / 2, sy, lastUpdTxt, CLR_TEXT_MUTED, g_fontSmall - 1);

   py += sumH + CARD_GAP;

   //=== CARD: EA (nome dinamico) ===
   int detH = (int)(240 * g_fontBase / 9.0);                        // mais alto
   Card("C_CardDetEA", cx, py, cw, detH, true, CLR_ACCENT_BLUE);

   sx = cx + CARD_PAD; sy = py + CARD_PAD + 4;
   //--- Nome do EA (dinamico) ---
   string eaName = ChartGetString(0, CHART_EXPERT_NAME);
   if(eaName == "" || StringLen(eaName) < 2) eaName = "EA";
   Label("C_DetEATitle", sx, sy, eaName, CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   sy += g_fontSection + 20;

   LabelValue("C_DetEAGross", sx, sy, "Lucro Bruto:", FmtMoney(g_eaProfit),
      CLR_TEXT_DIM, CLR_ACCENT_GREEN, sx + 155);
   sy += g_lineHSmall + 5;
   LabelValue("C_DetEALoss", sx, sy, "Perda Bruta:", FmtMoney(g_eaLoss),
      CLR_TEXT_DIM, CLR_ACCENT_RED, sx + 155);
   sy += g_lineHSmall + 5;
   LabelValue("C_DetEANet", sx, sy, "Resultado:", FmtMoney(g_eaProfit + g_eaLoss),
      CLR_TEXT_DIM, (g_eaProfit + g_eaLoss >= 0) ? CLR_ACCENT_GREEN : CLR_ACCENT_RED, sx + 155);
   sy += g_lineHSmall + 5;
   LabelValue("C_DetEAWins", sx, sy, "Vitorias:", IntegerToString(g_eaWins) + " trades",
      CLR_TEXT_DIM, CLR_TEXT_LIGHT, sx + 155);
   sy += g_lineHSmall + 5;
   LabelValue("C_DetEALosses", sx, sy, "Derrotas:", IntegerToString(g_eaLosses) + " trades",
      CLR_TEXT_DIM, CLR_TEXT_LIGHT, sx + 155);
   sy += g_lineHSmall + 5;
   LabelValue("C_DetEAWR", sx, sy, "WinRate:", FmtWinRate(g_eaWins, g_eaWins + g_eaLosses),
      CLR_TEXT_DIM, CLR_TEXT_WHITE, sx + 155);

   py += detH + CARD_GAP;

   //=== CARD: TRADES MANUAIS ===
   int manDetH = (int)(240 * g_fontBase / 9.0);                     // mais alto
   Card("C_CardDetMan", cx, py, cw, manDetH, true, CLR_ACCENT_PURPLE);

   sx = cx + CARD_PAD; sy = py + CARD_PAD + 4;
   Label("C_DetManTitle", sx, sy, "TRADES MANUAIS", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   sy += g_fontSection + 20;

   LabelValue("C_DetManGross", sx, sy, "Lucro Bruto:", FmtMoney(g_manualProfit),
      CLR_TEXT_DIM, CLR_ACCENT_GREEN, sx + 155);
   sy += g_lineHSmall + 5;
   LabelValue("C_DetManLoss", sx, sy, "Perda Bruta:", FmtMoney(g_manualLoss),
      CLR_TEXT_DIM, CLR_ACCENT_RED, sx + 155);
   sy += g_lineHSmall + 5;
   LabelValue("C_DetManNet", sx, sy, "Resultado:", FmtMoney(g_manualProfit + g_manualLoss),
      CLR_TEXT_DIM, (g_manualProfit + g_manualLoss >= 0) ? CLR_ACCENT_GREEN : CLR_ACCENT_RED, sx + 155);
   sy += g_lineHSmall + 5;
   LabelValue("C_DetManWins", sx, sy, "Vitorias:", IntegerToString(g_manualWins) + " trades",
      CLR_TEXT_DIM, CLR_TEXT_LIGHT, sx + 155);
   sy += g_lineHSmall + 5;
   LabelValue("C_DetManLosses", sx, sy, "Derrotas:", IntegerToString(g_manualLosses) + " trades",
      CLR_TEXT_DIM, CLR_TEXT_LIGHT, sx + 155);
   sy += g_lineHSmall + 5;
   LabelValue("C_DetManWR", sx, sy, "WinRate:", FmtWinRate(g_manualWins, g_manualWins + g_manualLosses),
      CLR_TEXT_DIM, CLR_TEXT_WHITE, sx + 155);

   py += manDetH + CARD_GAP;

   //=== CARD: METRICAS (FASE A) ===
   int advH = (int)(310 * g_fontBase / 9.0);                        // muito mais alto para caber tudo
   Card("C_CardAdv", cx, py, cw, advH, true, CLR_ACCENT_ORANGE);

   sx = cx + CARD_PAD; sy = py + CARD_PAD + 4;
   Label("C_AdvTitle", sx, sy, "METRICAS", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   sy += g_fontSection + 20;

   int col2X = sx + cw / 2;                                          // X da segunda coluna
   int valOff1 = sx + 155;                                            // offset valor coluna 1
   int valOff2 = col2X + 125;                                        // offset valor coluna 2

   //--- Linha 1: Avg Win / Avg Loss ---
   double avgWin = (totalWins > 0) ? totalProfit / totalWins : 0;
   double avgLoss = (totalLosses > 0) ? MathAbs(totalLoss) / totalLosses : 0;
   LabelValue("C_AdvAvgW", sx, sy, "Avg Win:", FmtMoney(avgWin), CLR_TEXT_DIM, CLR_ACCENT_GREEN, valOff1);
   LabelValue("C_AdvAvgL", col2X, sy, "Avg Loss:", FmtMoney(avgLoss), CLR_TEXT_DIM, CLR_ACCENT_RED, valOff2);
   sy += g_lineHSmall + 5;

   //--- Linha 2: Profit Factor / Expectancy ---
   double profitFactor = (MathAbs(totalLoss) > 0) ? totalProfit / MathAbs(totalLoss) : 0;
   double expectancy = (totalTrades > 0) ? netPnL / totalTrades : 0;
   LabelValue("C_AdvPF", sx, sy, "Profit Factor:", DoubleToString(profitFactor, 2), CLR_TEXT_DIM,
      (profitFactor >= 1.0) ? CLR_ACCENT_GREEN : CLR_ACCENT_RED, valOff1);
   LabelValue("C_AdvExp", col2X, sy, "Expectancy:", FmtMoney(expectancy), CLR_TEXT_DIM,
      (expectancy >= 0) ? CLR_ACCENT_GREEN : CLR_ACCENT_RED, valOff2);
   sy += g_lineHSmall + 5;

   //--- Linha 3: Best Trade / Worst Trade ---
   LabelValue("C_AdvBest", sx, sy, "Melhor Trade:", FmtMoney(g_bestTrade), CLR_TEXT_DIM, CLR_ACCENT_GREEN, valOff1);
   LabelValue("C_AdvWorst", col2X, sy, "Pior Trade:", FmtMoney(g_worstTrade), CLR_TEXT_DIM, CLR_ACCENT_RED, valOff2);
   sy += g_lineHSmall + 5;

   //--- Linha 4: Drawdown Max / Drawdown Atual ---
   color ddMaxClr = (g_maxDrawdown > 0) ? CLR_ACCENT_RED : CLR_TEXT_LIGHT;
   color ddCurClr = (g_curDrawdown > 0) ? CLR_ACCENT_YELLOW : CLR_TEXT_LIGHT;
   LabelValue("C_AdvDDMax", sx, sy, "Max Drawdown:", FmtMoney(-g_maxDrawdown), CLR_TEXT_DIM, ddMaxClr, valOff1);
   LabelValue("C_AdvDDCur", col2X, sy, "DD Atual:", FmtMoney(-g_curDrawdown), CLR_TEXT_DIM, ddCurClr, valOff2);
   sy += g_lineHSmall + 5;

   //--- Barra visual de drawdown (proporcao DD atual / DD max) ---
   double ddPct = (g_maxDrawdown > 0) ? g_curDrawdown / g_maxDrawdown * 100.0 : 0;
   ProgressBar("C_AdvDDBar", sx, sy, cw - 2 * CARD_PAD, 12, ddPct, CLR_BAR_RED);
   sy += 22;                                                         // gap generoso apos barra

   //--- Linha 5: Recovery Factor / Duracao Media ---
   color recClr = (g_recoveryFact >= 1.0) ? CLR_ACCENT_GREEN : CLR_ACCENT_RED;
   LabelValue("C_AdvRecov", sx, sy, "Recuperacao:", DoubleToString(g_recoveryFact, 2) + "x", CLR_TEXT_DIM, recClr, valOff1);

   //--- Formata duracao media em hh:mm:ss ---
   int durSec = (int)g_avgDuration;
   int durH = durSec / 3600; int durM = (durSec % 3600) / 60; int durS = durSec % 60;
   string durTxt = StringFormat("%02d:%02d:%02d", durH, durM, durS);
   LabelValue("C_AdvDur", col2X, sy, "Duracao Media:", durTxt, CLR_TEXT_DIM, CLR_TEXT_LIGHT, valOff2);
   sy += g_lineHSmall + 5;

   //--- Linha 6: Sequencia / Total Trades ---
   string streakTxt = "";
   color streakClr = CLR_TEXT_LIGHT;
   if(g_consecWins > 0) { streakTxt = IntegerToString(g_consecWins) + " wins"; streakClr = CLR_ACCENT_GREEN; }
   else if(g_consecLosses > 0) { streakTxt = IntegerToString(g_consecLosses) + " losses"; streakClr = CLR_ACCENT_RED; }
   else streakTxt = "0";
   LabelValue("C_AdvStreak", sx, sy, "Sequencia:", streakTxt, CLR_TEXT_DIM, streakClr, valOff1);
   LabelValue("C_AdvTrades", col2X, sy, "Total Trades:", IntegerToString(totalTrades), CLR_TEXT_DIM, CLR_TEXT_WHITE, valOff2);
}


//=====================================================================
// [18] ABA CONFIGURACOES
// Fonte, fuso horario, comissao.
//=====================================================================

void DrawTabConfig(int cx, int cy, int cw)
{
   int innerW = cw - 2 * CARD_PAD;
   int px = cx, py = cy;
   int btnSz = (int)(30 * g_fontBase / 9.0);                        // tamanho dos botoes +/-

   //=== CARD 1: TAMANHO DA FONTE ===
   int fontH = (int)(110 * g_fontBase / 9.0);                       // mais alto
   Card("C_CardFont", cx, py, cw, fontH, true, CLR_ACCENT_BLUE);

   int sx = cx + CARD_PAD, sy = py + CARD_PAD + 4;
   Label("C_CfgFontTitle", sx, sy, "TAMANHO DA FONTE", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   sy += g_fontSection + 22;                                         // espaco grande titulo -> controles

   Btn("C_BtnFontDown", sx, sy, btnSz, btnSz, "-", CLR_BTN_SECONDARY, CLR_ACCENT_RED, g_fontTitle);
   Label("C_CfgFontVal", sx + btnSz + 18, sy + 5, IntegerToString(g_fontBase) + " pt",
      CLR_TEXT_WHITE, g_fontTitle, "Segoe UI Bold");
   Btn("C_BtnFontUp", sx + btnSz * 2 + 30, sy, btnSz, btnSz, "+", CLR_BTN_SECONDARY, CLR_ACCENT_GREEN, g_fontTitle);
   Label("C_CfgFontPrev", sx + btnSz * 3 + 55, sy + 8, "Preview Abc 123", CLR_TEXT_DIM, g_fontNormal);
   sy += btnSz + 12;
   Label("C_CfgFontInfo", sx, sy, "Titulo:" + IntegerToString(g_fontTitle) + "  Normal:" + IntegerToString(g_fontNormal) + "  Pequeno:" + IntegerToString(g_fontSmall),
      CLR_TEXT_MUTED, g_fontSmall - 1);

   py += fontH + CARD_GAP;

   //=== CARD 2: FUSO HORARIO + MOEDA ===
   int tzH = (int)(130 * g_fontBase / 9.0);                         // mais alto para caber moeda
   Card("C_CardTZ", cx, py, cw, tzH, true, CLR_ACCENT_CYAN);

   sx = cx + CARD_PAD; sy = py + CARD_PAD + 4;
   Label("C_CfgTZTitle", sx, sy, "FUSO HORARIO", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   sy += g_fontSection + 22;

   Btn("C_BtnTZDown", sx, sy, btnSz, btnSz, "-", CLR_BTN_SECONDARY, CLR_ACCENT_RED, g_fontTitle);
   string tzSign = (g_tzShift >= 0) ? "+" : "";
   Label("C_CfgTZVal", sx + btnSz + 18, sy + 5, "UTC" + tzSign + IntegerToString(g_tzShift),
      CLR_TEXT_WHITE, g_fontTitle, "Segoe UI Bold");
   Btn("C_BtnTZUp", sx + btnSz * 2 + 50, sy, btnSz, btnSz, "+", CLR_BTN_SECONDARY, CLR_ACCENT_GREEN, g_fontTitle);

   //--- Nome do fuso ---
   string tzName = "Custom";
   if(g_tzShift == 9) tzName = "Japao (JST)";
   else if(g_tzShift == 0) tzName = "UTC/GMT";
   else if(g_tzShift == -3) tzName = "Brasilia (BRT)";
   else if(g_tzShift == -5) tzName = "New York (EST)";
   else if(g_tzShift == 1) tzName = "London (BST)";
   Label("C_CfgTZName", sx + btnSz * 3 + 75, sy + 8, tzName, CLR_TEXT_DIM, g_fontNormal);
   sy += btnSz + 16;

   //--- Informacao da moeda da conta (formato e simbolo) ---
   string currSymbol = "";
   string currFmt = "";
   if(g_acctCurrency == "USD")      { currSymbol = "$";  currFmt = "1,234.56"; }
   else if(g_acctCurrency == "JPY") { currSymbol = "\x00A5"; currFmt = "1,234"; }
   else if(g_acctCurrency == "EUR") { currSymbol = "EUR";  currFmt = "1.234,56"; }
   else if(g_acctCurrency == "GBP") { currSymbol = "GBP";  currFmt = "1,234.56"; }
   else if(g_acctCurrency == "BRL") { currSymbol = "R$"; currFmt = "1.234,56"; }
   else { currSymbol = g_acctCurrency; currFmt = "1,234.56"; }

   Label("C_CfgCurrLbl", sx, sy, "Moeda:", CLR_TEXT_DIM, g_fontSmall);
   Label("C_CfgCurrVal", sx + 55, sy, g_acctCurrency + " (" + currSymbol + ")", CLR_TEXT_LIGHT, g_fontSmall, "Segoe UI Semibold");
   Label("C_CfgCurrFmt", sx + 200, sy, "Formato: " + currFmt, CLR_TEXT_DIM, g_fontSmall);

   py += tzH + CARD_GAP;

   //=== CARD 3: COMISSAO ===
   int commH = (int)(105 * g_fontBase / 9.0);                       // mais alto
   Card("C_CardComm", cx, py, cw, commH, true, CLR_ACCENT_YELLOW);

   sx = cx + CARD_PAD; sy = py + CARD_PAD + 4;
   Label("C_CfgCommTitle", sx, sy, "COMISSAO POR LOTE (1 LADO)", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   sy += g_fontSection + 22;

   Btn("C_BtnCommDown", sx, sy, btnSz, btnSz, "-", CLR_BTN_SECONDARY, CLR_ACCENT_RED, g_fontTitle);
   Label("C_CfgCommVal", sx + btnSz + 18, sy + 5, FmtMoney(g_commission),
      CLR_TEXT_WHITE, g_fontTitle, "Segoe UI Bold");
   Btn("C_BtnCommUp", sx + btnSz * 2 + 50, sy, btnSz, btnSz, "+", CLR_BTN_SECONDARY, CLR_ACCENT_GREEN, g_fontTitle);
   Label("C_CfgCommInfo", sx + btnSz * 3 + 75, sy + 8, "Ida+volta: " + FmtMoney(g_commission * 2),
      CLR_TEXT_DIM, g_fontNormal);

   py += commH + CARD_GAP;

   //=== CARD 4: SENSORES MKS ===
   int snsRowH = 34;                                                  // altura maior para breathing room
   int snsH = (int)(75 * g_fontBase / 9.0) + SENSOR_COUNT * snsRowH; // titulo + N sensores
   Card("C_CardSns", cx, py, cw, snsH, true, CLR_ACCENT_PURPLE);

   sx = cx + CARD_PAD; sy = py + CARD_PAD + 4;
   Label("C_CfgSnsTitle", sx, sy, "SENSORES", CLR_TEXT_WHITE, g_fontSection, "Segoe UI Semibold");
   sy += g_fontSection + 20;

   //--- Lista de sensores com dot + nome + toggle ---
   for(int si = 0; si < SENSOR_COUNT; si++)
   {
      int rowY = sy + si * snsRowH;
      string id = IntegerToString(si);

      //--- Fundo alternado (criar ANTES dos textos - z-order) ---
      if(si % 2 == 0)
         Rect("C_SnsCfgBg" + id, sx - 4, rowY - 3,
            cw - 2 * CARD_PAD + 8, snsRowH - 4, C'18,22,32');

      //--- Dot de status (12x12) ---
      color dotClr = CLR_TEXT_MUTED;
      if(g_sensors[si].status == 2)      dotClr = CLR_ACCENT_GREEN;
      else if(g_sensors[si].status == 1) dotClr = CLR_ACCENT_YELLOW;
      Rect("C_SnsCfgDot" + id, sx, rowY + 7, 12, 12, dotClr);

      //--- Nome do sensor ---
      Label("C_SnsCfgName" + id, sx + 22, rowY + 5, g_sensors[si].displayName,
         (g_sensors[si].status == 0) ? CLR_TEXT_DIM : CLR_TEXT_LIGHT,
         g_fontSmall, "Segoe UI Semibold");

      //--- Texto de status ---
      string statTxt = "DESENVOLVIMENTO";
      if(g_sensors[si].status == 2)      statTxt = "CARREGADO";
      else if(g_sensors[si].status == 1) statTxt = "NAO ENCONTRADO";
      Label("C_SnsCfgStat" + id, sx + 200, rowY + 5, statTxt,
         dotClr, g_fontSmall - 1);

      //--- Toggle ON/OFF (so para nao-dev) ---
      if(g_sensors[si].status != 0)
      {
         color tgBg  = g_sensors[si].enabled ? CLR_ACCENT_GREEN : CLR_BTN_SECONDARY;
         color tgTxt = g_sensors[si].enabled ? CLR_TEXT_WHITE : CLR_TEXT_DIM;
         string tgLbl = g_sensors[si].enabled ? "ON" : "OFF";
         Btn("C_SnsToggle" + id, sx + cw - 2 * CARD_PAD - 55, rowY + 4, 50, 24,
            tgLbl, tgBg, tgTxt, g_fontSmall);
      }
      else
      {
         Label("C_SnsDev" + id, sx + cw - 2 * CARD_PAD - 30, rowY + 6, "--",
            CLR_TEXT_MUTED, g_fontSmall);
      }
   }

   py += snsH + CARD_GAP;

   //=== INFO DE PERSISTENCIA ===
   Label("C_CfgSaved", cx + CARD_PAD, py + 5, "Configuracoes salvas automaticamente via GlobalVariables",
      CLR_TEXT_MUTED, g_fontSmall - 1);
}


//=====================================================================
// [19] TROCA DE ABAS
// Atualiza cores das abas e redesenha conteudo.
//=====================================================================

void SwitchTab(int newTab)
{
   if(newTab < 0 || newTab >= TAB_COUNT) return;                     // valida indice
   g_activeTab = newTab;                                              // atualiza aba ativa

   //--- Atualiza visual das abas ---
   for(int i = 0; i < TAB_COUNT; i++)                                // percorre todas
   {
      string btn = N("Tab" + IntegerToString(i));                    // nome do botao
      if(ObjectFind(0, btn) < 0) continue;                           // nao encontrou

      color bg  = (i == g_activeTab) ? CLR_TAB_ACTIVE : CLR_TAB_INACTIVE;
      color txt = (i == g_activeTab) ? CLR_TEXT_WHITE : CLR_TEXT_DIM;
      ObjectSetInteger(0, btn, OBJPROP_BGCOLOR, bg);                 // atualiza fundo
      ObjectSetInteger(0, btn, OBJPROP_COLOR, txt);                  // atualiza texto
      ObjectSetInteger(0, btn, OBJPROP_STATE, false);                // reset estado

      //--- Linha de acento ---
      string accName = N("TabAcc" + IntegerToString(i));             // nome da linha acento
      if(i == g_activeTab)                                            // aba ativa
      {
         int tabW = g_panelW / TAB_COUNT;                            // largura aba
         int tabX = g_panelX + i * tabW;                             // X da aba
         int tabY = g_panelY + g_headerH + 1;                       // Y da aba
         if(ObjectFind(0, accName) < 0)                              // se nao existe
            Rect("TabAcc" + IntegerToString(i), tabX + 2, tabY + g_tabH - 2, tabW - 4, 2, CLR_ACCENT_BLUE);
         else
            ShowObj("TabAcc" + IntegerToString(i), true);            // mostra
      }
      else
      {
         if(ObjectFind(0, accName) >= 0)                             // se existe
            ShowObj("TabAcc" + IntegerToString(i), false);           // oculta
      }
   }

   //--- Coleta dados especificos da aba antes de desenhar ---
   if(g_activeTab == 0 || g_activeTab == 3)                          // Dashboard ou Relatorios
   {
      UpdatePerformanceData();
      UpdateIntelligenceData();
   }
   if(g_activeTab == 2)                                               // Mercado: recarrega calendario
   {
      UpdateCalendarData();
   }

   DrawActiveTab();                                                   // redesenha conteudo
   ChartRedraw(0);                                                   // aplica mudancas
}


//=====================================================================
// [20] MINIMIZAR / RESTAURAR
//=====================================================================

void ToggleMinimize()
{
   g_minimized = !g_minimized;                                       // toggle estado

   //--- Atualiza botao ---
   string btn = N("BtnMin");
   if(ObjectFind(0, btn) >= 0)
   {
      ObjectSetString(0, btn, OBJPROP_TEXT, g_minimized ? "+" : "-");  // icone
      ObjectSetInteger(0, btn, OBJPROP_STATE, false);                 // reset
   }

   //--- Quando minimizado: esconde TUDO menos header compacto ---
   //--- Redimensiona fundo principal para so o header ---
   string mainBg = N("MainBg");
   if(ObjectFind(0, mainBg) >= 0)
   {
      if(g_minimized)
         ObjectSetInteger(0, mainBg, OBJPROP_YSIZE, g_headerH + 2);  // so header
      else
         ObjectSetInteger(0, mainBg, OBJPROP_YSIZE, g_panelH);       // painel inteiro
   }

   //--- Oculta/mostra abas ---
   for(int i = 0; i < TAB_COUNT; i++)
      ShowObj("Tab" + IntegerToString(i), !g_minimized);

   //--- Oculta/mostra fundo conteudo e separadores ---
   ShowObj("ContentBg", !g_minimized);
   ShowObj("HdrLine", !g_minimized);

   //--- Oculta/mostra TODOS objetos com prefixo (exceto header e botao min) ---
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, OBJ_PREFIX) != 0) continue;               // nao e nosso objeto

      //--- Preserva header essencial quando minimizado ---
      if(name == N("MainBg")) continue;                              // fundo ja ajustado acima
      if(name == N("Header")) continue;                              // header sempre visivel
      if(name == N("BtnMin")) continue;                              // botao sempre visivel
      if(name == N("HdrLogo")) continue;                             // simbolo sempre visivel
      if(name == N("HdrTime")) continue;                             // hora sempre visivel

      //--- Oculta todo o resto quando minimizado ---
      if(StringFind(name, OBJ_PREFIX + "C_") == 0 ||                // conteudo de abas
         StringFind(name, OBJ_PREFIX + "Tab") == 0 ||               // abas
         StringFind(name, OBJ_PREFIX + "Content") == 0 ||           // fundo conteudo
         StringFind(name, OBJ_PREFIX + "HdrLine") == 0 ||           // separador header
         StringFind(name, OBJ_PREFIX + "HdrDate") == 0)             // data
      {
         ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES,
            g_minimized ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
      }
   }

   ChartRedraw(0);
}


//=====================================================================
// [21] ALTERACAO DE CONFIGURACOES
// Fonte, fuso e comissao com persistencia via GlobalVariable.
//=====================================================================

void ChangeFontSize(int delta)
{
   g_fontBase += delta;                                               // incrementa/decrementa
   CalculateFonts();                                                  // recalcula fontes
   GlobalVariableSet(g_gvFont, g_fontBase);                          // persiste
   DeleteAll(); BuildPanel(); ChartRedraw(0);                        // recria tudo
}

void ChangeTimezone(int delta)
{
   g_tzShift += delta;                                                // incrementa/decrementa
   if(g_tzShift < -12) g_tzShift = -12;                             // limite inferior
   if(g_tzShift > 14)  g_tzShift = 14;                              // limite superior
   GlobalVariableSet(g_gvTZ, g_tzShift);                             // persiste
   DeleteAll(); BuildPanel(); ChartRedraw(0);                        // recria tudo
}

void ChangeCommission(double delta)
{
   g_commission += delta;                                             // incrementa/decrementa
   if(g_commission < 0) g_commission = 0;                            // limite inferior
   if(g_commission > 100) g_commission = 100;                        // limite superior
   GlobalVariableSet(g_gvComm, g_commission);                        // persiste
   DeleteAll(); BuildPanel(); ChartRedraw(0);                        // recria tudo
}


//=====================================================================
// [22] API PUBLICA — REGISTRO DE ESTRATEGIAS
// EAs externos chamam estas funcoes para registrar estrategias
// e atualizar o estado no dashboard.
//=====================================================================

//--- Registra uma estrategia no dashboard ---
void RegisterStrategy(string name, bool active = true)
{
   if(g_stratCount >= MAX_STRATEGIES) return;                        // limite
   g_stratNames[g_stratCount] = name;                                // nome
   g_stratActive[g_stratCount] = active;                             // estado
   g_stratCount++;                                                    // incrementa
}


//=====================================================================
// [23] ATUALIZA CURVA P&L (CHAMADO PERIODICAMENTE)
// Adiciona ponto na curva a cada minuto.
//=====================================================================

void UpdatePnLCurve()
{
   double currentPnL = g_eaProfit + g_eaLoss + g_manualProfit + g_manualLoss;  // P&L total

   if(g_pnlCount < PNL_POINTS)                                      // se ainda tem espaco
   {
      g_pnlCurve[g_pnlCount] = currentPnL;                          // adiciona ponto
      g_pnlCount++;                                                  // incrementa
   }
   else                                                               // buffer cheio
   {
      //--- Shift para esquerda (remove o mais antigo) ---
      for(int i = 0; i < PNL_POINTS - 1; i++)                       // shift
         g_pnlCurve[i] = g_pnlCurve[i + 1];
      g_pnlCurve[PNL_POINTS - 1] = currentPnL;                     // adiciona no final
   }
}


//=====================================================================
// [24] ONINIT — INICIALIZACAO
// Configura abas, restaura persistencia, detecta framework,
// cria handles e monta o painel.
//=====================================================================

int OnInit()
{
   //--- Nomes das abas ---
   g_tabLabels[0] = "DASHBOARD";                                     // aba 0
   g_tabLabels[1] = "ROBO";                                          // aba 1 (sem acento — MQL5 nao suporta)
   g_tabLabels[2] = "MERCADO";                                       // aba 2
   g_tabLabels[3] = "RELATORIOS";                                    // aba 3
   g_tabLabels[4] = "CONFIG";                                        // aba 4

   //--- Simbolo ---
   g_symbol = Symbol();                                               // resolve simbolo
   g_acctCurrency = GetAccountCurrency();                             // moeda da conta

   //--- Restaura configuracoes persistidas ---
   if(GlobalVariableCheck(g_gvFont))                                 // fonte salva?
      g_fontBase = (int)GlobalVariableGet(g_gvFont);                 // restaura
   else
      g_fontBase = InpFontSize;                                      // usa input
   CalculateFonts();                                                  // calcula fontes

   if(GlobalVariableCheck(g_gvComm))                                 // comissao salva?
      g_commission = GlobalVariableGet(g_gvComm);                    // restaura
   else
      g_commission = InpCommission;                                   // usa input

   if(GlobalVariableCheck(g_gvTZ))                                   // fuso salvo?
      g_tzShift = (int)GlobalVariableGet(g_gvTZ);                   // restaura
   else
      g_tzShift = InpTimezoneShift;                                   // usa input

   //--- Detecta framework Renko ---
   DetectFramework();                                                 // busca CS

   //--- Cria handle ATR D1 ---
   g_hATR_D1 = iATR(g_symbol, PERIOD_D1, 21);                      // ATR(21) diario

   //--- Registra estrategias de exemplo (placeholder) ---
   RegisterStrategy("Trend Following", true);                        // estrategia 1
   RegisterStrategy("Mean Reversion", true);                         // estrategia 2
   RegisterStrategy("Breakout", false);                              // estrategia 3
   RegisterStrategy("Scalp Renko", true);                            // estrategia 4

   //--- Inicializa P&L curve com zeros ---
   ArrayInitialize(g_pnlCurve, 0.0);                                // zera curva
   g_pnlCount = 0;                                                   // nenhum ponto

   //--- Estado inicial ---
   g_activeTab = 0;                                                   // aba Dashboard
   g_minimized = false;                                              // nao minimizado
   g_lastMinute = 0;                                                 // sem referencia
   g_tickCount = 0;                                                  // sem ticks
   g_ticksPerMin = 0;                                                // sem ticks/min

   //--- Coleta dados iniciais ---
   UpdatePerformanceData(); UpdateIntelligenceData();

   //--- Inicializa sensores (carrega toggles persistidos) ---
   InitSensors();
   UpdateSensorsData();

   //--- Carrega calendario economico real ---
   UpdateCalendarData();

   //--- Constroi painel ---
   DeleteAll();                                                       // limpa objetos anteriores
   BuildPanel();                                                      // monta o painel
   ChartRedraw(0);                                                   // renderiza

   PrintFormat("[24] MKS Dashboard Pro v5 iniciado — %s | TZ: UTC%+d | Font: %d",
      g_symbol, g_tzShift, g_fontBase);                               // log de inicializacao

   return(INIT_SUCCEEDED);                                            // sucesso
}


//=====================================================================
// [25] ONCALCULATE — ATUALIZACAO EM TEMPO REAL
// Atualiza dados a cada tick: precos, hora, P&L, ticks/min.
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
   //--- Contador de ticks/minuto ---
   datetime now = TimeCurrent();                                     // hora atual
   MqlDateTime dt;                                                   // estrutura
   TimeToStruct(now, dt);                                            // decompoe
   int currentMin = dt.min;                                          // minuto atual

   if(g_lastMinute == 0) g_lastMinute = currentMin;                 // inicializa

   if(currentMin != g_lastMinute)                                    // mudou de minuto?
   {
      g_ticksPerMin = g_tickCount;                                   // salva contagem anterior
      g_tickCount = 0;                                               // reseta
      g_lastMinute = currentMin;                                     // atualiza referencia

      //--- Verifica se ha novos deals (cache) ---
      MqlDateTime dtDay;
      TimeToStruct(TimeCurrent(), dtDay);
      dtDay.hour = 0; dtDay.min = 0; dtDay.sec = 0;
      datetime dayStart = StructToTime(dtDay);
      HistorySelect(dayStart, TimeCurrent());
      int curDealCount = HistoryDealsTotal();

      if(curDealCount != g_lastDealCount)                            // novos deals detectados
      {
         g_lastDealCount = curDealCount;                             // atualiza cache
         UpdatePerformanceData();                                     // recalcula P&L
      }

      //--- Intelligence + Calendario: a cada 5 minutos ---
      if(currentMin % 5 == 0 && currentMin != g_intellMinute)
      {
         g_intellMinute = currentMin;                                // marca ultimo calculo
         UpdateIntelligenceData();                                    // analise 30 dias (pesado)
         UpdateCalendarData();                                        // refresh calendario
      }

      //--- Curva P&L: sempre atualiza ---
      UpdatePnLCurve();                                               // adiciona ponto

      //--- Atualiza dados dos sensores (leitura de GVs, rapido) ---
      UpdateSensorsData();

      //--- Redesenha aba ativa (Dashboard, Mercado ou Config) ---
      if(g_activeTab == 0 || g_activeTab == 2 || g_activeTab == 4)
      {
         DrawActiveTab();
      }
   }
   g_tickCount++;                                                     // conta este tick

   //--- Re-detecta framework periodicamente ---
   if(!g_frameworkOk && g_tickCount % 100 == 1)
   {
      DetectFramework();
      if(g_frameworkOk) { DrawActiveTab(); ChartRedraw(0); }
   }

   //--- Se minimizado, nao atualiza UI ---
   if(g_minimized) return(rates_total);

   //--- Atualiza header (hora + risco + trades) ---
   UpdLabel("HdrTime", GetServerTimeFormatted());

   //--- Atualiza indicador de risco (inclui daily loss alert) ---
   color riskClr = CLR_ACCENT_GREEN;
   string riskTxt = "LOW RISK";
   if(g_dailyLossAlert)
   {
      riskClr = CLR_ACCENT_RED; riskTxt = "LOSS LIMIT!";            // alerta maximo
   }
   else if(g_maxDrawdown > 0)
   {
      double ddPctBal = (g_totalBalance > 0) ? g_curDrawdown / g_totalBalance * 100.0 : 0;
      if(ddPctBal > 5.0)       { riskClr = CLR_ACCENT_RED;    riskTxt = "HIGH RISK"; }
      else if(ddPctBal > 2.0)  { riskClr = CLR_ACCENT_YELLOW; riskTxt = "MED RISK"; }
   }
   UpdLabel("HdrRiskTxt", riskTxt);
   UpdColor("HdrRiskTxt", riskClr);
   string riskDot = N("HdrRiskDot");
   if(ObjectFind(0, riskDot) >= 0) ObjectSetInteger(0, riskDot, OBJPROP_BGCOLOR, riskClr);

   //--- Quality Score no header ---
   string qsTxt = "QS:" + IntegerToString((int)g_qualityScore);
   color qsClr = CLR_ACCENT_GREEN;
   if(g_qualityScore < 40) qsClr = CLR_ACCENT_RED;
   else if(g_qualityScore < 65) qsClr = CLR_ACCENT_YELLOW;
   UpdLabel("HdrQS", qsTxt);
   UpdColor("HdrQS", qsClr);

   //--- Atualiza contador de trades ao vivo ---
   int liveCount = 0;
   for(int lp = PositionsTotal() - 1; lp >= 0; lp--)
      if(PositionGetSymbol(lp) == g_symbol) liveCount++;
   UpdLabel("HdrLive", "TRADES: " + IntegerToString(liveCount));
   UpdColor("HdrLive", (liveCount > 0) ? CLR_ACCENT_CYAN : CLR_TEXT_DIM);

   //--- Atualiza aba Dashboard se ativa ---
   if(g_activeTab == 0)
   {
      int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
      double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
      double tSize = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
      int sprd = (tSize > 0) ? (int)MathRound((ask - bid) / tSize) : 0;

      //--- Atualiza precos ---
      UpdLabel("C_BidVal", FmtPrice(bid, digits));
      UpdLabel("C_AskVal", FmtPrice(ask, digits));
      UpdLabel("C_SpreadTxt", IntegerToString(sprd));

      //--- Atualiza sessao (ativas + proxima, horario Japao) ---
      UpdLabel("C_MktSession", BuildSessionText());

      //--- Atualiza day high/low ---
      double dayHigh = iHigh(g_symbol, PERIOD_D1, 0);
      double dayLow  = iLow(g_symbol, PERIOD_D1, 0);
      UpdLabel("C_MktHigh", "High: " + FmtPrice(dayHigh, digits));
      UpdLabel("C_MktLow", "Low: " + FmtPrice(dayLow, digits));

      //--- Atualiza velocidade ---
      string speedTxt = "LENTO"; color speedClr = CLR_BAR_GREEN;
      if(g_ticksPerMin > 60)      { speedTxt = "RAPIDO"; speedClr = CLR_BAR_RED; }
      else if(g_ticksPerMin > 25) { speedTxt = "MEDIO";  speedClr = CLR_BAR_YELLOW; }
      UpdLabel("C_VolSpeed", "Ticks/min: " + IntegerToString(g_ticksPerMin) + " (" + speedTxt + ")");
      UpdColor("C_VolSpeed", speedClr);

      //--- Atualiza P&L ---
      double totalPnL = g_eaProfit + g_eaLoss + g_manualProfit + g_manualLoss;
      color pnlClr = (totalPnL >= 0) ? CLR_ACCENT_GREEN : CLR_ACCENT_RED;
      UpdLabel("C_PnlValue", FmtMoney(totalPnL));
      UpdColor("C_PnlValue", pnlClr);

      ChartRedraw(0);
   }

   return(rates_total);
}


//=====================================================================
// [26] ONCHARTEVENT — CLIQUES E RESIZE
// Processa cliques nas abas, botoes de config, strategy toggles.
//=====================================================================

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   //--- Clique em objeto ---
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      //--- Botao minimizar ---
      if(sparam == N("BtnMin"))
      {
         ToggleMinimize();
         return;
      }

      //--- Clique nas abas ---
      for(int i = 0; i < TAB_COUNT; i++)
      {
         if(sparam == N("Tab" + IntegerToString(i)))
         {
            SwitchTab(i);
            return;
         }
      }

      //--- Botoes de fonte ---
      if(sparam == N("C_BtnFontUp"))
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChangeFontSize(+1);
         return;
      }
      if(sparam == N("C_BtnFontDown"))
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChangeFontSize(-1);
         return;
      }

      //--- Botoes de fuso ---
      if(sparam == N("C_BtnTZUp"))
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChangeTimezone(+1);
         return;
      }
      if(sparam == N("C_BtnTZDown"))
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChangeTimezone(-1);
         return;
      }

      //--- Botoes de comissao ---
      if(sparam == N("C_BtnCommUp"))
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChangeCommission(+0.50);
         return;
      }
      if(sparam == N("C_BtnCommDown"))
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         ChangeCommission(-0.50);
         return;
      }

      //--- Botoes de filtro de relatorios ---
      for(int i = 0; i < 4; i++)
      {
         if(sparam == N("C_Filter" + IntegerToString(i)))
         {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_reportFilter = i;
            DrawActiveTab();
            ChartRedraw(0);
            return;
         }
      }

      //--- Toggles de estrategias ---
      for(int i = 0; i < g_stratCount; i++)
      {
         if(sparam == N("C_StratToggle" + IntegerToString(i)))
         {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_stratActive[i] = !g_stratActive[i];                    // toggle
            GlobalVariableSet("MKSD_Strat_" + g_stratNames[i],
               g_stratActive[i] ? 1.0 : 0.0);                      // persiste via GV
            DrawActiveTab();                                          // redesenha
            ChartRedraw(0);
            return;
         }
      }

      //--- Toggles de sensores ---
      for(int sti = 0; sti < SENSOR_COUNT; sti++)
      {
         if(sparam == N("C_SnsToggle" + IntegerToString(sti)))
         {
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            g_sensors[sti].enabled = !g_sensors[sti].enabled;
            SaveSensorToggle(sti);
            DrawActiveTab();                                          // redesenha (Config + Dashboard)
            ChartRedraw(0);
            return;
         }
      }

      //--- Botao exportar (placeholder) ---
      if(sparam == N("C_BtnExport"))
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         PrintFormat("[26] Exportacao solicitada — filtro: %d (feature futura)", g_reportFilter);
         return;
      }
   }

   //--- Resize do grafico ---
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      int newW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int newH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(newW != g_chartW || newH != g_chartH)
      {
         DeleteAll();
         BuildPanel();
         ChartRedraw(0);
      }
   }
}


//=====================================================================
// [27] ONDEINIT — LIMPEZA
// Libera handles e remove objetos ao descarregar.
//=====================================================================

void OnDeinit(const int reason)
{
   //--- Libera handles de indicadores ---
   if(g_hATR_D1  != INVALID_HANDLE) IndicatorRelease(g_hATR_D1);    // ATR D1

   DeleteAll();                                                       // remove todos os objetos
   ChartRedraw(0);                                                   // aplica limpeza

   PrintFormat("[27] MKS Dashboard Pro removido — motivo: %d", reason);  // log de saida
}