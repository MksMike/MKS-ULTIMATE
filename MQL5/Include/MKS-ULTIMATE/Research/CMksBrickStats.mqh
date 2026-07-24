//+------------------------------------------------------------------+
//| @file           : CMksBrickStats.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Research
//| @responsibility : Medições estatísticas PURAS sobre uma série de
//|                   bricks fechados, para DESCOBERTA DE EDGE (research-
//|                   only, NÃO toca o caminho de trading/paridade). Cada
//|                   função condiciona a transição brick[i-1]→brick[i]
//|                   ("continua" = mesma direção) a um contexto do brick
//|                   i-1: run-length, hora do dia, volatilidade, regime.
//|                   Desvio de P(continua) vs 0.5 (random walk) = candidato
//|                   a edge. Puras → testáveis sem MT5 (um bug aqui = edge
//|                   falso, o modo de falha que o projeto existe pra matar).
//| @depends_on     : Core/Sensors/Regime/CMksReversalRegime.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Research/CMksBrickStats.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_RESEARCH_CMKSBRICKSTATS_MQH
#define MKS_ULTIMATE_RESEARCH_CMKSBRICKSTATS_MQH

#include <MKS-ULTIMATE/Core/Sensors/Regime/CMksReversalRegime.mqh>

// Probabilidade de continuação a partir de contadores. Vazio → 0.5 (neutro,
// sem evidência), para não simular edge onde não há amostra.
double MksStatProb(int cont, int rev)
{
   int tot = cont + rev;
   return (tot > 0) ? (double)cont / (double)tot : 0.5;
}

// z-score da proporção vs 0.5 (H0: random walk). z = 2·(p−0.5)·sqrt(N).
// |z|>=2 ≈ 5% de significância; >=3 ≈ forte. Serve de gate contra "sinal"
// que é só amostra pequena (o marcador por |p−0.5| sozinho mente). 0 sem N.
double MksStatZ(int cont, int rev)
{
   int tot = cont + rev;
   if(tot <= 0) return 0.0;
   double p = (double)cont / (double)tot;
   return 2.0 * (p - 0.5) * MathSqrt((double)tot);
}

// Hora do dia [0..23] do timestamp (msc), aplicando offset servidor→alvo.
// Ex.: Exness server ~UTC+2/+3 — passar offset negativo p/ ler em UTC.
int MksStatHourOf(long timeMsc, int offsetHours)
{
   long sec = timeMsc / 1000;
   int  h   = (int)(((sec / 3600) + offsetHours) % 24);
   if(h < 0) h += 24;
   return h;
}

// A. RUN-LENGTH → CONTINUAÇÃO. Após um run de EXATAMENTE k bricks da mesma
//    cor, o (k+1)-ésimo continua (mesma cor) ou reverte? cont[k]/rev[k] para
//    k=1..maxK (runs > maxK dobrados em maxK). Índice 0 não usado.
//    P(continua|run==k) = cont[k]/(cont[k]+rev[k]); >0.5 = momentum, <0.5 =
//    reversão. É a pergunta fundamental do Renko.
void MksStatRunLength(const int &dir[], int n, int maxK, int &cont[], int &rev[])
{
   ArrayResize(cont, maxK + 1);
   ArrayResize(rev,  maxK + 1);
   ArrayInitialize(cont, 0);
   ArrayInitialize(rev,  0);
   if(n < 2 || maxK < 1) return;

   int run = 1; // comprimento do run terminando no índice 0
   for(int i = 1; i < n; i++)
   {
      int k = (run < maxK) ? run : maxK;
      if(dir[i] == dir[i - 1]) { cont[k]++; run++;    }
      else                     { rev[k]++;  run = 1;  }
   }
}

// D. HORA DO DIA → CONTINUAÇÃO. Condiciona a transição à hora do brick i-1.
//    Revela padrão intraday (sessões Ásia/Londres/NY no XAU). 24 buckets.
void MksStatHourOfDay(const int &dir[], const long &t[], int n,
                      int offsetHours, int &cont[], int &rev[])
{
   ArrayResize(cont, 24);
   ArrayResize(rev,  24);
   ArrayInitialize(cont, 0);
   ArrayInitialize(rev,  0);
   for(int i = 1; i < n; i++)
   {
      int h = MksStatHourOf(t[i - 1], offsetHours);
      if(dir[i] == dir[i - 1]) cont[h]++;
      else                     rev[h]++;
   }
}

// C. VOLATILIDADE (terciles) → CONTINUAÇÃO. Proxy de vol = velocidade de
//    formação do brick (dt entre closes; dt pequeno = alta vol). Bucket 0 =
//    baixa vol (lento), 2 = alta vol (rápido). loThr/hiThr = 33/66 pct de dt.
//    Responde: o mercado tende ou reverte quando os bricks formam rápido?
void MksStatVolatilityTerciles(const int &dir[], const long &t[], int n,
                               int &cont[], int &rev[], long &loThr, long &hiThr)
{
   ArrayResize(cont, 3);
   ArrayResize(rev,  3);
   ArrayInitialize(cont, 0);
   ArrayInitialize(rev,  0);
   loThr = 0; hiThr = 0;
   if(n < 4) return;

   long dts[];
   ArrayResize(dts, n - 1);
   for(int i = 1; i < n; i++) dts[i - 1] = t[i] - t[i - 1];

   long sorted[];
   ArrayCopy(sorted, dts);
   ArraySort(sorted);
   int m = n - 1;
   loThr = sorted[m / 3];         // 33º percentil (dt pequeno)
   hiThr = sorted[(2 * m) / 3];   // 66º percentil

   // Vol do brick i-1 = dt que o formou (t[i-1]-t[i-2]); precisa i>=2.
   for(int i = 2; i < n; i++)
   {
      long v = t[i - 1] - t[i - 2];
      int  b = (v <= loThr) ? 2 : ((v <= hiThr) ? 1 : 0); // dt pequeno → alta vol (2)
      if(dir[i] == dir[i - 1]) cont[b]++;
      else                     rev[b]++;
   }
}

// B. REGIME (lateral vs trend) → CONTINUAÇÃO. Reusa o CMksReversalRegime
//    validado (score de reversões numa janela). Bucket 0 = trend
//    (score<threshold), 1 = lateral (score>=threshold). Espera-se trend→
//    momentum e lateral→reversão (edge de regime-switching), se existir.
void MksStatRegime(const int &dir[], int n, int period, double threshold,
                   int &cont[], int &rev[])
{
   ArrayResize(cont, 2);
   ArrayResize(rev,  2);
   ArrayInitialize(cont, 0);
   ArrayInitialize(rev,  0);
   if(n < period + 1 || period < 2) return;

   // CMksReversalRegime lê open/close; sintetiza close>open sse bull.
   double op[]; double cl[];
   ArrayResize(op, n);
   ArrayResize(cl, n);
   for(int i = 0; i < n; i++) { op[i] = 0.0; cl[i] = (double)dir[i]; }

   CMksReversalRegime regime(period, threshold);
   for(int i = period - 1; i < n - 1; i++)   // score no brick i, transição i→i+1
   {
      double score = regime.Compute(op, cl, i);
      int    b     = (score >= threshold) ? 1 : 0;
      if(dir[i + 1] == dir[i]) cont[b]++;
      else                     rev[b]++;
   }
}

// Resultado do trade "ride-to-flip" (a OUTRA metade da equação do edge:
// não a taxa de acerto, mas o R-múltiplo — quanto ganha vs quanto perde).
struct MksPayoff
{
   int    trades;
   int    wins;
   double sumR;      // soma de R (unidades de brick, bruto)
   double sumR2;     // soma de R² (para desvio/t-stat)
   double sumWinR;
   double sumLossR;  // negativo
   double sumFwd;    // soma do forward-run (bricks até reverter)

   MksPayoff() { trades=0; wins=0; sumR=0; sumR2=0; sumWinR=0; sumLossR=0; sumFwd=0; }

   double EV()      const { return trades > 0 ? sumR / trades : 0.0; }             // EV bruto em bricks
   double WinRate() const { return trades > 0 ? (double)wins / trades : 0.0; }
   double AvgWin()  const { return wins > 0 ? sumWinR / wins : 0.0; }
   double AvgLoss() const { int l=trades-wins; return l > 0 ? sumLossR / l : 0.0; } // negativo
   double AvgFwd()  const { return trades > 0 ? sumFwd / trades : 0.0; }
   // EV líquido = bruto − custo (spread/slippage em bricks, por trade).
   double NetEV(double costBricks) const { return EV() - costBricks; }
   // t-stat do EV bruto vs 0 (significância de que o EV != 0). >2 ~ 5%.
   double T() const
   {
      if(trades < 2) return 0.0;
      double m = EV();
      double var = sumR2 / trades - m * m;
      if(var <= 0.0) return 0.0;
      double se = MathSqrt(var) / MathSqrt((double)trades);
      return (se > 0.0) ? m / se : 0.0;
   }
};

// Trade "ride-to-flip": entra no close do brick i (quando signal[i]), corre
// enquanto a direção continua, SAI no close do 1º brick j>i com dir[j]!=dir[i].
// R = dir[i]·(close[j]−close[i])/brickSize (bricks; +ganho, −perda). Trades
// NÃO-SOBREPOSTOS (o próximo entry parte do flip) → independentes, t-stat vale.
// Sinais no último run (sem flip até o fim) são descartados (trade incompleto).
void MksStatRideToFlip(const int &dir[], const double &closeArr[], int n,
                       const bool &signal[], double brickSize, MksPayoff &out)
{
   if(brickSize <= 0.0) return;
   int i = 0;
   while(i < n - 1)
   {
      if(!signal[i]) { i++; continue; }
      int j = i + 1;
      while(j < n && dir[j] == dir[i]) j++;
      if(j >= n) break;                         // sem flip até o fim: descarta
      double R = (double)dir[i] * (closeArr[j] - closeArr[i]) / brickSize;
      out.trades++;
      out.sumR   += R;
      out.sumR2  += R * R;
      out.sumFwd += (double)(j - i);
      if(R > 0.0) { out.wins++; out.sumWinR += R; }
      else        { out.sumLossR += R; }
      i = j;                                     // não-sobreposto
   }
}

// Trade de REVERSÃO (fade): entra CONTRA a direção do brick i (short se bull),
// caminha brick a brick e SAI quando o P&L (em bricks) atinge +target (win) ou
// −stop (loss) — R clampado ao nível (alvo/stop fixo). Sem nível até o fim →
// para. R = clamp(−dir[i]·(close[j]−close[i])/S). NÃO-SOBREPOSTO (próximo entry
// parte da saída) → independentes. É o ESPELHO do ride-to-flip: ganha as
// reversões pequenas e frequentes, perde as tendências raras e grandes.
void MksStatFade(const int &dir[], const double &closeArr[], int n,
                 const bool &signal[], double brickSize,
                 double target, double stop, MksPayoff &out)
{
   if(brickSize <= 0.0 || target <= 0.0 || stop <= 0.0) return;
   int i = 0;
   while(i < n - 1)
   {
      if(!signal[i]) { i++; continue; }
      int    side = -dir[i];              // fade: contra o brick
      int    j    = i + 1;
      double R    = 0.0;
      bool   hit  = false;
      while(j < n)
      {
         R = (double)side * (closeArr[j] - closeArr[i]) / brickSize;
         if(R >=  target) { R =  target; hit = true; break; }
         if(R <= -stop)   { R = -stop;   hit = true; break; }
         j++;
      }
      if(!hit) break;                      // não atingiu alvo/stop até o fim
      out.trades++;
      out.sumR  += R;
      out.sumR2 += R * R;
      out.sumFwd += (double)(j - i);
      if(R > 0.0) { out.wins++; out.sumWinR += R; }
      else        { out.sumLossR += R; }
      i = j;                               // não-sobreposto
   }
}

#endif // MKS_ULTIMATE_RESEARCH_CMKSBRICKSTATS_MQH
