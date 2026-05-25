//+------------------------------------------------------------------+
//| @file           : CMksMultiFileTickSource.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Data
//| @responsibility : Implementação de ITickSource sobre conjunto
//|                   ordenado de arquivos .mkstick (multi-day replay).
//|                   Transição transparente entre arquivos consecutivos,
//|                   validação de proveniência homogênea + continuidade
//|                   de seq cross-file. Materializa ADR-024 §regra 4
//|                   último parágrafo.
//| @depends_on     : Core/Interfaces/ITickSource.mqh,
//|                   Core/Data/CMksFileTickSource.mqh,
//|                   Core/Types/Tick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Data/CMksMultiFileTickSource.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_DATA_CMKSMULTIFILETICKSOURCE_MQH
#define MKS_ULTIMATE_CORE_DATA_CMKSMULTIFILETICKSOURCE_MQH

#include <MKS-ULTIMATE/Core/Interfaces/ITickSource.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksFileTickSource.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Padrão de uso:
//   string paths[];
//   ArrayResize(paths, 3);
//   paths[0] = "MKS-ULTIMATE/Ticks/XAUUSDm_20260520.mkstick";
//   paths[1] = "MKS-ULTIMATE/Ticks/XAUUSDm_20260521.mkstick";
//   paths[2] = "MKS-ULTIMATE/Ticks/XAUUSDm_20260522.mkstick";
//   CMksMultiFileTickSource src(paths, expectedBroker, expectedAccount, expectedSymbol);
//   if(!src.Open(err)) return;
//   MksTick t;
//   while(src.Next(t)) builder.IngestTick(t);
//
// Política cross-file (ADR-024 §4 último parágrafo):
//   - Symbol cross-file: TODOS os arquivos têm que ser do mesmo símbolo.
//     Divergência = 811 (MULTI_PROVENANCE_MISMATCH), fatal.
//   - Broker/Account cross-file: idem 811. Replayer só pode misturar
//     arquivos do mesmo (broker, account, symbol) — paridade arquitetural
//     depende disso (ADR-012 §2).
//   - Seq cross-file: último seq do arquivo N tem que ser estritamente
//     menor que o primeiro seq do N+1. Divergência = 810
//     (SEQ_DISCONTINUITY), fatal.
//
// Quanto à proveniência **vs conta corrente em runtime** (broker/account
// diferentes do que está logado no terminal), a política da ADR-024 §4
// é WARN-flag — herdada do CMksFileTickSource single-file (o primeiro
// arquivo aberto define o flag, demais arquivos têm que bater com ele).
class CMksMultiFileTickSource : public ITickSource
{
private:
   string m_paths[];
   string m_expectedBroker;
   long   m_expectedAccount;
   string m_expectedSymbol;

   CMksFileTickSource *m_current;
   int    m_currentIdx;    // -1 antes do primeiro Open
   bool   m_opened;
   long   m_lastTickTimeMsc;
   ulong  m_lastSeqGlobal;          // último seq lido, cross-file
   long   m_accumulatedTicksRead;   // soma de TicksRead dos arquivos já fechados

   // Proveniência observada no primeiro arquivo aberto (referência para
   // validação cross-file). String vazia / 0 antes do primeiro Open.
   string m_observedBroker;
   long   m_observedAccount;

   // WARN-flag agregada vs conta corrente (do primeiro arquivo).
   bool   m_brokerMismatch;
   bool   m_accountMismatch;
   string m_brokerMismatchMsg;
   string m_accountMismatchMsg;

   bool OpenFileAt(int idx, MksError &err)
   {
      if(m_current != NULL) { delete m_current; m_current = NULL; }

      m_current = new CMksFileTickSource(m_paths[idx],
                                         m_expectedBroker,
                                         m_expectedAccount,
                                         m_expectedSymbol);
      if(!m_current.Open(err))
      {
         // Preserva o erro original do CMksFileTickSource (symbol mismatch,
         // magic inválido, etc.). Limpeza fica para o destrutor / Close.
         return false;
      }

      // Primeira abertura: trava a proveniência observada e captura WARN.
      if(idx == 0)
      {
         m_observedBroker  = m_current.Broker();
         m_observedAccount = m_current.AccountLogin();
         m_brokerMismatch     = m_current.BrokerMismatch();
         m_accountMismatch    = m_current.AccountMismatch();
         m_brokerMismatchMsg  = m_current.BrokerMismatchMsg();
         m_accountMismatchMsg = m_current.AccountMismatchMsg();
         return true;
      }

      // Arquivos seguintes: proveniência cross-file homogênea (fatal).
      if(StringCompare(m_current.Broker(), m_observedBroker) != 0)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_MULTI_PROVENANCE_MISMATCH,
                       "broker divergente entre arquivos do conjunto",
                       StringFormat("idx=%d path=%s firstBroker=%s thisBroker=%s",
                                    idx, m_paths[idx],
                                    m_observedBroker, m_current.Broker()));
         return false;
      }
      if(m_current.AccountLogin() != m_observedAccount)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_MULTI_PROVENANCE_MISMATCH,
                       "account divergente entre arquivos do conjunto",
                       StringFormat("idx=%d path=%s firstAccount=%I64d thisAccount=%I64d",
                                    idx, m_paths[idx],
                                    m_observedAccount, m_current.AccountLogin()));
         return false;
      }
      // Symbol já é fatal no CMksFileTickSource.Open (m_expectedSymbol).
      return true;
   }

   // Tenta avançar para o próximo arquivo. Retorna true se abriu OK,
   // false se acabou (m_currentIdx >= ArraySize(m_paths)) ou erro.
   bool AdvanceToNextFile(MksError &err)
   {
      if(m_current != NULL)
      {
         m_accumulatedTicksRead += m_current.TicksRead();
         delete m_current;
         m_current = NULL;
      }
      m_currentIdx++;
      if(m_currentIdx >= ArraySize(m_paths)) return false;
      return OpenFileAt(m_currentIdx, err);
   }

public:
   // paths: array ordenado cronologicamente. Vazio = não pode abrir.
   // Para arquivos .mkstick com naming <symbol>_YYYYMMDD.mkstick,
   // ordenação lexicográfica == cronológica (vide ADR-024 §3).
   CMksMultiFileTickSource(const string &paths[],
                           const string &expectedBroker,
                           long expectedAccount,
                           const string &expectedSymbol)
   {
      ArrayResize(m_paths, ArraySize(paths));
      for(int i = 0; i < ArraySize(paths); i++) m_paths[i] = paths[i];
      m_expectedBroker  = expectedBroker;
      m_expectedAccount = expectedAccount;
      m_expectedSymbol  = expectedSymbol;
      m_current = NULL;
      m_currentIdx = -1;
      m_opened = false;
      m_lastTickTimeMsc = 0;
      m_lastSeqGlobal = 0;
      m_accumulatedTicksRead = 0;
      m_observedBroker = "";
      m_observedAccount = 0;
      m_brokerMismatch = false;
      m_accountMismatch = false;
      m_brokerMismatchMsg = "";
      m_accountMismatchMsg = "";
   }

   ~CMksMultiFileTickSource()
   {
      if(m_current != NULL) { delete m_current; m_current = NULL; }
   }

   bool Open(MksError &err)
   {
      if(m_opened)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID,
                       "multi source já aberto", "");
         return false;
      }
      if(ArraySize(m_paths) == 0)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID,
                       "lista de paths vazia", "");
         return false;
      }
      m_currentIdx = 0;
      if(!OpenFileAt(0, err)) return false;
      m_opened = true;
      return true;
   }

   virtual bool Next(MksTick &tick) override
   {
      if(!m_opened || m_current == NULL) return false;

      // Tenta o arquivo corrente. Se EOF, avança para o próximo.
      while(true)
      {
         if(m_current.Next(tick))
         {
            // Continuidade de seq cross-file: tick[0] do arquivo N+1 deve
            // ter seq estritamente > último seq do arquivo N.
            if(m_lastSeqGlobal > 0 && tick.seq <= m_lastSeqGlobal)
            {
               // Reporta via Print (Next não tem out-param de erro na
               // interface ITickSource). Encerra o stream — paridade
               // exige continuidade. Composition root pode inspecionar
               // via SeqDiscontinuityDetected() abaixo.
               m_seqDiscontinuity = true;
               m_seqDiscontinuityMsg = StringFormat(
                  "seq cross-file invalida: lastGlobal=%I64u currentInFileIdx=%d firstInFileSeq=%I64u",
                  m_lastSeqGlobal, m_currentIdx, tick.seq);
               return false;
            }
            m_lastSeqGlobal = tick.seq;
            m_lastTickTimeMsc = tick.timeMsc;
            return true;
         }

         // EOF do arquivo corrente — tenta próximo.
         MksError err;
         if(!AdvanceToNextFile(err))
         {
            // Sem mais arquivos OU falha ao abrir próximo.
            if(err.HasError())
            {
               m_openFailedDuringAdvance = true;
               m_advanceErrorMsg = err.ToString();
            }
            return false;
         }
         // Loop volta — tenta Next() no arquivo recém-aberto.
      }
   }

   void Close()
   {
      if(m_current != NULL) { delete m_current; m_current = NULL; }
      m_opened = false;
   }

   virtual long LastTickTimeMsc() const override { return m_lastTickTimeMsc; }

   // Soma de ticks lidos em todos os arquivos do conjunto.
   long TicksRead() const
   {
      long current = (m_current != NULL) ? m_current.TicksRead() : 0;
      return m_accumulatedTicksRead + current;
   }

   int  FileCount()      const { return ArraySize(m_paths); }
   int  CurrentFileIdx() const { return m_currentIdx; }
   string CurrentFilePath() const
   {
      if(m_currentIdx < 0 || m_currentIdx >= ArraySize(m_paths)) return "";
      return m_paths[m_currentIdx];
   }

   // Flags WARN herdadas do primeiro arquivo aberto.
   bool   BrokerMismatch()    const { return m_brokerMismatch; }
   bool   AccountMismatch()   const { return m_accountMismatch; }
   string BrokerMismatchMsg() const { return m_brokerMismatchMsg; }
   string AccountMismatchMsg()const { return m_accountMismatchMsg; }

   // Erros fatais detectados durante Next() (que não tem out-param).
   // Composition root inspeciona após Next() retornar false para
   // distinguir EOF natural de falha real.
   bool   SeqDiscontinuityDetected()       const { return m_seqDiscontinuity; }
   string SeqDiscontinuityMsg()            const { return m_seqDiscontinuityMsg; }
   bool   AdvanceFailureDetected()         const { return m_openFailedDuringAdvance; }
   string AdvanceErrorMsg()                const { return m_advanceErrorMsg; }

private:
   // Flags de falha detectada durante Next() (a interface não tem out-param).
   bool   m_seqDiscontinuity;
   string m_seqDiscontinuityMsg;
   bool   m_openFailedDuringAdvance;
   string m_advanceErrorMsg;
};

#endif // MKS_ULTIMATE_CORE_DATA_CMKSMULTIFILETICKSOURCE_MQH
