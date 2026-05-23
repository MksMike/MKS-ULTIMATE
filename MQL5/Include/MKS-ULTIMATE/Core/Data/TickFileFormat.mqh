//+------------------------------------------------------------------+
//| @file           : TickFileFormat.mqh
//| @project        : MKS-ULTIMATE
//| @module         : Core / Data
//| @responsibility : Constantes do formato binário .mkstick v1 de
//|                   persistência de ticks crus (header + records).
//|                   Layout fixo, versionado, broker-locked com
//|                   proveniência (ADR-012 §3, ADR-013 §3, ADR-024 §1).
//| @depends_on     : Nenhuma (autocontido)
//| @install_path   : MQL5/Include/MKS-ULTIMATE/Core/Data/TickFileFormat.mqh
//+------------------------------------------------------------------+
//
// Layout do arquivo .mkstick v1 (little-endian, sem padding entre campos):
//
// HEADER (256 bytes, dos quais 200 usados e 56 reservados zero-fill):
//   off  size  tipo     campo
//   ---  ----  -------  ---------------------------------------------
//     0     8  char[8]  magic = "MKSTK01" + '\0' (7 ASCII + 1 zero, ADR-024 §1)
//     8     2  uint16   formatVersion           (== 1 nesta versão)
//    10     2  uint16   tickRecordSize          (== 64 nesta versão)
//    12     4  uint32   headerSize              (== 256 nesta versão)
//    16    64  char[64] broker (UTF-8 zero-padded)
//    80     8  int64    accountLogin
//    88    32  char[32] symbol (UTF-8 zero-padded)
//   120     1  uint8    digits
//   121     7  bytes    reserved (zero-fill, alinha p/ 128)
//   128     8  double   tickSize     (snapshot do símbolo na abertura)
//   136     8  double   point        (snapshot do símbolo na abertura)
//   144     8  double   contractSize (snapshot do símbolo na abertura)
//   152     8  bytes    reserved (zero-fill, alinha p/ 160)
//   160     8  int64    tickCount    (patched no Close)
//   168     8  int64    timeMscFirst (timeMsc do 1º tick — do broker)
//   176     8  int64    timeMscLast  (timeMsc do último tick — do broker)
//   184     8  int64    createdAtMsc (TimeCurrent na abertura do writer)
//   192     8  int64    closedAtMsc  (TimeCurrent no Close — duração wall-clock)
//   200    56  bytes    reserved (zero-fill, header termina em 256)
//
// TICK RECORD (64 bytes, repetido `tickCount` vezes após o header):
//   off  size  tipo     campo
//   ---  ----  -------  ---------------------------------------------
//     0     8  uint64   seq
//     8     8  int64    timeMsc        (timestamp do broker, ms desde epoch)
//    16     8  double   bid
//    24     8  double   ask
//    32     8  double   last           (0 se broker não popular)
//    40     8  int64    volume
//    48     4  uint32   flags          (bitmask TICK_FLAG_* — ADR-012 §4)
//    52    12  bytes    reserved (zero-fill, alinha p/ 64 — espaço p/ v2)
//
// Tamanho total do arquivo = 256 + (64 * tickCount).
//
// Patching no Close: tickCount, timeMscFirst/Last, createdAtMsc e closedAtMsc
// são escritos no header somente quando o writer fecha o arquivo. Durante
// a escrita, esses campos no header ficam zerados.

#ifndef MKS_ULTIMATE_CORE_DATA_TICKFILEFORMAT_MQH
#define MKS_ULTIMATE_CORE_DATA_TICKFILEFORMAT_MQH

#define MKS_TICKFILE_MAGIC          "MKSTK01"
#define MKS_TICKFILE_MAGIC_SIZE     8
#define MKS_TICKFILE_FORMAT_VERSION 1
#define MKS_TICKFILE_HEADER_SIZE    256
#define MKS_TICKFILE_RECORD_SIZE    64
#define MKS_TICKFILE_BROKER_SIZE    64
#define MKS_TICKFILE_SYMBOL_SIZE    32

// Offsets dentro do header — único ponto que muda em revisões futuras.
#define MKS_TICKFILE_OFF_MAGIC           0
#define MKS_TICKFILE_OFF_FORMAT_VERSION  8
#define MKS_TICKFILE_OFF_RECORD_SIZE     10
#define MKS_TICKFILE_OFF_HEADER_SIZE     12
#define MKS_TICKFILE_OFF_BROKER          16
#define MKS_TICKFILE_OFF_ACCOUNT         80
#define MKS_TICKFILE_OFF_SYMBOL          88
#define MKS_TICKFILE_OFF_DIGITS          120
#define MKS_TICKFILE_OFF_TICK_SIZE       128
#define MKS_TICKFILE_OFF_POINT           136
#define MKS_TICKFILE_OFF_CONTRACT_SIZE   144
#define MKS_TICKFILE_OFF_TICK_COUNT      160
#define MKS_TICKFILE_OFF_TIME_FIRST      168
#define MKS_TICKFILE_OFF_TIME_LAST       176
#define MKS_TICKFILE_OFF_CREATED_AT      184
#define MKS_TICKFILE_OFF_CLOSED_AT       192

#endif // MKS_ULTIMATE_CORE_DATA_TICKFILEFORMAT_MQH