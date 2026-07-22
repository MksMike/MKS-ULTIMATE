//+------------------------------------------------------------------+
//| @file           : BrickFileFormat.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Data
//| @responsibility : Constantes do formato binário .mksbk de
//|                   persistência de bricks (header + records).
//|                   Layout fixo, versionado, broker-locked com
//|                   proveniência (ADR-012 §5, ADR-013 §3).
//| @depends_on     : Nenhuma (autocontido)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Data/BrickFileFormat.mqh
//+------------------------------------------------------------------+
//
// Layout do arquivo .mksbk v1 (little-endian, sem padding entre campos):
//
// HEADER (256 bytes, dos quais 200 usados e 56 reservados zero-fill):
//   off  size  tipo     campo
//   ---  ----  -------  ---------------------------------------------
//     0     8  char[8]  magic = "MKSBRK01"
//     8     2  uint16   formatVersion           (== 1 nesta versão)
//    10     2  uint16   brickRecordSize         (== 72 nesta versão)
//    12     4  uint32   headerSize              (== 256 nesta versão)
//    16    64  char[64] broker (UTF-8 zero-padded)
//    80     8  int64    accountLogin
//    88    32  char[32] symbol (UTF-8 zero-padded)
//   120     1  uint8    digits
//   121     7  bytes    reserved (zero-fill, alinha p/ 128)
//   128     8  double   geometryPO
//   136     8  double   geometryPRO
//   144     8  double   geometryRevSizeRatio
//   152     8  double   brickSizePoints
//   160     8  int64    brickCount
//   168     8  int64    timeMscFirst (close do 1º brick)
//   176     8  int64    timeMscLast  (close do último brick)
//   184     8  int64    createdAtMsc (TimeCurrent na hora do Close)
//   192    64  bytes    reserved (zero-fill, header termina em 256)
//
// BRICK RECORD (72 bytes, repetido `brickCount` vezes após o header):
//   off  size  tipo     campo
//   ---  ----  -------  ---------------------------------------------
//     0     4  int32    direction (ENUM_MKS_BRICK_DIR: -1=BEAR, 1=BULL)
//     4     4  int32    thresholdsCrossed
//     8     8  double   open
//    16     8  double   close
//    24     8  double   high
//    32     8  double   low
//    40     8  double   triggerPrice
//    48     8  uint64   triggerTickId
//    56     8  int64    closeTimeMsc
//    64     8  int64    volume
//
// Tamanho total do arquivo = 256 + (72 * brickCount).
//
// Patching no Close: brickCount e timeMscFirst/Last/createdAtMsc são
// escritos no header somente quando o writer fecha o arquivo. Durante
// a escrita, esses campos no header ficam zerados.

#ifndef MKS_ULTIMATE_CORE_DATA_BRICKFILEFORMAT_MQH
#define MKS_ULTIMATE_CORE_DATA_BRICKFILEFORMAT_MQH

#define MKS_BRICKFILE_MAGIC          "MKSBRK01"
#define MKS_BRICKFILE_MAGIC_SIZE     8
#define MKS_BRICKFILE_FORMAT_VERSION 1
#define MKS_BRICKFILE_HEADER_SIZE    256
#define MKS_BRICKFILE_RECORD_SIZE    72
#define MKS_BRICKFILE_BROKER_SIZE    64
#define MKS_BRICKFILE_SYMBOL_SIZE    32

// Offsets dentro do header — único ponto que muda em revisões futuras.
#define MKS_BRICKFILE_OFF_MAGIC           0
#define MKS_BRICKFILE_OFF_FORMAT_VERSION  8
#define MKS_BRICKFILE_OFF_RECORD_SIZE     10
#define MKS_BRICKFILE_OFF_HEADER_SIZE     12
#define MKS_BRICKFILE_OFF_BROKER          16
#define MKS_BRICKFILE_OFF_ACCOUNT         80
#define MKS_BRICKFILE_OFF_SYMBOL          88
#define MKS_BRICKFILE_OFF_DIGITS          120
#define MKS_BRICKFILE_OFF_GEOM_PO         128
#define MKS_BRICKFILE_OFF_GEOM_PRO        136
#define MKS_BRICKFILE_OFF_GEOM_REVRATIO   144
#define MKS_BRICKFILE_OFF_BRICK_SIZE_PTS  152
#define MKS_BRICKFILE_OFF_BRICK_COUNT     160
#define MKS_BRICKFILE_OFF_TIME_FIRST      168
#define MKS_BRICKFILE_OFF_TIME_LAST       176
#define MKS_BRICKFILE_OFF_CREATED_AT      184

#endif // MKS_ULTIMATE_CORE_DATA_BRICKFILEFORMAT_MQH
