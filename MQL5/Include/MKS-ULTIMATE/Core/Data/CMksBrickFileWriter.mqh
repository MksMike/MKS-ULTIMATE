//+------------------------------------------------------------------+
//| @file           : CMksBrickFileWriter.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Data
//| @responsibility : Serializa MksBrick em arquivo .mksbk com header
//|                   de proveniência (broker, conta, símbolo, geometria).
//|                   Layout em BrickFileFormat.mqh. Padrão broker-locked
//|                   conforme ADR-012 §3 e ADR-013 §3.
//| @depends_on     : Core/Data/BrickFileFormat.mqh, Core/Types/Brick.mqh,
//|                   Core/Types/Error.mqh, Core/Types/RenkoGeometry.mqh
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Data/CMksBrickFileWriter.mqh
//+------------------------------------------------------------------+
#ifndef MKS_ULTIMATE_CORE_DATA_CMKSBRICKFILEWRITER_MQH
#define MKS_ULTIMATE_CORE_DATA_CMKSBRICKFILEWRITER_MQH

#include <MKS-ULTIMATE/Core/Data/BrickFileFormat.mqh>
#include <MKS-ULTIMATE/Core/Types/Brick.mqh>
#include <MKS-ULTIMATE/Core/Types/Error.mqh>
#include <MKS-ULTIMATE/Core/Types/RenkoGeometry.mqh>

// Padrão de uso:
//   CMksBrickFileWriter w;
//   if(!w.Open("MKS-ULTIMATE/run1.mksbk", err)) return;
//   if(!w.WriteHeader(broker, account, symbol, digits, geom, sizePts, err)) {...}
//   for each brick: w.WriteBrick(brick, err);
//   w.Close(err); // patcheia header com brickCount + timeMscFirst/Last + createdAt
//
// WriteHeader grava um header com brickCount=0 e times zerados; Close
// faz seek de volta e sobrescreve esses campos com os valores reais.
class CMksBrickFileWriter
{
private:
   int    m_handle;
   long   m_brickCount;
   long   m_timeMscFirst;
   long   m_timeMscLast;
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
   CMksBrickFileWriter()
   {
      m_handle = INVALID_HANDLE;
      m_brickCount = 0;
      m_timeMscFirst = 0; m_timeMscLast = 0;
      m_hasFirst = false;
      m_headerWritten = false;
      m_closed = false;
   }

   ~CMksBrickFileWriter()
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
      // FILE_READ|FILE_WRITE permite seek + patch do header no Close.
      m_handle = FileOpen(path, FILE_READ | FILE_WRITE | FILE_BIN);
      if(m_handle == INVALID_HANDLE)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_FILE_IO, "FileOpen falhou",
                       StringFormat("path=%s LastError=%d", path, GetLastError()));
         return false;
      }
      return true;
   }

   bool WriteHeader(const string &broker, long accountLogin,
                    const string &symbol, int digits,
                    const MksRenkoGeometry &geom, double brickSizePoints,
                    MksError &err)
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

      // Magic — 8 bytes ASCII
      if(!WriteFixedString(MKS_BRICKFILE_MAGIC, MKS_BRICKFILE_MAGIC_SIZE, err))
         return false;

      // formatVersion (uint16), brickRecordSize (uint16), headerSize (uint32)
      FileWriteInteger(m_handle, MKS_BRICKFILE_FORMAT_VERSION, 2);
      FileWriteInteger(m_handle, MKS_BRICKFILE_RECORD_SIZE,    2);
      FileWriteInteger(m_handle, MKS_BRICKFILE_HEADER_SIZE,    4);

      // broker (64), accountLogin (8), symbol (32)
      if(!WriteFixedString(broker, MKS_BRICKFILE_BROKER_SIZE, err)) return false;
      FileWriteLong(m_handle, accountLogin);
      if(!WriteFixedString(symbol, MKS_BRICKFILE_SYMBOL_SIZE, err)) return false;

      // digits (1) + 7 bytes reserved
      FileWriteInteger(m_handle, digits, 1);
      if(!WriteZeros(7, err)) return false;

      // Geometria + brick size (4 doubles)
      FileWriteDouble(m_handle, geom.po);
      FileWriteDouble(m_handle, geom.pro);
      FileWriteDouble(m_handle, geom.revSizeRatio);
      FileWriteDouble(m_handle, brickSizePoints);

      // brickCount, timeMscFirst, timeMscLast, createdAtMsc — placeholders (0)
      // patched no Close.
      FileWriteLong(m_handle, 0);
      FileWriteLong(m_handle, 0);
      FileWriteLong(m_handle, 0);
      FileWriteLong(m_handle, 0);

      // Reserved até 256 bytes
      ulong pos = FileTell(m_handle);
      int remaining = MKS_BRICKFILE_HEADER_SIZE - (int)pos;
      if(remaining < 0)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_HEADER_INVALID,
                       "header excedeu tamanho previsto",
                       StringFormat("pos=%I64u expected=%d", pos, MKS_BRICKFILE_HEADER_SIZE));
         return false;
      }
      if(remaining > 0 && !WriteZeros(remaining, err)) return false;

      m_headerWritten = true;
      return true;
   }

   bool WriteBrick(const MksBrick &brick, MksError &err)
   {
      if(!m_headerWritten || m_closed)
      {
         MKS_SET_ERROR(err, MKS_ERR_DATA_STATE_INVALID,
                       "WriteBrick antes do header ou em writer fechado", "");
         return false;
      }

      FileWriteInteger(m_handle, (int)brick.direction,    4);
      FileWriteInteger(m_handle, brick.thresholdsCrossed, 4);
      FileWriteDouble(m_handle,  brick.open);
      FileWriteDouble(m_handle,  brick.close);
      FileWriteDouble(m_handle,  brick.high);
      FileWriteDouble(m_handle,  brick.low);
      FileWriteDouble(m_handle,  brick.triggerPrice);
      FileWriteLong(m_handle,    (long)brick.triggerTickId);
      FileWriteLong(m_handle,    brick.closeTimeMsc);
      FileWriteLong(m_handle,    brick.volume);

      m_brickCount++;
      if(!m_hasFirst)
      {
         m_timeMscFirst = brick.closeTimeMsc;
         m_hasFirst = true;
      }
      m_timeMscLast = brick.closeTimeMsc;
      return true;
   }

   // createdAtMscOverride < 0 => usa TimeCurrent (produção). Valor explícito
   // permite golden file test reproduzível byte-a-byte.
   bool Close(MksError &err, long createdAtMscOverride = -1)
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

      long createdAt = (createdAtMscOverride >= 0)
                       ? createdAtMscOverride
                       : (long)TimeCurrent() * 1000;

      // Patch dos campos dinâmicos do header.
      FileSeek(m_handle, MKS_BRICKFILE_OFF_BRICK_COUNT, SEEK_SET);
      FileWriteLong(m_handle, m_brickCount);
      FileWriteLong(m_handle, m_timeMscFirst);
      FileWriteLong(m_handle, m_timeMscLast);
      FileWriteLong(m_handle, createdAt);

      FileClose(m_handle);
      m_handle = INVALID_HANDLE;
      m_closed = true;
      return true;
   }

   long BrickCount() const { return m_brickCount; }
};

#endif // MKS_ULTIMATE_CORE_DATA_CMKSBRICKFILEWRITER_MQH
