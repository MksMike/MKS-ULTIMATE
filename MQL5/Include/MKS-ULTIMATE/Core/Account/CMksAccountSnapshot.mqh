//+------------------------------------------------------------------+
//| @file           : CMksAccountSnapshot.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Account
//| @responsibility : Snapshot temporal da conta — rastreia balance de
//|                   inicio-do-dia-UTC e peak-equity-desde-criacao para
//|                   alimentar a camada "Por Conta" do CMksRiskManager
//|                   (slice 6.3). Stateful: estrategia chama Update()
//|                   a cada tick; o snapshot detecta rollover de dia
//|                   (via IClock UTC) e atualiza peak monotonicamente.
//| @depends_on     : Core/Interfaces/IAccount.mqh,
//|                   Core/Interfaces/IClock.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Account/CMksAccountSnapshot.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_ACCOUNT_CMKSACCOUNTSNAPSHOT_MQH
#define MKS_ULTIMATE_CORE_ACCOUNT_CMKSACCOUNTSNAPSHOT_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IAccount.mqh>
#include <MKS-ULTIMATE/Core/Interfaces/IClock.mqh>

#define MKS_SNAPSHOT_MSC_PER_DAY 86400000L

// Padrao de uso:
//   CMksAccountSnapshot snap(account, clock);
//   snap.Init();                       // captura baseline (1a vez)
//   ... a cada tick:
//   snap.Update();                     // rollover-aware, peak monotonico
//   risk.CheckOrder(req, err);         // consulta o snapshot via Risk
//
// Por que a camada Por Conta precisa de stateful: IAccount expoe estado
// pontual (Balance/Equity now). "Daily loss" = (equity - balanceStartOfDay),
// "drawdown" = (peakEquity - equity). Esses sao numeros temporais que
// nao saem do IAccount estatico — exigem rastrear o tempo do baseline
// e o peak observado. O snapshot encapsula esse estado, deixando
// IAccount limpo e Risk Manager declarativo (só compara).
//
// Rollover de dia: UTC. Mesma fronteira do .mkstick (ADR-024 §3) e
// do .mksbk (ADR-014). Detectado por floor(nowMsc / MSC_PER_DAY)
// !=  floor(dayStartMsc / MSC_PER_DAY). Na virada, m_dayStartBalance
// passa a ser o balance corrente.
//
// Init opcional: Update() detecta primeira chamada (m_initialized=false)
// e auto-inicializa. Padroniza para evitar bug de "esqueci de chamar
// Init" — frequente no V5 antigo.
class CMksAccountSnapshot
{
private:
   IAccount *m_account;
   IClock   *m_clock;

   bool   m_initialized;
   long   m_dayStartMsc;
   double m_dayStartBalance;
   double m_peakEquity;

   static long DayOf(long msc)
   {
      // floor com correcao para negativos (defensivo — clocks
      // normais nunca chegam a < 1970).
      long d = msc / MKS_SNAPSHOT_MSC_PER_DAY;
      if(msc < 0 && msc % MKS_SNAPSHOT_MSC_PER_DAY != 0) d--;
      return d;
   }

public:
   CMksAccountSnapshot(IAccount *account, IClock *clock)
   {
      m_account = account;
      m_clock   = clock;
      m_initialized     = false;
      m_dayStartMsc     = 0;
      m_dayStartBalance = 0.0;
      m_peakEquity      = 0.0;
   }

   // Inicializa baseline com o estado atual. Idempotente; chamadas
   // subsequentes nao alteram o baseline (a nao ser por rollover via
   // Update). Util quando a estrategia quer baseline determinado em
   // OnInit em vez de no primeiro tick.
   void Init()
   {
      if(m_initialized) return;
      m_dayStartMsc     = m_clock.NowMsc();
      m_dayStartBalance = m_account.Balance();
      m_peakEquity      = m_account.Equity();
      m_initialized     = true;
   }

   // Chamada a cada tick. Detecta rollover de dia UTC, atualiza peak.
   void Update()
   {
      if(!m_initialized) { Init(); return; }

      long now = m_clock.NowMsc();
      if(DayOf(now) != DayOf(m_dayStartMsc))
      {
         // Novo dia UTC — reset do baseline diario.
         m_dayStartMsc     = now;
         m_dayStartBalance = m_account.Balance();
      }

      double eq = m_account.Equity();
      if(eq > m_peakEquity) m_peakEquity = eq;
   }

   //--- Getters ------------------------------------------------------+

   bool   Initialized()        const { return m_initialized; }
   long   DayStartMsc()        const { return m_dayStartMsc; }
   double DayStartBalance()    const { return m_dayStartBalance; }
   double PeakEquity()         const { return m_peakEquity; }

   // Conveniência — passagem direta do IAccount. RiskManager Por Conta
   // consulta via aqui para evitar receber IAccount como dependência
   // separada (o snapshot ja agrega o estado relevante).
   double Equity()  const { return m_account.Equity(); }
   double Balance() const { return m_account.Balance(); }

   // P&L do dia em moeda da conta = EQUITY corrente (FLUTUANTE — inclui o
   // não-realizado das posições abertas) − BALANCE de início do dia UTC.
   // Escolha DELIBERADA (E5.4/ADR-036): usar equity flutuante (não só o
   // balance realizado) faz a camada de perda diária reagir a drawdown
   // intraday NÃO-realizado — mais protetor, alinhado ao antídoto do V5
   // (`[daypnl-uses-equity]`). Positivo = lucro, negativo = perda.
   double DayPnL() const
   {
      if(!m_initialized) return 0.0;
      return m_account.Equity() - m_dayStartBalance;
   }

   // P&L do dia em %. Positivo = lucro, negativo = perda. 0 se balance
   // de inicio do dia for <= 0 (evita divisao por zero; conta sem saldo
   // nao tem semantica de "%").
   double DayPnLPct() const
   {
      if(!m_initialized || m_dayStartBalance <= 0.0) return 0.0;
      return 100.0 * DayPnL() / m_dayStartBalance;
   }

   // Drawdown desde peak. Sempre >= 0 — quando equity > peak, retorna 0.
   double Drawdown() const
   {
      if(!m_initialized) return 0.0;
      double dd = m_peakEquity - m_account.Equity();
      return (dd > 0.0) ? dd : 0.0;
   }

   double DrawdownPct() const
   {
      if(!m_initialized || m_peakEquity <= 0.0) return 0.0;
      return 100.0 * Drawdown() / m_peakEquity;
   }
};

#endif // MKS_ULTIMATE_CORE_ACCOUNT_CMKSACCOUNTSNAPSHOT_MQH
