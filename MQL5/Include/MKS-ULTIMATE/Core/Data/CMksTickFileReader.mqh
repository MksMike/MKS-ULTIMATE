//+------------------------------------------------------------------+
//| @file           : CMksTickFileReader.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Data
//| @responsibility : Lê arquivos .mkstick produzidos pelo writer. Valida
//|                   magic, formatVersion, recordSize, headerSize e
//|                   integridade (tamanho do arquivo == header + N*record).
//|                   Expõe proveniência via getters (ADR-013 §3, ADR-024 §4).
//|                   Camada base do CMksFileTickSource (slice 24b).
//| @depends_on     : Core/Data/TickFileFormat.mqh, Core/Types/Tick.mqh,
//|                   Core/Types/Error.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Data/CMksTickFileReader.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_DATA_CMKSTICKFILEREADER_MQH
#define MKS_ULTIMATE_CORE_DATA_CMKSTICKFILEREADER_MQH

#include <MKS-ULTIMATE/Core/Data/TickFileFormat.mqh>
#include <MKS-ULTIMATE/Core/Types/Tick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>

class CMksTickFileReader
{
private:
   int    m_handle;
   bool   m_headerLoaded;
   long   m_ticksRead;

   // Campos do header
   string m_broker;
   long   m_accountLogin;
   string m_symbol;
   int    m_digits;
   double m_tickSize;
   double m_point;
   double m_contractSize;
   long   m_tickCount;
   long   m_timeMscFirst;
   long   m_timeMscLast;
   long   m_createdAtMsc;
   long   m_closedAtMsc;

   bool ReadFixedString(int fixedLen, string &out, MksError &err)
   {
      uchar buf[];
      ArrayResize(buf, fixedLen);
      uint n = FileReadArray(m_handle, buf, 0, fixedLen);
      if(n != (uint)fixedLen)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_FILE_IO, "fixed string read failed",
                       StringFormat("fixedLen=%d read=%u", fixedLen, n));
         return false;
      }
      // CharArrayToString para até primeiro \0 ou fim do buffer.
      out = CharArrayToString(buf, 0, fixedLen, CP_UTF8);
      return true;
   }

public:
   CMksTickFileReader()
   {
      m_handle = INVALID_HANDLE;
      m_headerLoaded = false;
      m_ticksRead = 0;
      m_broker = ""; m_symbol = "";
      m_accountLogin = 0; m_digits = 0;
      m_tickSize = 0.0; m_point = 0.0; m_contractSize = 0.0;
      m_tickCount = 0; m_timeMscFirst = 0; m_timeMscLast = 0;
      m_createdAtMsc = 0; m_closedAtMsc = 0;
   }

   ~CMksTickFileReader()
   {
      if(m_handle != INVALID_HANDLE)
         FileClose(m_handle);
   }

   bool Open(const string &path, MksError &err)
   {
      if(m_handle != INVALID_HANDLE)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID, "reader já aberto", path);
         return false;
      }
      m_handle = FileOpen(path, FILE_READ | FILE_BIN);
      if(m_handle == INVALID_HANDLE)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_FILE_IO, "FileOpen falhou",
                       StringFormat("path=%s LastError=%d", path, GetLastError()));
         return false;
      }

      // Magic
      string magic;
      if(!ReadFixedString(MKS_TICKFILE_MAGIC_SIZE, magic, err)) return false;
      if(StringCompare(magic, MKS_TICKFILE_MAGIC) != 0)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_INVALID_MAGIC,
                       "magic inválido",
                       StringFormat("esperado=%s lido=%s",
                                    MKS_TICKFILE_MAGIC, magic));
         return false;
      }

      // formatVersion + recordSize + headerSize
      int formatVersion = FileReadInteger(m_handle, 2);
      int recordSize    = FileReadInteger(m_handle, 2);
      int headerSize    = FileReadInteger(m_handle, 4);

      if(formatVersion != MKS_TICKFILE_FORMAT_VERSION)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_UNSUPPORTED_VERSION,
                       "formatVersion não suportada",
                       StringFormat("lido=%d suportado=%d",
                                    formatVersion, MKS_TICKFILE_FORMAT_VERSION));
         return false;
      }
      if(recordSize != MKS_TICKFILE_RECORD_SIZE)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_HEADER_INVALID,
                       "recordSize inconsistente",
                       StringFormat("lido=%d esperado=%d",
                                    recordSize, MKS_TICKFILE_RECORD_SIZE));
         return false;
      }
      if(headerSize != MKS_TICKFILE_HEADER_SIZE)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_HEADER_INVALID,
                       "headerSize inconsistente",
                       StringFormat("lido=%d esperado=%d",
                                    headerSize, MKS_TICKFILE_HEADER_SIZE));
         return false;
      }

      // broker, accountLogin, symbol
      if(!ReadFixedString(MKS_TICKFILE_BROKER_SIZE, m_broker, err)) return false;
      m_accountLogin = FileReadLong(m_handle);
      if(!ReadFixedString(MKS_TICKFILE_SYMBOL_SIZE, m_symbol, err)) return false;

      // digits + 7 bytes reserved (skip)
      m_digits = FileReadInteger(m_handle, 1);
      FileSeek(m_handle, 7, SEEK_CUR);

      // Snapshot do símbolo
      m_tickSize     = FileReadDouble(m_handle);
      m_point        = FileReadDouble(m_handle);
      m_contractSize = FileReadDouble(m_handle);

      // 8 bytes reserved (skip)
      FileSeek(m_handle, 8, SEEK_CUR);

      // tickCount, timeMscFirst, timeMscLast, createdAtMsc, closedAtMsc
      m_tickCount    = FileReadLong(m_handle);
      m_timeMscFirst = FileReadLong(m_handle);
      m_timeMscLast  = FileReadLong(m_handle);
      m_createdAtMsc = FileReadLong(m_handle);
      m_closedAtMsc  = FileReadLong(m_handle);

      // Pula reserved final até headerSize
      FileSeek(m_handle, MKS_TICKFILE_HEADER_SIZE, SEEK_SET);

      // Validação de integridade: tamanho do arquivo == header + N*record
      ulong totalSize = FileSize(m_handle);
      ulong expected = (ulong)MKS_TICKFILE_HEADER_SIZE
                     + (ulong)m_tickCount * (ulong)MKS_TICKFILE_RECORD_SIZE;
      if(totalSize != expected)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_TRUNCATED,
                       "tamanho do arquivo inconsistente com tickCount",
                       StringFormat("size=%I64u expected=%I64u tickCount=%I64d",
                                    totalSize, expected, m_tickCount));
         return false;
      }

      m_headerLoaded = true;
      return true;
   }

   bool ReadNext(MksTick &tick, MksError &err)
   {
      if(!m_headerLoaded)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID,
                       "ReadNext antes de Open bem-sucedido", "");
         return false;
      }
      if(m_ticksRead >= m_tickCount)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_TRUNCATED,
                       "ReadNext além de tickCount",
                       StringFormat("read=%I64d total=%I64d",
                                    m_ticksRead, m_tickCount));
         return false;
      }

      tick.seq     = (ulong)FileReadLong(m_handle);
      tick.timeMsc = FileReadLong(m_handle);
      tick.bid     = FileReadDouble(m_handle);
      tick.ask     = FileReadDouble(m_handle);
      tick.last    = FileReadDouble(m_handle);
      tick.volume  = FileReadLong(m_handle);
      tick.flags   = (uint)FileReadInteger(m_handle, 4);

      // Pula 12 bytes reserved do record.
      FileSeek(m_handle, 12, SEEK_CUR);

      m_ticksRead++;
      return true;
   }

   void Close()
   {
      if(m_handle != INVALID_HANDLE)
      {
         FileClose(m_handle);
         m_handle = INVALID_HANDLE;
      }
   }

   // Getters de proveniência e estado.
   string Broker()         const { return m_broker; }
   long   AccountLogin()   const { return m_accountLogin; }
   string Symbol()         const { return m_symbol; }
   int    Digits()         const { return m_digits; }
   double TickSize()       const { return m_tickSize; }
   double Point()          const { return m_point; }
   double ContractSize()   const { return m_contractSize; }
   long   TickCount()      const { return m_tickCount; }
   long   TimeMscFirst()   const { return m_timeMscFirst; }
   long   TimeMscLast()    const { return m_timeMscLast; }
   long   CreatedAtMsc()   const { return m_createdAtMsc; }
   long   ClosedAtMsc()    const { return m_closedAtMsc; }
   long   TicksRead()      const { return m_ticksRead; }
   bool   HasMore()        const { return m_ticksRead < m_tickCount; }
};

#endif // MKS_ULTIMATE_CORE_DATA_CMKSTICKFILEREADER_MQH