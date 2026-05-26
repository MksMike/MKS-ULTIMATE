//+------------------------------------------------------------------+
//| @file           : CMksAuditLogSink.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Output
//| @responsibility : Sink que escreve um audit log textual TSV de cada
//|                   brick emitido + eventos anômalos do builder
//|                   (K excedido, tick inválido descartado). Producer
//|                   e Replayer geram audits no MESMO formato — diff
//|                   linha-a-linha revela a primeira divergência em
//|                   forma humana-legível, complementando o fc/b
//|                   binário do verify-parity.ps1.
//| @depends_on     : Core/Interfaces/IRenkoSink.mqh,
//|                   Core/Types/Brick.mqh, Core/Types/FormingBrick.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Output/CMksAuditLogSink.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_OUTPUT_CMKSAUDITLOGSINK_MQH
#define MKS_ULTIMATE_CORE_OUTPUT_CMKSAUDITLOGSINK_MQH

#include <MKS-ULTIMATE/Core/Interfaces/IRenkoSink.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/FormingBrick.mqh>

// Audit log TSV reproduzível. Producer e Replayer instanciam este sink
// e geram arquivos com mesmo formato. Comparação via diff/fc /l aponta
// a primeira linha divergente — útil pra debugging humano onde o
// fc/b binário do verify-parity.ps1 só dá offset de byte.
//
// Formato:
//   Header (comentado, ignorado em diff de bricks):
//     # MKS-ULTIMATE audit log
//     # symbol=<...> broker=<...> account=<...> sizePoints=<...> geometry=<...>
//   Cabeçalho de colunas:
//     idx	seq	dir	open	close	high	low	trigger	tickId	closeTimeMsc	M
//   Por brick (uma linha TSV, precisão alta no double):
//     0	1	BEAR	4523.762000	4522.762000	4523.911000	4522.762000	4522.717500	78	1779797744000	1
//   Eventos anômalos (linhas começando com "# K_EXCEEDED" / "# INVALID_TICK"):
//     # K_EXCEEDED tickSeq=120 mid=4525.500000 M=21
//     # INVALID_TICK tickSeq=145 bid=0.000000 ask=0.000000
//
// Determinismo: precisão %.6f no double cobre 6 casas decimais — mais
// que os 3 digits do XAU. Garante reprodutibilidade bit-a-bit do TSV
// entre Producer e Replayer dado mesmo input.
class CMksAuditLogSink : public IRenkoSink
{
private:
   int    m_handle;
   long   m_brickIdx;       // contador local
   bool   m_headerWritten;
   string m_path;

   void WriteLine(const string &s)
   {
      if(m_handle == INVALID_HANDLE) return;
      FileWriteString(m_handle, s + "\r\n");
   }

public:
   CMksAuditLogSink()
   {
      m_handle = INVALID_HANDLE;
      m_brickIdx = 0;
      m_headerWritten = false;
      m_path = "";
   }

   ~CMksAuditLogSink()
   {
      if(m_handle != INVALID_HANDLE) FileClose(m_handle);
   }

   // Abre o arquivo audit em modo escrita texto. Retorna true se sucesso.
   bool Open(const string &path)
   {
      if(m_handle != INVALID_HANDLE) return false;
      m_path = path;
      // FILE_TXT + ANSI: TSV ASCII puro, evita problemas de encoding
      // entre Producer (Windows) e ferramentas de diff.
      m_handle = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_ANSI);
      return (m_handle != INVALID_HANDLE);
   }

   // Escreve cabeçalho com proveniência (linhas comentadas) + cabeçalho
   // de colunas TSV. Deve ser chamado UMA vez antes do primeiro brick.
   void WriteHeader(const string &symbol, const string &broker,
                    long accountLogin, int digits,
                    double sizePoints, const string &geometryPreset)
   {
      if(m_headerWritten || m_handle == INVALID_HANDLE) return;
      WriteLine("# MKS-ULTIMATE audit log");
      WriteLine(StringFormat("# symbol=%s broker=\"%s\" account=%I64d digits=%d",
                              symbol, broker, accountLogin, digits));
      WriteLine(StringFormat("# sizePoints=%.6f geometry=%s",
                              sizePoints, geometryPreset));
      // Cabeçalho de colunas TSV (tab-separated, tudo numérico exceto dir)
      WriteLine("idx\tseq\tdir\topen\tclose\thigh\tlow\ttrigger\ttickId\tcloseTimeMsc\tM");
      m_headerWritten = true;
   }

   // IRenkoSink: brick fechado pelo builder. Escreve uma linha TSV.
   virtual void OnBrickClose(const MksBrick &brick) override
   {
      if(m_handle == INVALID_HANDLE) return;
      string dir = (brick.direction == MKS_BRICK_BULL) ? "BULL" : "BEAR";
      WriteLine(StringFormat(
         "%I64d\t%I64d\t%s\t%.6f\t%.6f\t%.6f\t%.6f\t%.6f\t%I64u\t%I64d\t%d",
         m_brickIdx,
         (long)brick.triggerTickId, // seq do tick (igual triggerTickId para auditoria)
         dir,
         brick.open, brick.close, brick.high, brick.low,
         brick.triggerPrice,
         brick.triggerTickId,
         brick.closeTimeMsc,
         brick.thresholdsCrossed));
      m_brickIdx++;
   }

   // IRenkoSink: bar parcial — sink ignora (audit log só registra bricks
   // fechados; bar parcial é estado intermediário não reproduzível
   // por construção do brick fechado).
   virtual void OnBrickForming(const MksFormingBrick &fb) override { }

   //--- Eventos anômalos do builder (chamados pelo caller — Producer/
   //--- Replayer — quando detectam erros 102/103/104) ---

   void RecordKExceeded(ulong tickSeq, double mid, int M)
   {
      if(m_handle == INVALID_HANDLE) return;
      WriteLine(StringFormat("# K_EXCEEDED tickSeq=%I64u mid=%.6f M=%d",
                              tickSeq, mid, M));
   }

   void RecordInvalidTick(ulong tickSeq, double bid, double ask)
   {
      if(m_handle == INVALID_HANDLE) return;
      WriteLine(StringFormat("# INVALID_TICK tickSeq=%I64u bid=%.6f ask=%.6f",
                              tickSeq, bid, ask));
   }

   void RecordStreamHalted(ulong tickSeq, int invalidLimit)
   {
      if(m_handle == INVALID_HANDLE) return;
      WriteLine(StringFormat("# STREAM_HALTED tickSeq=%I64u invalidLimit=%d",
                              tickSeq, invalidLimit));
   }

   // Fecha o arquivo. Escreve rodapé com contagem total.
   void Close()
   {
      if(m_handle == INVALID_HANDLE) return;
      WriteLine(StringFormat("# total=%I64d", m_brickIdx));
      FileClose(m_handle);
      m_handle = INVALID_HANDLE;
   }

   long  BrickIdx() const { return m_brickIdx; }
   string Path()   const { return m_path; }
};

#endif // MKS_ULTIMATE_CORE_OUTPUT_CMKSAUDITLOGSINK_MQH
