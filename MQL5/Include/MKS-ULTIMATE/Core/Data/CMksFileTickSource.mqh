//+------------------------------------------------------------------+
//| @file           : CMksFileTickSource.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Data
//| @responsibility : Implementação de ITickSource sobre arquivo .mkstick.
//|                   Encapsula CMksTickFileReader, valida proveniência
//|                   contra a conta corrente (broker/account WARN-flag,
//|                   symbol fatal — ADR-024 §4), expõe LastTickTimeMsc()
//|                   para o CMksReplayClock.
//| @depends_on     : Core/Interfaces/ITickSource.mqh,
//|                   Core/Data/CMksTickFileReader.mqh,
//|                   Core/Types/Tick.mqh, Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Data/CMksFileTickSource.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_DATA_CMKSFILETICKSOURCE_MQH
#define MKS_ULTIMATE_CORE_DATA_CMKSFILETICKSOURCE_MQH

#include <MKS-ULTIMATE/Core/Interfaces/ITickSource.mqh>
#include <MKS-ULTIMATE/Core/Data/CMksTickFileReader.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Padrão de uso:
//   CMksFileTickSource src(path, expectedBroker, expectedAccount, expectedSymbol);
//   if(!src.Open(err)) return;
//   if(src.BrokerMismatch()) logger.Warn(src.BrokerMismatchMsg());
//   if(src.AccountMismatch()) logger.Warn(src.AccountMismatchMsg());
//   MksTick t;
//   while(src.Next(t)) builder.IngestTick(t);
//
// Política de proveniência (ADR-024 §4 + ADR-012 §2 + ADR-013 §3):
//   - broker  do arquivo != esperado → WARN-flag, Open ainda sucede
//   - account do arquivo != esperada → WARN-flag, Open ainda sucede
//   - symbol  do arquivo != esperado → FATAL, Open falha
//
// O WARN é exposto via getters em vez de logar diretamente — mantém
// o source desacoplado de ILogger e replay-safe. Composition root
// (Replayer EA) inspeciona após Open e decide se loga.
//
// Multi-arquivo: esta versão (slice 24b) cobre apenas single-file.
// Multi-arquivo cross-day (ADR-024 §4 último parágrafo, com validação
// de seq-discontinuity 804) entra no slice 24d quando o Recorder
// produzir múltiplos arquivos. Antes disso seria overhead sem retorno.
class CMksFileTickSource : public ITickSource
{
private:
   string m_path;
   string m_expectedBroker;
   long   m_expectedAccount;
   string m_expectedSymbol;

   CMksTickFileReader m_reader;
   bool   m_opened;
   long   m_lastTickTimeMsc;

   bool   m_brokerMismatch;
   bool   m_accountMismatch;
   string m_brokerMismatchMsg;
   string m_accountMismatchMsg;

public:
   CMksFileTickSource(const string &path,
                      const string &expectedBroker,
                      long expectedAccount,
                      const string &expectedSymbol)
   {
      m_path = path;
      m_expectedBroker = expectedBroker;
      m_expectedAccount = expectedAccount;
      m_expectedSymbol = expectedSymbol;
      m_opened = false;
      m_lastTickTimeMsc = 0;
      m_brokerMismatch = false;
      m_accountMismatch = false;
      m_brokerMismatchMsg = "";
      m_accountMismatchMsg = "";
   }

   ~CMksFileTickSource()
   {
      if(m_opened) m_reader.Close();
   }

   bool Open(MksError &err)
   {
      if(m_opened)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID, "source já aberto", m_path);
         return false;
      }
      if(!m_reader.Open(m_path, err)) return false;

      // Symbol é fronteira fatal. ADR-024 §4: sem proveniência canônica
      // de símbolo, o feed pode ser de outro instrumento — backtest
      // inteiro fica inválido. Código dedicado MKS_ERR_DATA_SYMBOL_MISMATCH
      // (807) materializado no slice 24c.
      if(StringCompare(m_reader.Symbol(), m_expectedSymbol) != 0)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_SYMBOL_MISMATCH,
                       "symbol mismatch — fatal por ADR-024 §4",
                       StringFormat("file=%s expected=%s got=%s",
                                    m_path, m_expectedSymbol, m_reader.Symbol()));
         m_reader.Close();
         return false;
      }

      // Broker e account são WARN-flag (ADR-012 §2 + ADR-013 §3).
      if(StringCompare(m_reader.Broker(), m_expectedBroker) != 0)
      {
         m_brokerMismatch = true;
         m_brokerMismatchMsg = StringFormat(
            "broker mismatch — file=%s expected=%s got=%s",
            m_path, m_expectedBroker, m_reader.Broker());
      }
      if(m_reader.AccountLogin() != m_expectedAccount)
      {
         m_accountMismatch = true;
         m_accountMismatchMsg = StringFormat(
            "account mismatch — file=%s expected=%I64d got=%I64d",
            m_path, m_expectedAccount, m_reader.AccountLogin());
      }

      m_opened = true;
      return true;
   }

   // ITickSource: lê próximo tick na ordem natural do arquivo. Retorna
   // false no EOF (sem erro — fim do feed em replay é caminho normal,
   // não falha de I/O).
   virtual bool Next(MksTick &tick) override
   {
      if(!m_opened) return false;
      if(!m_reader.HasMore()) return false;

      MksError err;
      if(!m_reader.ReadNext(tick, err)) return false;

      m_lastTickTimeMsc = tick.timeMsc;
      return true;
   }

   void Close()
   {
      if(m_opened)
      {
         m_reader.Close();
         m_opened = false;
      }
   }

   // Consultado pelo CMksReplayClock. 0 antes do primeiro Next() bem-sucedido.
   long LastTickTimeMsc() const { return m_lastTickTimeMsc; }

   // Proveniência observada (delegada ao reader).
   string Broker()       const { return m_reader.Broker(); }
   long   AccountLogin() const { return m_reader.AccountLogin(); }
   string Symbol()       const { return m_reader.Symbol(); }
   int    Digits()       const { return m_reader.Digits(); }
   double TickSize()     const { return m_reader.TickSize(); }
   double Point()        const { return m_reader.Point(); }
   double ContractSize() const { return m_reader.ContractSize(); }
   long   TickCount()    const { return m_reader.TickCount(); }
   long   TimeMscFirst() const { return m_reader.TimeMscFirst(); }
   long   TimeMscLast()  const { return m_reader.TimeMscLast(); }
   long   TicksRead()    const { return m_reader.TicksRead(); }

   // Mismatch flags + mensagens para o composition root logar.
   bool   BrokerMismatch()       const { return m_brokerMismatch; }
   bool   AccountMismatch()      const { return m_accountMismatch; }
   string BrokerMismatchMsg()    const { return m_brokerMismatchMsg; }
   string AccountMismatchMsg()   const { return m_accountMismatchMsg; }
};

#endif // MKS_ULTIMATE_CORE_DATA_CMKSFILETICKSOURCE_MQH