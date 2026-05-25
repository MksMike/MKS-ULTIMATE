//+------------------------------------------------------------------+
//| @file           : PreloadHistory.mq5
//| @project        : MKS-ULTIMATE
//| @module         : Scripts / MKS-ULTIMATE
//| @responsibility : Força download de N dias de ticks do símbolo
//|                   alvo para o cache local do terminal. Garante que
//|                   o Producer (InpHistoricalFillDays=30) e o
//|                   TickRecorder tenham dados disponíveis quando
//|                   forem anexados. Reporta cobertura dia-a-dia +
//|                   detecta gaps suspeitos. Utilitário operacional
//|                   pré-pipeline ADR-024.
//| @depends_on     : MqlTick, CopyTicksRange, SymbolSelect
//| @install_path   : MQL5/Scripts/MKS-ULTIMATE/PreloadHistory.mq5
//+------------------------------------------------------------------+
#property script_show_inputs
#property copyright "MKS-ULTIMATE"

input string InpSymbol             = "XAUUSDm"; // Símbolo a preparar
input int    InpDays               = 30;        // Dias para trás a baixar
input int    InpMaxAttemptsPerDay  = 20;        // Retry por dia se cache vier vazio
input int    InpAttemptDelayMs     = 500;       // Delay entre retries
input bool   InpVerbose            = false;     // Imprime cada tentativa

//+------------------------------------------------------------------+
//| Formata datetime UTC como "YYYY-MM-DD HH:MM:SS".                  |
//+------------------------------------------------------------------+
string FormatUtc(datetime t)
{
   return TimeToString(t, TIME_DATE | TIME_SECONDS);
}

//+------------------------------------------------------------------+
//| Constrói datetime UTC do início de um dia (00:00:00 UTC).         |
//| daysAgo=0 = hoje. daysAgo=1 = ontem. Etc.                          |
//+------------------------------------------------------------------+
datetime DayStartUtc(int daysAgo)
{
   datetime now = TimeGMT();
   long s = (long)now;
   long dayStart = (s / 86400) * 86400; // alinha para 00:00 UTC
   return (datetime)(dayStart - (long)daysAgo * 86400);
}

//+------------------------------------------------------------------+
//| Tenta CopyTicksRange para uma janela [fromMsc, toMsc] com retries.|
//| Retorna o número de ticks finalmente obtidos (0 = falha mesmo     |
//| após retries).                                                    |
//+------------------------------------------------------------------+
int LoadWindow(const string &symbol, long fromMsc, long toMsc, MqlTick &outTicks[])
{
   for(int attempt = 0; attempt < InpMaxAttemptsPerDay; attempt++)
   {
      int n = CopyTicksRange(symbol, outTicks, COPY_TICKS_ALL, fromMsc, toMsc);
      if(n > 0) return n;
      int err = GetLastError();
      if(InpVerbose)
         PrintFormat("  [attempt %d/%d] CopyTicksRange retornou %d (lastErr=%d) — aguardando %dms",
                     attempt + 1, InpMaxAttemptsPerDay, n, err, InpAttemptDelayMs);
      ResetLastError();
      Sleep(InpAttemptDelayMs);
   }
   return 0;
}

//+------------------------------------------------------------------+
//| OnStart                                                           |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("");
   Print("=== PreloadHistory ===");
   PrintFormat("symbol = %s", InpSymbol);
   PrintFormat("days   = %d", InpDays);
   PrintFormat("maxAttemptsPerDay = %d (delay=%dms entre retries)",
               InpMaxAttemptsPerDay, InpAttemptDelayMs);

   if(StringLen(InpSymbol) == 0)
   {
      Print("ERRO: InpSymbol vazio.");
      return;
   }

   if(!SymbolSelect(InpSymbol, true))
   {
      PrintFormat("ERRO: SymbolSelect(%s) falhou (err=%d). Adicione o símbolo "
                  "ao Market Watch manualmente antes de rodar este script.",
                  InpSymbol, GetLastError());
      return;
   }

   if(InpDays <= 0)
   {
      Print("ERRO: InpDays deve ser > 0.");
      return;
   }

   uint startMs = GetTickCount();
   long totalTicks = 0;
   int  daysWithData = 0;
   int  daysEmpty    = 0;
   long minTicksDay  = LONG_MAX;
   long maxTicksDay  = 0;
   string firstDayStr = "";
   string lastDayStr  = "";

   Print("");
   Print("--- Cobertura dia-a-dia (UTC) ---");

   // Itera dos mais antigos para os mais recentes (daysAgo decrescente).
   // Range fechado-aberto: [start_of_day, start_of_next_day).
   for(int d = InpDays - 1; d >= 0; d--)
   {
      datetime dayStart = DayStartUtc(d);
      datetime dayEnd   = (datetime)((long)dayStart + 86400);
      long fromMsc      = (long)dayStart * 1000;
      long toMsc        = (long)dayEnd * 1000 - 1; // inclusivo último ms do dia

      MqlTick ticks[];
      int n = LoadWindow(InpSymbol, fromMsc, toMsc, ticks);

      string dayLabel = TimeToString(dayStart, TIME_DATE);
      MqlDateTime dt;
      TimeToStruct(dayStart, dt);
      bool isWeekend = (dt.day_of_week == 0 || dt.day_of_week == 6);

      string flag = "";
      if(n == 0 && !isWeekend) flag = "  ⚠ DIA VAZIO (dia útil, esperado ter ticks)";
      else if(n == 0 && isWeekend) flag = "  (weekend — esperado vazio)";

      PrintFormat("  %s : %8d ticks%s", dayLabel, n, flag);

      if(n > 0)
      {
         daysWithData++;
         totalTicks += n;
         if((long)n < minTicksDay) minTicksDay = (long)n;
         if((long)n > maxTicksDay) maxTicksDay = (long)n;
         if(firstDayStr == "") firstDayStr = dayLabel;
         lastDayStr = dayLabel;
      }
      else
      {
         daysEmpty++;
      }
   }

   uint elapsedMs = GetTickCount() - startMs;

   Print("");
   Print("--- Resumo ---");
   PrintFormat("janela analisada    : %d dias (de hoje-%d a hoje)",
               InpDays, InpDays - 1);
   PrintFormat("dias com dados      : %d", daysWithData);
   PrintFormat("dias vazios         : %d (inclui fins-de-semana)", daysEmpty);
   PrintFormat("primeiro dia c/ dados: %s", firstDayStr);
   PrintFormat("último dia c/ dados  : %s", lastDayStr);
   PrintFormat("total de ticks      : %I64d", totalTicks);
   if(daysWithData > 0)
   {
      PrintFormat("média/dia           : %I64d ticks",
                  totalTicks / (long)daysWithData);
      PrintFormat("min/max por dia     : %I64d / %I64d", minTicksDay, maxTicksDay);
   }
   PrintFormat("tempo de execução   : %.1fs", elapsedMs / 1000.0);

   Print("");
   if(daysWithData == 0)
   {
      Print("⚠ NENHUM DIA TEM DADOS. Cache local vazio ou broker sem histórico de "
            "ticks. Tente: (1) abrir um chart M1 do símbolo e deixar carregar; "
            "(2) Tools → History Center → forçar download; (3) verificar se "
            "a corretora fornece tick history para este símbolo.");
   }
   else
   {
      Print("✓ Cache local pronto. Producer.mq5 (InpHistoricalFillDays) e "
            "TickRecorder.mq5 devem encontrar ticks suficientes para o teste.");
   }
}
//+------------------------------------------------------------------+