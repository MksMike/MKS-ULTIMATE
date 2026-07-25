//+------------------------------------------------------------------+
//| @file           : CMksVolatilitySensor.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Sensors / Volatility
//| @responsibility : Sensor de VOLATILIDADE renko-native (1º do catálogo de
//|                   sensores de decisão — E8). Mede a vol pela TAXA de
//|                   formação de brick (o renko descarta o range mas guarda o
//|                   TEMPO), no stream determinístico — NÃO lê o CS nem M1/M5.
//|                   Reativo: EWMA rápida do dt entre bricks + o GAP atual sem
//|                   brick (atualizado por tick → pega a calmaria na hora).
//|                   Adaptativo (forward-honest): o score é percentil relativo
//|                   a uma referência TRAILING (nunca full-sample/look-ahead).
//|                   Level contínuo (0-10) reativo + bucket discreto com
//|                   HISTERESE (não pisca). Metadado absoluto: bricks/hora.
//|
//| CONTRATO (o "cumpre seu papel" — falsificável):
//|   C1 Monotonicidade: períodos rotulados ALTA têm rate realizado > MÉDIA >
//|      BAIXA (mede o que diz medir).
//|   C2 Reatividade à calmaria: após bricks rápidos, um gap longo sem brick
//|      DERRUBA o Score antes do próximo brick (via o gap, por tick).
//|   C3 Clustering: o bucket PERSISTE mais que o acaso (histerese) — é regime,
//|      não ruído.
//|   C4 Adaptativo: em regime globalmente mais calmo, "ALTA" ainda ocorre (a
//|      alta DAQUELE regime) — não satura em BAIXA (nem em ULTRA no violento).
//|   C5 Estável a parâmetro: variar halfLife/ref um pouco não vira o mundo.
//|   C6 Determinístico: mesmo stream → mesma saída (sem look-ahead; ref trailing).
//| @depends_on     : Nenhuma (autocontido; opera sobre timestamps de brick + tick)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Sensors/Volatility/CMksVolatilitySensor.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_SENSORS_VOLATILITY_CMKSVOLATILITYSENSOR_MQH
#define MKS_ULTIMATE_CORE_SENSORS_VOLATILITY_CMKSVOLATILITYSENSOR_MQH

enum ENUM_MKS_VOL_LEVEL
{
   MKS_VOL_LOW     = 0,   // baixa
   MKS_VOL_MEDIUM  = 1,   // média
   MKS_VOL_HIGH    = 2,   // alta
   MKS_VOL_EXTREME = 3,   // extrema
   MKS_VOL_ULTRA   = 4    // ultra (outlier — gate de risco)
};

string MksVolLevelToString(ENUM_MKS_VOL_LEVEL l)
{
   switch(l)
   {
      case MKS_VOL_LOW:     return "LOW";
      case MKS_VOL_MEDIUM:  return "MEDIUM";
      case MKS_VOL_HIGH:    return "HIGH";
      case MKS_VOL_EXTREME: return "EXTREME";
      case MKS_VOL_ULTRA:   return "ULTRA";
   }
   return "?";
}

class CMksVolatilitySensor
{
private:
   //--- config ---
   double m_alpha;        // peso EWMA (derivado da meia-vida)
   int    m_refWindow;    // tamanho da referência trailing (bricks)
   double m_hyst;         // margem de histerese na escala 0-10
   double m_maxGapMs;     // dt acima disto = DESCONTINUIDADE (pausa/fim-de-semana):
                          // NÃO entra na EWMA nem na referência (não envenena a vol)

   //--- estado ---
   double m_ewmaDt;       // EWMA do dt entre bricks (ms)
   bool   m_haveEwma;
   long   m_lastBrickMsc;
   bool   m_haveLast;

   double m_ref[];        // ring buffer dos dts (referência)
   int    m_refCount;
   int    m_refHead;
   double m_sorted[];     // cópia ordenada (percentil)

   double m_score;        // último Level contínuo (0-10)
   ENUM_MKS_VOL_LEVEL m_level;
   long   m_lastUpdateMsc;

   //--- percentil com MIDRANK p/ empates: pct = (qtde<dt + qtde<=dt)/(2n).
   //    Sem midrank, um bloco de dts idênticos recebia o percentil do TOPO do
   //    bloco (viés p/ baixo no score) e uma série constante colapsava em
   //    LOW-ou-ULTRA por 1 ulp; com midrank, constante → pct 0.5 → MEDIUM.
   double PctRank(double dt) const
   {
      int n = ArraySize(m_sorted);
      if(n == 0) return 0.5;
      int lo = 0, hi = n;                 // lower: 1º índice com sorted >= dt
      while(lo < hi) { int mid = (lo + hi) / 2; if(m_sorted[mid] < dt) lo = mid + 1; else hi = mid; }
      int lower = lo;
      lo = lower; hi = n;                 // upper: 1º índice com sorted > dt
      while(lo < hi) { int mid = (lo + hi) / 2; if(m_sorted[mid] <= dt) lo = mid + 1; else hi = mid; }
      int upper = lo;
      return (double)(lower + upper) / (2.0 * (double)n);
   }

   // dt pequeno = brick rápido = alta vol → score alto. score = (1-pct)*10.
   double ScoreFromDt(double dt) const { return (1.0 - PctRank(dt)) * 10.0; }

   // Histerese: só troca de nível quando o score cruza a borda + margem.
   ENUM_MKS_VOL_LEVEL ApplyHysteresis(ENUM_MKS_VOL_LEVEL cur, double score) const
   {
      double edge[4]; edge[0]=3.0; edge[1]=5.0; edge[2]=7.0; edge[3]=9.0; // borda SUP de LOW,MED,HIGH,EXTREME
      int L = (int)cur;
      while(L < 4)   // sobe: cruza a borda + margem
      {
         double up = edge[L] + m_hyst;
         // ULTRA capado em 9.5: score = 10·(1−pctrank) chega a ~9.99, nunca 10,
         // e com hyst>=1 a borda 9+hyst>=10 tornaria ULTRA (gate de risco)
         // INALCANÇÁVEL. Cap garante que uma rajada no top ~5% dispara ULTRA.
         if(L == 3 && up > 9.5) up = 9.5;
         if(score >= up) L++; else break;
      }
      while(L > 0 && score < edge[L - 1] - m_hyst) L--;   // desce
      return (ENUM_MKS_VOL_LEVEL)L;
   }

public:
   CMksVolatilitySensor(double halfLifeBricks = 10.0, int refWindow = 500,
                        double hysteresis = 1.0, double maxGapMs = 14400000.0) // 4h
   {
      m_alpha = (halfLifeBricks > 0.0) ? (1.0 - MathPow(2.0, -1.0 / halfLifeBricks)) : 1.0;
      m_refWindow = (refWindow >= 10) ? refWindow : 10;
      m_hyst = (hysteresis >= 0.0) ? hysteresis : 0.0;
      m_maxGapMs = (maxGapMs > 0.0) ? maxGapMs : 14400000.0;
      Reset();
   }

   void Reset()
   {
      m_ewmaDt = 0.0; m_haveEwma = false;
      m_lastBrickMsc = 0; m_haveLast = false;
      ArrayResize(m_ref, m_refWindow);
      m_refCount = 0; m_refHead = 0;
      ArrayResize(m_sorted, 0);
      m_score = 5.0; m_level = MKS_VOL_MEDIUM; m_lastUpdateMsc = 0;
   }

   // Evento: um brick fechou em brickMsc. Atualiza a EWMA e a referência.
   void OnBrick(long brickMsc)
   {
      if(m_haveLast)
      {
         double dt = (double)(brickMsc - m_lastBrickMsc);
         if(dt < 0.0) dt = 0.0;   // defesa: tempo não-monotônico
         // dt > maxGap = descontinuidade (pausa/fim-de-semana). NÃO entra na
         // EWMA nem na referência — senão o gap gigante envenena a vol por
         // ~3×meia-vida (Monday-open lido como calmo sem ser). O gap ainda é
         // visto por OnTick (calmaria observável), só não polui a distribuição.
         if(dt <= m_maxGapMs)
         {
            m_ewmaDt = m_haveEwma ? (m_alpha * dt + (1.0 - m_alpha) * m_ewmaDt) : dt;
            m_haveEwma = true;

            if(m_refCount < m_refWindow) { m_ref[m_refCount] = dt; m_refCount++; }
            else { m_ref[m_refHead] = dt; m_refHead = (m_refHead + 1) % m_refWindow; }
            ArrayResize(m_sorted, m_refCount);
            ArrayCopy(m_sorted, m_ref, 0, 0, m_refCount);
            ArraySort(m_sorted);
         }
      }
      m_lastBrickMsc = brickMsc;
      m_haveLast = true;
      OnTick(brickMsc);   // reavalia no instante do brick (gap=0)
   }

   // Reavalia no tempo atual (chamar por tick). Reatividade à calmaria: se o
   // gap sem brick > EWMA, a vol está caindo AGORA (effectiveDt = gap).
   void OnTick(long nowMsc)
   {
      m_lastUpdateMsc = nowMsc;
      if(!m_haveEwma || m_refCount < 2) { m_score = 5.0; m_level = MKS_VOL_MEDIUM; return; }
      double gap = (double)(nowMsc - m_lastBrickMsc);
      if(gap < 0.0) gap = 0.0;
      double effDt = (gap > m_ewmaDt) ? gap : m_ewmaDt;   // só ALARGA (calmaria), nunca antecipa spike
      m_score = ScoreFromDt(effDt);
      m_level = ApplyHysteresis(m_level, m_score);
   }

   //--- saídas ---
   double             Score() const { return m_score; }              // 0-10 reativo (Level contínuo)
   ENUM_MKS_VOL_LEVEL Level() const { return m_level; }              // bucket com histerese
   double             Confidence() const { return MathMin(1.0, (double)m_refCount / 50.0); }
   long               LastUpdateMsc() const { return m_lastUpdateMsc; }
   double             EwmaDtMsc() const { return m_ewmaDt; }         // metadado

   // Metadado ABSOLUTO: bricks/hora (magnitude real, p/ risco). Usa a EWMA
   // (não o gap) — a taxa "típica" recente, não o instante.
   double RawBricksPerHour() const
   {
      if(!m_haveEwma || m_ewmaDt <= 0.0) return 0.0;
      return 3600000.0 / m_ewmaDt;
   }
};

#endif // MKS_ULTIMATE_CORE_SENSORS_VOLATILITY_CMKSVOLATILITYSENSOR_MQH
