//+------------------------------------------------------------------+
//| @file           : CMksBrickFileReader.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Data
//| @responsibility : Lê arquivos .mksbk produzidos pelo writer. Valida
//|                   magic, formatVersion, recordSize, headerSize e
//|                   integridade (tamanho do arquivo == header + N*record).
//|                   Expõe proveniência via getters (ADR-013 §3).
//| @depends_on     : Core/Data/BrickFileFormat.mqh, Core/Types/Brick.mqh,
//|                   Core/Types/Error.mqh, Core/Types/RenkoGeometry.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Data/CMksBrickFileReader.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_DATA_CMKSBRICKFILEREADER_MQH
#define MKS_ULTIMATE_CORE_DATA_CMKSBRICKFILEREADER_MQH

#include <MKS-ULTIMATE/Core/Data/BrickFileFormat.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>

class CMksBrickFileReader
{
private:
   int    m_handle;
   bool   m_headerLoaded;
   long   m_bricksRead;

   // Campos do header
   string m_broker;
   long   m_accountLogin;
   string m_symbol;
   int    m_digits;
   MksRenkoGeometry m_geometry;
   double m_brickSizePoints;
   long   m_brickCount;
   long   m_timeMscFirst;
   long   m_timeMscLast;
   long   m_createdAtMsc;

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
   CMksBrickFileReader()
   {
      m_handle = INVALID_HANDLE;
      m_headerLoaded = false;
      m_bricksRead = 0;
      m_broker = ""; m_symbol = "";
      m_accountLogin = 0; m_digits = 0;
      m_brickSizePoints = 0.0;
      m_brickCount = 0; m_timeMscFirst = 0; m_timeMscLast = 0; m_createdAtMsc = 0;
   }

   ~CMksBrickFileReader()
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
      if(!ReadFixedString(MKS_BRICKFILE_MAGIC_SIZE, magic, err)) return false;
      if(StringCompare(magic, MKS_BRICKFILE_MAGIC) != 0)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_INVALID_MAGIC,
                       "magic inválido",
                       StringFormat("esperado=%s lido=%s",
                                    MKS_BRICKFILE_MAGIC, magic));
         return false;
      }

      // formatVersion + recordSize + headerSize
      int formatVersion = FileReadInteger(m_handle, 2);
      int recordSize    = FileReadInteger(m_handle, 2);
      int headerSize    = FileReadInteger(m_handle, 4);

      if(formatVersion != MKS_BRICKFILE_FORMAT_VERSION)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_UNSUPPORTED_VERSION,
                       "formatVersion não suportada",
                       StringFormat("lido=%d suportado=%d",
                                    formatVersion, MKS_BRICKFILE_FORMAT_VERSION));
         return false;
      }
      if(recordSize != MKS_BRICKFILE_RECORD_SIZE)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_HEADER_INVALID,
                       "recordSize inconsistente",
                       StringFormat("lido=%d esperado=%d",
                                    recordSize, MKS_BRICKFILE_RECORD_SIZE));
         return false;
      }
      if(headerSize != MKS_BRICKFILE_HEADER_SIZE)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_HEADER_INVALID,
                       "headerSize inconsistente",
                       StringFormat("lido=%d esperado=%d",
                                    headerSize, MKS_BRICKFILE_HEADER_SIZE));
         return false;
      }

      // broker, accountLogin, symbol
      if(!ReadFixedString(MKS_BRICKFILE_BROKER_SIZE, m_broker, err)) return false;
      m_accountLogin = FileReadLong(m_handle);
      if(!ReadFixedString(MKS_BRICKFILE_SYMBOL_SIZE, m_symbol, err)) return false;

      // digits + 7 bytes reserved (skip)
      m_digits = FileReadInteger(m_handle, 1);
      FileSeek(m_handle, 7, SEEK_CUR);

      // Geometria + brickSizePoints
      m_geometry.po           = FileReadDouble(m_handle);
      m_geometry.pro          = FileReadDouble(m_handle);
      m_geometry.revSizeRatio = FileReadDouble(m_handle);
      m_brickSizePoints       = FileReadDouble(m_handle);

      // brickCount, timeMscFirst, timeMscLast, createdAtMsc
      m_brickCount   = FileReadLong(m_handle);
      m_timeMscFirst = FileReadLong(m_handle);
      m_timeMscLast  = FileReadLong(m_handle);
      m_createdAtMsc = FileReadLong(m_handle);

      // Pula reserved2 até headerSize
      FileSeek(m_handle, MKS_BRICKFILE_HEADER_SIZE, SEEK_SET);

      // Validação de integridade: tamanho do arquivo == header + N*record
      ulong totalSize = FileSize(m_handle);
      ulong expected = (ulong)MKS_BRICKFILE_HEADER_SIZE
                     + (ulong)m_brickCount * (ulong)MKS_BRICKFILE_RECORD_SIZE;
      if(totalSize != expected)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_TRUNCATED,
                       "tamanho do arquivo inconsistente com brickCount",
                       StringFormat("size=%I64u expected=%I64u brickCount=%I64d",
                                    totalSize, expected, m_brickCount));
         return false;
      }

      m_headerLoaded = true;
      return true;
   }

   bool ReadNext(MksBrick &brick, MksError &err)
   {
      if(!m_headerLoaded)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID,
                       "ReadNext antes de Open bem-sucedido", "");
         return false;
      }
      if(m_bricksRead >= m_brickCount)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_TRUNCATED,
                       "ReadNext além de brickCount",
                       StringFormat("read=%I64d total=%I64d",
                                    m_bricksRead, m_brickCount));
         return false;
      }

      brick.direction        = (ENUM_MKS_BRICK_DIR)FileReadInteger(m_handle, 4);
      brick.thresholdsCrossed = FileReadInteger(m_handle, 4);
      brick.open             = FileReadDouble(m_handle);
      brick.close            = FileReadDouble(m_handle);
      brick.high             = FileReadDouble(m_handle);
      brick.low              = FileReadDouble(m_handle);
      brick.triggerPrice     = FileReadDouble(m_handle);
      brick.triggerTickId    = (ulong)FileReadLong(m_handle);
      brick.closeTimeMsc     = FileReadLong(m_handle);
      brick.volume           = FileReadLong(m_handle);

      m_bricksRead++;
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
   MksRenkoGeometry Geometry() const { return m_geometry; }
   double BrickSizePoints() const { return m_brickSizePoints; }
   long   BrickCount()     const { return m_brickCount; }
   long   TimeMscFirst()   const { return m_timeMscFirst; }
   long   TimeMscLast()    const { return m_timeMscLast; }
   long   CreatedAtMsc()   const { return m_createdAtMsc; }
   long   BricksRead()     const { return m_bricksRead; }
   bool   HasMore()        const { return m_bricksRead < m_brickCount; }
};

#endif // MKS_ULTIMATE_CORE_DATA_CMKSBRICKFILEREADER_MQH
