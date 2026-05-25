//+------------------------------------------------------------------+
//| @file           : CMksTickFileWriter.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Data
//| @responsibility : Serializa MksTick em arquivo .mkstick com header
//|                   de proveniência (broker, conta, símbolo, snapshot
//|                   de tickSize/point/contractSize). Layout em
//|                   TickFileFormat.mqh. Broker-locked conforme
//|                   ADR-012 §3, ADR-013 §3 e ADR-024 §2.
//| @depends_on     : Core/Data/TickFileFormat.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Data/CMksTickFileWriter.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_DATA_CMKSTICKFILEWRITER_MQH
#define MKS_ULTIMATE_CORE_DATA_CMKSTICKFILEWRITER_MQH

#include <MKS-ULTIMATE/Core/Data/TickFileFormat.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

// Padrão de uso:
//   CMksTickFileWriter w;
//   if(!w.Open("MKS-ULTIMATE/Ticks/XAUUSDm_20260523.mkstick", err)) return;
//   if(!w.WriteHeader(broker, account, symbol, digits,
//                     tickSize, point, contractSize, createdAtMsc, err)) {...}
//   for each tick: w.WriteTick(tick, err);
//   w.Close(err); // patcheia header com tickCount + timeMscFirst/Last + closedAt
//
// WriteHeader grava um header com tickCount=0 e times zerados; Close
// faz seek de volta e sobrescreve esses campos com os valores reais.
// O slice 24d (TickRecorder Service) ainda adicionará política de reopen
// no mesmo arquivo (ADR-024 §2); o writer aqui é o caminho de criação.
class CMksTickFileWriter
{
private:
   int    m_handle;
   long   m_tickCount;
   long   m_timeMscFirst;
   long   m_timeMscLast;
   long   m_createdAtMsc;
   bool   m_hasFirst;
   bool   m_headerWritten;
   bool   m_closed;

   bool WriteFixedString(const string &s, int fixedLen, MksError &err)
   {
      uchar src[];
      int copied = StringToCharArray(s, src, 0, -1, CP_UTF8); // inclui \0 final
      int strLen = (copied > 0) ? copied - 1 : 0;
      int n = (strLen < fixedLen) ? strLen : fixedLen;

      uchar out[];
      ArrayResize(out, fixedLen);
      ArrayInitialize(out, 0);
      for(int i = 0; i < n; i++) out[i] = src[i];

      if(FileWriteArray(m_handle, out, 0, fixedLen) != (uint)fixedLen)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_FILE_IO, "fixed string write failed",
                       StringFormat("fixedLen=%d", fixedLen));
         return false;
      }
      return true;
   }

   bool WriteZeros(int count, MksError &err)
   {
      uchar zeros[];
      ArrayResize(zeros, count);
      ArrayInitialize(zeros, 0);
      if(FileWriteArray(m_handle, zeros, 0, count) != (uint)count)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_FILE_IO, "zero-fill write failed",
                       StringFormat("count=%d", count));
         return false;
      }
      return true;
   }

public:
   CMksTickFileWriter()
   {
      m_handle = INVALID_HANDLE;
      m_tickCount = 0;
      m_timeMscFirst = 0; m_timeMscLast = 0; m_createdAtMsc = 0;
      m_hasFirst = false;
      m_headerWritten = false;
      m_closed = false;
   }

   ~CMksTickFileWriter()
   {
      if(m_handle != INVALID_HANDLE)
         FileClose(m_handle);
   }

   bool Open(const string &path, MksError &err)
   {
      if(m_handle != INVALID_HANDLE)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID, "writer já aberto", path);
         return false;
      }
      // Caminho de criação. Política de reopen entra no slice 24d (Service).
      if(FileIsExist(path))
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_FILE_EXISTS,
                       "arquivo já existe — recusa sobrescrever", path);
         return false;
      }
      m_handle = FileOpen(path, FILE_READ | FILE_WRITE | FILE_BIN);
      if(m_handle == INVALID_HANDLE)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_FILE_IO, "FileOpen falhou",
                       StringFormat("path=%s LastError=%d", path, GetLastError()));
         return false;
      }
      return true;
   }

   // createdAtMscOverride < 0 => usa TimeCurrent (produção). Valor explícito
   // permite golden file test reproduzível byte-a-byte.
   bool WriteHeader(const string &broker, long accountLogin,
                    const string &symbol, int digits,
                    double tickSize, double point, double contractSize,
                    MksError &err,
                    long createdAtMscOverride = -1)
   {
      if(m_handle == INVALID_HANDLE || m_closed)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID,
                       "WriteHeader em writer fechado ou não aberto", "");
         return false;
      }
      if(m_headerWritten)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID,
                       "WriteHeader chamado mais de uma vez", "");
         return false;
      }

      FileSeek(m_handle, 0, SEEK_SET);

      // Magic — 8 bytes ASCII ("MKSTK01" + \0 final por zero-fill)
      if(!WriteFixedString(MKS_TICKFILE_MAGIC, MKS_TICKFILE_MAGIC_SIZE, err))
         return false;

      // formatVersion (uint16), tickRecordSize (uint16), headerSize (uint32)
      FileWriteInteger(m_handle, MKS_TICKFILE_FORMAT_VERSION, 2);
      FileWriteInteger(m_handle, MKS_TICKFILE_RECORD_SIZE,    2);
      FileWriteInteger(m_handle, MKS_TICKFILE_HEADER_SIZE,    4);

      // broker (64), accountLogin (8), symbol (32)
      if(!WriteFixedString(broker, MKS_TICKFILE_BROKER_SIZE, err)) return false;
      FileWriteLong(m_handle, accountLogin);
      if(!WriteFixedString(symbol, MKS_TICKFILE_SYMBOL_SIZE, err)) return false;

      // digits (1) + 7 bytes reserved → alinha p/ 128
      FileWriteInteger(m_handle, digits, 1);
      if(!WriteZeros(7, err)) return false;

      // Snapshot do símbolo (3 doubles)
      FileWriteDouble(m_handle, tickSize);
      FileWriteDouble(m_handle, point);
      FileWriteDouble(m_handle, contractSize);

      // 8 bytes reserved → alinha p/ 160
      if(!WriteZeros(8, err)) return false;

      // tickCount, timeMscFirst, timeMscLast, createdAtMsc, closedAtMsc
      // placeholders (0) — createdAt e closedAt patcheados no Close.
      FileWriteLong(m_handle, 0); // tickCount
      FileWriteLong(m_handle, 0); // timeMscFirst
      FileWriteLong(m_handle, 0); // timeMscLast
      FileWriteLong(m_handle, 0); // createdAtMsc
      FileWriteLong(m_handle, 0); // closedAtMsc

      // Reserved até 256 bytes
      ulong pos = FileTell(m_handle);
      int remaining = MKS_TICKFILE_HEADER_SIZE - (int)pos;
      if(remaining < 0)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_HEADER_INVALID,
                       "header excedeu tamanho previsto",
                       StringFormat("pos=%I64u expected=%d", pos, MKS_TICKFILE_HEADER_SIZE));
         return false;
      }
      if(remaining > 0 && !WriteZeros(remaining, err)) return false;

      // Memoriza createdAt para uso no Close (valor real é patcheado lá).
      m_createdAtMsc = (createdAtMscOverride >= 0)
                       ? createdAtMscOverride
                       : (long)TimeCurrent() * 1000;
      m_headerWritten = true;
      return true;
   }

   bool WriteTick(const MksTick &tick, MksError &err)
   {
      if(!m_headerWritten || m_closed)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID,
                       "WriteTick antes do header ou em writer fechado", "");
         return false;
      }

      FileWriteLong(m_handle,    (long)tick.seq);
      FileWriteLong(m_handle,    tick.timeMsc);
      FileWriteDouble(m_handle,  tick.bid);
      FileWriteDouble(m_handle,  tick.ask);
      FileWriteDouble(m_handle,  tick.last);
      FileWriteLong(m_handle,    tick.volume);
      FileWriteInteger(m_handle, (int)tick.flags, 4);

      // 12 bytes reserved no record (zero-fill p/ alinhar a 64).
      if(!WriteZeros(12, err)) return false;

      m_tickCount++;
      if(!m_hasFirst)
      {
         m_timeMscFirst = tick.timeMsc;
         m_hasFirst = true;
      }
      m_timeMscLast = tick.timeMsc;
      return true;
   }

   // Checkpoint: patcheia tickCount/timeMscFirst/timeMscLast no header SEM
   // fechar o handle, depois faz seek de volta para o final do arquivo
   // e força FileFlush. Permite que um crash do Service deixe o arquivo
   // parcialmente válido — leitor (CMksTickFileReader) lê exatamente os
   // ticks acumulados até o último Checkpoint. createdAtMsc e closedAtMsc
   // NÃO são gravados aqui (closedAtMsc só faz sentido em Close).
   bool Checkpoint(MksError &err)
   {
      if(m_handle == INVALID_HANDLE || m_closed)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID,
                       "Checkpoint em writer fechado ou não aberto", "");
         return false;
      }
      if(!m_headerWritten)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID,
                       "Checkpoint sem WriteHeader prévio", "");
         return false;
      }

      ulong endPos = FileTell(m_handle);

      FileSeek(m_handle, MKS_TICKFILE_OFF_TICK_COUNT, SEEK_SET);
      FileWriteLong(m_handle, m_tickCount);
      FileWriteLong(m_handle, m_timeMscFirst);
      FileWriteLong(m_handle, m_timeMscLast);

      FileSeek(m_handle, (long)endPos, SEEK_SET);
      FileFlush(m_handle);
      return true;
   }

   // Força flush dos bytes pendentes para disco sem mexer no header.
   // Cheap; pode ser chamado a cada N ticks no Service.
   void Flush()
   {
      if(m_handle != INVALID_HANDLE)
         FileFlush(m_handle);
   }

   // closedAtMscOverride < 0 => usa TimeCurrent (produção). Valor explícito
   // permite golden file test reproduzível byte-a-byte.
   bool Close(MksError &err, long closedAtMscOverride = -1)
   {
      if(m_handle == INVALID_HANDLE || m_closed)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID,
                       "Close em writer já fechado ou não aberto", "");
         return false;
      }
      if(!m_headerWritten)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID,
                       "Close sem WriteHeader prévio", "");
         FileClose(m_handle);
         m_handle = INVALID_HANDLE;
         m_closed = true;
         return false;
      }

      long closedAt = (closedAtMscOverride >= 0)
                      ? closedAtMscOverride
                      : (long)TimeCurrent() * 1000;

      // Patch dos campos dinâmicos do header.
      FileSeek(m_handle, MKS_TICKFILE_OFF_TICK_COUNT, SEEK_SET);
      FileWriteLong(m_handle, m_tickCount);
      FileWriteLong(m_handle, m_timeMscFirst);
      FileWriteLong(m_handle, m_timeMscLast);
      FileWriteLong(m_handle, m_createdAtMsc);
      FileWriteLong(m_handle, closedAt);

      FileClose(m_handle);
      m_handle = INVALID_HANDLE;
      m_closed = true;
      return true;
   }

   long TickCount() const { return m_tickCount; }
};

#endif // MKS_ULTIMATE_CORE_DATA_CMKSTICKFILEWRITER_MQH