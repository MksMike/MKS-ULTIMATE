//+------------------------------------------------------------------+
//| @file           : CMksDecisionJournal.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Trade
//| @responsibility : Journal TSV DETERMINÍSTICO das DECISÕES da
//|                   estratégia (SEND/CLOSE/AUTOCLOSE/REJECT). É o
//|                   oráculo de paridade da camada de decisão (E2): dois
//|                   runs do mesmo .mkstick + config pinada produzem o
//|                   MESMO journal byte-a-byte. Na disciplina do
//|                   CMksAuditLogSink (FILE_TXT|FILE_ANSI, \r\n, %.6f,
//|                   header comentado ignorado no diff, rodapé com
//|                   total). Campos = função pura de feed + config
//|                   pinada: zero wall-clock, zero RNG, positionId
//|                   NORMALIZADO (ordinal 1,2,3…), tempo do FEED.
//|                   Preço/custo/equity ficam FORA (vão para um ledger
//|                   informacional separado) para estabilizar o diff a
//|                   ajustes de custo que não mudem a SEQUÊNCIA.
//| @depends_on     : Core/Types/OrderRequest.mqh (ENUM_MKS_ORDER_SIDE),
//|                   Core/Types/ExecutionResult.mqh (ENUM_MKS_EXEC_STATUS)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Trade/CMksDecisionJournal.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_TRADE_CMKSDECISIONJOURNAL_MQH
#define MKS_ULTIMATE_CORE_TRADE_CMKSDECISIONJOURNAL_MQH

#include <MKS-ULTIMATE/Core/Types/OrderRequest.mqh>
#include <MKS-ULTIMATE/Core/Types/ExecutionResult.mqh>

// Bundle pinado gravado no header (linhas '#', IGNORADAS no diff, mas
// LIDAS e assertadas no replay — E2.3). O journal é função de
// (feed + CostModel + modelo-de-conta + config-da-estratégia): esse
// bundle inteiro é a unidade versionada do golden.
struct MksDecisionJournalHeader
{
   string symbol;
   string broker;
   long   account;
   int    digits;
   double point;
   double tickSize;
   // Âncora da escada (E2.3) — 1º anchor do builder.
   double seedMid;
   ulong  seedTickSeq;
   // CostModel pinado.
   double spreadPts;
   double slipPts;
   double commPerLot;
   // Modelo de conta.
   double startBalance;
   bool   applySwap;     // v1: false (swap-free, marcado)
   // Config da estratégia.
   double slPoints;
   long   magic;
   string lotMode;       // "FIXED" | "PERCENT"
   double fixedLots;
   double riskPct;
   int    fillDays;      // E2.3: paridade exige 0
   bool   isShadow;      // E2.5: captura-shadow (banner de honestidade)

   MksDecisionJournalHeader()
   {
      symbol=""; broker=""; account=0; digits=0; point=0.0; tickSize=0.0;
      seedMid=0.0; seedTickSeq=0;
      spreadPts=0.0; slipPts=0.0; commPerLot=0.0;
      startBalance=0.0; applySwap=false;
      slPoints=0.0; magic=0; lotMode="FIXED"; fixedLots=0.0; riskPct=0.0;
      fillDays=0; isShadow=false;
   }
};

class CMksDecisionJournal
{
private:
   int    m_handle;
   string m_path;
   bool   m_headerWritten;
   long   m_ord;                 // contador de linha (alinhamento no diff)

   // Contexto do brick corrente (setado pelo runner antes do brick chegar
   // à estratégia). SEND/CLOSE herdam este contexto.
   long   m_ctxBrickIdx;
   ulong  m_ctxTriggerTickSeq;

   // Mapa positionId(broker) -> ordinal normalizado + side. Remove o
   // ticket não-determinístico do broker do journal.
   ulong               m_mapId[];
   long                m_mapOrdinal[];
   ENUM_MKS_ORDER_SIDE m_mapSide[];
   long                m_nextPosOrdinal;

   void WriteLine(const string &s)
   {
      if(m_handle == INVALID_HANDLE) return;
      FileWriteString(m_handle, s + "\r\n");
   }

   string ExecStatusStr(const ENUM_MKS_EXEC_STATUS s) const
   {
      if(s == MKS_EXEC_FILLED)   return "FILLED";
      if(s == MKS_EXEC_PARTIAL)  return "PARTIAL";
      if(s == MKS_EXEC_REJECTED) return "REJECTED";
      return "ERROR";
   }

   string SideStr(const ENUM_MKS_ORDER_SIDE side) const
   {
      return (side == MKS_ORDER_BUY) ? "BUY" : "SELL";
   }

   int FindMap(const ulong id) const
   {
      int n = ArraySize(m_mapId);
      for(int i = 0; i < n; i++)
         if(m_mapId[i] == id) return i;
      return -1;
   }

   long RegisterPos(const ulong id, const ENUM_MKS_ORDER_SIDE side)
   {
      int idx = FindMap(id);
      if(idx >= 0) return m_mapOrdinal[idx]; // já registrado (defensivo)
      int n = ArraySize(m_mapId);
      ArrayResize(m_mapId,      n + 1);
      ArrayResize(m_mapOrdinal, n + 1);
      ArrayResize(m_mapSide,    n + 1);
      long ord = m_nextPosOrdinal++;
      m_mapId[n]      = id;
      m_mapOrdinal[n] = ord;
      m_mapSide[n]    = side;
      return ord;
   }

   long OrdinalOf(const ulong id) const
   {
      int idx = FindMap(id);
      return (idx >= 0) ? m_mapOrdinal[idx] : 0;
   }

   // Uma linha TSV. Ordem de colunas é o contrato de paridade.
   void WriteEvent(const string &ev, const ENUM_MKS_EXEC_STATUS status,
                   const long brickIdx, const ulong triggerTickSeq,
                   const ENUM_MKS_ORDER_SIDE side, const long posOrdinal,
                   const double lots, const double slPoints,
                   const double tpPoints, const int retcode)
   {
      WriteLine(StringFormat(
         "%I64d\t%s\t%s\t%I64d\t%I64u\t%s\t%I64d\t%.6f\t%.6f\t%.6f\t%d",
         m_ord, ev, ExecStatusStr(status), brickIdx, triggerTickSeq,
         SideStr(side), posOrdinal, lots, slPoints, tpPoints, retcode));
      m_ord++;
   }

public:
   CMksDecisionJournal()
   {
      m_handle = INVALID_HANDLE;
      m_path = "";
      m_headerWritten = false;
      m_ord = 0;
      m_ctxBrickIdx = -1;
      m_ctxTriggerTickSeq = 0;
      m_nextPosOrdinal = 1;
      ArrayResize(m_mapId, 0);
      ArrayResize(m_mapOrdinal, 0);
      ArrayResize(m_mapSide, 0);
   }

   ~CMksDecisionJournal()
   {
      if(m_handle != INVALID_HANDLE) FileClose(m_handle);
   }

   bool Open(const string &path)
   {
      if(m_handle != INVALID_HANDLE) return false;
      m_path = path;
      m_handle = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
      return (m_handle != INVALID_HANDLE);
   }

   // Header com o bundle pinado (linhas '#') + cabeçalho de colunas.
   // Chamado UMA vez antes do 1º evento.
   void WriteHeader(const MksDecisionJournalHeader &h)
   {
      if(m_headerWritten || m_handle == INVALID_HANDLE) return;
      WriteLine("# MKS-ULTIMATE decision journal");
      WriteLine(StringFormat("# symbol=%s broker=\"%s\" account=%I64d digits=%d point=%.6f tickSize=%.6f",
                             h.symbol, h.broker, h.account, h.digits, h.point, h.tickSize));
      WriteLine(StringFormat("# ANCHOR seedMid=%.6f seedTickSeq=%I64u",
                             h.seedMid, h.seedTickSeq));
      WriteLine(StringFormat("# COST spreadPts=%.6f slipPts=%.6f commPerLot=%.6f",
                             h.spreadPts, h.slipPts, h.commPerLot));
      WriteLine(StringFormat("# ACCT model=SIM startBalance=%.6f mtm=on swap=%s",
                             h.startBalance, (h.applySwap ? "on" : "off")));
      WriteLine(StringFormat("# STRAT slPoints=%.6f magic=%I64d lotMode=%s fixedLots=%.6f riskPct=%.6f",
                             h.slPoints, h.magic, h.lotMode, h.fixedLots, h.riskPct));
      WriteLine(StringFormat("# fillDays=%d", h.fillDays));
      if(h.isShadow)
         WriteLine("# BANNER SHADOW-SIM — NAO e o que o EA real tradou; ver ADR de paridade");
      WriteLine("ord\tev\tstatus\tbrickIdx\ttriggerTickSeq\tside\tposOrdinal\tlots\tslPoints\ttpPoints\tretcode");
      m_headerWritten = true;
   }

   // Setado pelo runner (via context sink) antes do brick chegar à
   // estratégia. SEND/CLOSE do flip herdam este contexto.
   void SetBrickContext(const long brickIdx, const ulong triggerTickSeq)
   {
      m_ctxBrickIdx       = brickIdx;
      m_ctxTriggerTickSeq = triggerTickSeq;
   }

   // Decisão de ABERTURA (do JournalingBroker, fora do gate → enxerga
   // REJECTED do risco). posOrdinal atribuído no 1º SEND FILLED.
   void RecordSend(const ENUM_MKS_EXEC_STATUS status,
                   const ENUM_MKS_ORDER_SIDE side, const ulong positionId,
                   const double lots, const double slPoints,
                   const double tpPoints, const int retcode)
   {
      long posOrd = 0;
      if(status == MKS_EXEC_FILLED)
         posOrd = RegisterPos(positionId, side);
      WriteEvent("SEND", status, m_ctxBrickIdx, m_ctxTriggerTickSeq,
                 side, posOrd, lots, slPoints, tpPoints, retcode);
   }

   // Decisão de FECHAMENTO no flip (do JournalingBroker). side/ordinal
   // via o mapa do SEND.
   void RecordClose(const ENUM_MKS_EXEC_STATUS status, const ulong positionId,
                    const double lots, const int retcode)
   {
      int idx = FindMap(positionId);
      ENUM_MKS_ORDER_SIDE side = (idx >= 0) ? m_mapSide[idx] : MKS_ORDER_BUY;
      long posOrd = (idx >= 0) ? m_mapOrdinal[idx] : 0;
      WriteEvent("CLOSE", status, m_ctxBrickIdx, m_ctxTriggerTickSeq,
                 side, posOrd, lots, 0.0, 0.0, retcode);
   }

   // AUTO-CLOSE de SL/TP (do runner, via PollAutoCloses). brickIdx=-1;
   // triggerTickSeq = seq do tick que cruzou (do MksSimAutoCloseEvent).
   void RecordAutoClose(const ENUM_MKS_ORDER_SIDE side, const ulong positionId,
                        const double lots, const ulong triggerTickSeq)
   {
      long posOrd = OrdinalOf(positionId);
      WriteEvent("AUTOCLOSE", MKS_EXEC_FILLED, -1, triggerTickSeq,
                 side, posOrd, lots, 0.0, 0.0, 0);
   }

   void Flush()
   {
      if(m_handle != INVALID_HANDLE) FileFlush(m_handle);
   }

   void Close()
   {
      if(m_handle == INVALID_HANDLE) return;
      WriteLine(StringFormat("# total=%I64d", m_ord));
      FileClose(m_handle);
      m_handle = INVALID_HANDLE;
   }

   long  EventCount() const { return m_ord; }
   string Path()      const { return m_path; }
};

#endif // MKS_ULTIMATE_CORE_TRADE_CMKSDECISIONJOURNAL_MQH
