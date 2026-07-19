# tools/verify-parity.ps1
#
# Valida paridade bit-a-bit entre uma sessão live do Producer e uma
# reconstrução via Replayer sobre o .mkstick capturado em paralelo.
# Materializa ADR-024 §regra 7 (com refinamento da nota de esclarecimento
# 2026-05-24 sobre timestamps wall-clock no header).
#
# Pipeline canônico (executado pelo operador antes de rodar este script):
#   (a) Rodar Producer em chart real por >=1h → gera live.mksbk + live.log
#   (b) Rodar TickRecorder em Service em paralelo → gera live.mkstick
#   (c) Rodar Replayer (EA em qualquer chart, com InpTickFilePath=live.mkstick)
#       → gera replay.mksbk + replay.log
#
# Este script:
#   1. Compara live.mksbk vs replay.mksbk byte-a-byte, IGNORANDO o range
#      wall-clock do header (offset 184-191 = createdAtMsc, que vale o
#      momento do Close do writer — inerentemente diferente entre live
#      e replay).
#   2. Reporta primeira divergência com offset + interpretação
#      (header field, brick #N, campo qual) em caso de falha.
#   3. Reporta tamanho/contagem de bricks em sucesso.
#   4. (Opcional) Compara linhas de decisão dos logs quando flag passado.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tools\verify-parity.ps1 `
#     -LiveMksbk path\to\live.mksbk -ReplayMksbk path\to\replay.mksbk
#
#   # Opcional — comparar logs também:
#   powershell ... -LiveLog path\to\live.log -ReplayLog path\to\replay.log
#
# Exit codes:
#   0 = paridade verificada
#   1 = divergência detectada no .mksbk
#   2 = divergência detectada nos logs
#   3 = arquivo de entrada não encontrado / erro de argumentos

param(
  [Parameter(Mandatory=$true)][string]$LiveMksbk,
  [Parameter(Mandatory=$true)][string]$ReplayMksbk,
  [string]$LiveLog   = "",
  [string]$ReplayLog = ""
)

$ErrorActionPreference = "Stop"

function Write-Header([string]$msg) {
  Write-Host ""
  Write-Host "=== $msg ===" -ForegroundColor Cyan
}

function Write-Ok([string]$msg)    { Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Fail([string]$msg)  { Write-Host "  X   $msg" -ForegroundColor Red }
function Write-Info([string]$msg)  { Write-Host "      $msg" -ForegroundColor DarkGray }

#------------------------------------------------------------------#
# 1. Validar inputs
#------------------------------------------------------------------#
Write-Header "verify-parity (ADR-024 §regra 7)"

if (-not (Test-Path -LiteralPath $LiveMksbk)) {
  Write-Fail "live.mksbk não encontrado: $LiveMksbk"
  exit 3
}
if (-not (Test-Path -LiteralPath $ReplayMksbk)) {
  Write-Fail "replay.mksbk não encontrado: $ReplayMksbk"
  exit 3
}

$LiveMksbk   = (Resolve-Path -LiteralPath $LiveMksbk).Path
$ReplayMksbk = (Resolve-Path -LiteralPath $ReplayMksbk).Path

Write-Info "live   = $LiveMksbk"
Write-Info "replay = $ReplayMksbk"

#------------------------------------------------------------------#
# Constantes do layout .mksbk (espelham Core/Data/BrickFileFormat.mqh).
# Mantenha sincronizado se o formato mudar.
#------------------------------------------------------------------#
$MKSBK_HEADER_SIZE  = 256
$MKSBK_RECORD_SIZE  = 72
$MKSBK_OFF_CREATED  = 184   # int64 — TimeCurrent na hora do Close (wall-clock)
$MKSBK_CREATED_LEN  = 8

# Tabela de campos do header para diagnóstico de divergência.
$headerFieldMap = @(
  @{ off =   0; len =  8; name = "magic"           },
  @{ off =   8; len =  2; name = "formatVersion"   },
  @{ off =  10; len =  2; name = "brickRecordSize" },
  @{ off =  12; len =  4; name = "headerSize"      },
  @{ off =  16; len = 64; name = "broker"          },
  @{ off =  80; len =  8; name = "accountLogin"    },
  @{ off =  88; len = 32; name = "symbol"          },
  @{ off = 120; len =  1; name = "digits"          },
  @{ off = 128; len =  8; name = "geometryPO"      },
  @{ off = 136; len =  8; name = "geometryPRO"     },
  @{ off = 144; len =  8; name = "geometryRevSizeRatio" },
  @{ off = 152; len =  8; name = "brickSizePoints" },
  @{ off = 160; len =  8; name = "brickCount"      },
  @{ off = 168; len =  8; name = "timeMscFirst"    },
  @{ off = 176; len =  8; name = "timeMscLast"     },
  @{ off = 184; len =  8; name = "createdAtMsc (wall-clock — IGNORADO)" }
)

# Tabela de campos do record (72 bytes). Offset relativo ao início do record.
$recordFieldMap = @(
  @{ off =  0; len = 4; name = "direction"         },
  @{ off =  4; len = 4; name = "thresholdsCrossed" },
  @{ off =  8; len = 8; name = "open"              },
  @{ off = 16; len = 8; name = "close"             },
  @{ off = 24; len = 8; name = "high"              },
  @{ off = 32; len = 8; name = "low"               },
  @{ off = 40; len = 8; name = "triggerPrice"      },
  @{ off = 48; len = 8; name = "triggerTickId"     },
  @{ off = 56; len = 8; name = "closeTimeMsc"      },
  @{ off = 64; len = 8; name = "volume"            }
)

function Identify-Offset([int]$offset, [int]$headerSize, [int]$recordSize) {
  if ($offset -lt $headerSize) {
    foreach ($f in $headerFieldMap) {
      $fStart = [int]$f.off
      $fEnd   = $fStart + [int]$f.len
      if ($offset -ge $fStart -and $offset -lt $fEnd) {
        $fName = [string]$f.name
        return "header." + $fName + " (offset " + $fStart + ", len " + [int]$f.len + ")"
      }
    }
    return "header reserved (offset " + $offset + ")"
  }
  $brickIdx = [Math]::Floor(($offset - $headerSize) / $recordSize)
  $inRec    = ($offset - $headerSize) % $recordSize
  foreach ($f in $recordFieldMap) {
    $fStart = [int]$f.off
    $fEnd   = $fStart + [int]$f.len
    if ($inRec -ge $fStart -and $inRec -lt $fEnd) {
      $fName = [string]$f.name
      return "brick[" + $brickIdx + "]." + $fName + " (record offset " + $fStart + ", len " + [int]$f.len + ")"
    }
  }
  return "brick[" + $brickIdx + "] reserved (record offset " + $inRec + ")"
}

#------------------------------------------------------------------#
# 2. Tamanho comparado primeiro — divergência de tamanho é diagnóstico
#    rápido antes do byte-a-byte custoso.
#------------------------------------------------------------------#
$liveSize   = (Get-Item -LiteralPath $LiveMksbk).Length
$replaySize = (Get-Item -LiteralPath $ReplayMksbk).Length

Write-Info "live   size = $liveSize bytes"
Write-Info "replay size = $replaySize bytes"

if ($liveSize -ne $replaySize) {
  Write-Fail "tamanhos divergem: delta = $($replaySize - $liveSize) bytes"
  Write-Info "Cada brick = 72 bytes; header = 256 bytes."
  $brickDeltaApprox = [Math]::Round(($replaySize - $liveSize) / 72.0, 2)
  Write-Info "delta em bricks (estimado) = $brickDeltaApprox"
  exit 1
}

#------------------------------------------------------------------#
# 3. Comparação byte-a-byte com janela de exclusão para timestamps
#    wall-clock. O range 184-191 do header (.mksbk createdAtMsc) carrega
#    o TimeCurrent no momento do Close — diferente entre live (Producer
#    fecha quando operador desanexa) e replay (Replayer fecha em EOF).
#    Esses 8 bytes divergem inerentemente. Resto deve ser idêntico.
#------------------------------------------------------------------#
Write-Header "comparação byte-a-byte (ignorando wall-clock no header)"

$liveBytes   = [System.IO.File]::ReadAllBytes($LiveMksbk)
$replayBytes = [System.IO.File]::ReadAllBytes($ReplayMksbk)

$firstDiverge = -1
$diffCount    = 0
$ignoreStart  = $MKSBK_OFF_CREATED
$ignoreEnd    = $MKSBK_OFF_CREATED + $MKSBK_CREATED_LEN

for ($i = 0; $i -lt $liveBytes.Length; $i++) {
  if ($i -ge $ignoreStart -and $i -lt $ignoreEnd) { continue } # range wall-clock
  if ($liveBytes[$i] -ne $replayBytes[$i]) {
    if ($firstDiverge -lt 0) { $firstDiverge = $i }
    $diffCount++
  }
}

if ($diffCount -eq 0) {
  $brickCount = [Math]::Round(($liveSize - $MKSBK_HEADER_SIZE) / $MKSBK_RECORD_SIZE)
  Write-Ok "byte-a-byte IDÊNTICOS ($liveSize bytes, $brickCount bricks; wall-clock ignorado)"
} else {
  $field = Identify-Offset $firstDiverge $MKSBK_HEADER_SIZE $MKSBK_RECORD_SIZE
  Write-Fail "DIVERGEM em $diffCount byte(s)"
  Write-Info "primeira divergência: offset $firstDiverge"
  Write-Info "campo identificado:   $field"

  # Mostra os bytes em hex (12 ao redor do ponto de divergência).
  $rangeStart = [Math]::Max(0, $firstDiverge - 4)
  $rangeEnd   = [Math]::Min($liveBytes.Length - 1, $firstDiverge + 7)
  $liveHex    = ""
  $replayHex  = ""
  for ($i = $rangeStart; $i -le $rangeEnd; $i++) {
    $marker     = if ($i -eq $firstDiverge) { "[" } else { " " }
    $liveHex   += "$marker{0:X2}" -f $liveBytes[$i]
    $replayHex += "$marker{0:X2}" -f $replayBytes[$i]
  }
  Write-Host "      live   bytes: $liveHex" -ForegroundColor DarkYellow
  Write-Host "      replay bytes: $replayHex" -ForegroundColor DarkYellow
  Write-Host ""
  Write-Info "Divergência em campo do header = problema de metadata"
  Write-Info "  (proveniência, geometry, brickSize, brickCount, timeMscFirst/Last)."
  Write-Info "Divergência em campo de brick = não-determinismo do builder OU"
  Write-Info "  feed divergente (.mkstick != ticks reais que o Producer viu)."
  exit 1
}

#------------------------------------------------------------------#
# 4. Comparação opcional de logs — só roda se -LiveLog e -ReplayLog
#    passados.
#------------------------------------------------------------------#
if ($LiveLog -ne "" -and $ReplayLog -ne "") {
  Write-Header "diff logs (chaves de decisão da estratégia)"

  if (-not (Test-Path -LiteralPath $LiveLog)) {
    Write-Fail "live.log não encontrado: $LiveLog"
    exit 3
  }
  if (-not (Test-Path -LiteralPath $ReplayLog)) {
    Write-Fail "replay.log não encontrado: $ReplayLog"
    exit 3
  }

  # Para esta fase (sem estratégia ainda), o "decision" relevante é a
  # cadeia de eventos do builder: bricks emitidos, erros 102/103/104.
  # Filtra linhas com "msg":"brick" ou erros do builder.
  # Quando a estratégia entrar, expandir o filtro para incluir
  # "decision":"buy"/"sell"/"close"/etc.
  $pattern = '"msg":"(brick|invalid tick|threshold limit|stream corrupt|ingest error)'

  $liveDecisions   = Select-String -LiteralPath $LiveLog   -Pattern $pattern -SimpleMatch:$false | ForEach-Object { $_.Line }
  $replayDecisions = Select-String -LiteralPath $ReplayLog -Pattern $pattern -SimpleMatch:$false | ForEach-Object { $_.Line }

  # Normaliza: remove "ts" e "sessionStartMsc" (diferem inerentemente
  # entre live e replay), mantém o resto.
  $normalize = {
    param($line)
    $line = [regex]::Replace($line, '"ts":"[^"]*",', '')
    $line = [regex]::Replace($line, '"sessionStartMsc":\d+,?', '')
    return $line
  }
  $liveNorm   = $liveDecisions   | ForEach-Object { & $normalize $_ }
  $replayNorm = $replayDecisions | ForEach-Object { & $normalize $_ }

  Write-Info "live   decisões = $($liveNorm.Count) linhas"
  Write-Info "replay decisões = $($replayNorm.Count) linhas"

  # Passe vácuo (M18, auditoria 2026-07-19): se o padrão não casa NADA em
  # ambos os logs, o log-diff não prova paridade — reportar "IDÊNTICOS
  # (0 decisões)" seria falso-OK. Chave do JSON renomeada, sessão sem
  # bricks, ou filtro desatualizado. Trata como falha, nunca sucesso.
  if ($liveNorm.Count -eq 0 -and $replayNorm.Count -eq 0) {
    Write-Fail "0 linhas casaram o padrão de decisão em AMBOS os logs — nada a comparar (passe vácuo)."
    Write-Info "Pattern: $pattern"
    Write-Info "(chave do JSON renomeada? sessão sem bricks? filtro desatualizado?)"
    exit 2
  }

  if ($liveNorm.Count -ne $replayNorm.Count) {
    Write-Fail "contagens divergem: live=$($liveNorm.Count) replay=$($replayNorm.Count)"
    exit 2
  }

  $divergences = 0
  for ($i = 0; $i -lt $liveNorm.Count; $i++) {
    if ($liveNorm[$i] -ne $replayNorm[$i]) {
      $divergences++
      if ($divergences -le 3) {
        Write-Fail "linha $i divergente:"
        Write-Host "  live  : $($liveNorm[$i])"   -ForegroundColor DarkRed
        Write-Host "  replay: $($replayNorm[$i])" -ForegroundColor DarkRed
      }
    }
  }
  if ($divergences -eq 0) {
    Write-Ok "logs IDÊNTICOS após normalização ($($liveNorm.Count) decisões)"
  } else {
    Write-Fail "$divergences divergências (acima 3 omitidas)"
    exit 2
  }
}

#------------------------------------------------------------------#
# 5. Sucesso total.
#------------------------------------------------------------------#
Write-Header "PARIDADE VERIFICADA"
Write-Ok "live e replay produzem o mesmo .mksbk byte-a-byte"
if ($LiveLog -ne "" -and $ReplayLog -ne "") {
  Write-Ok "decisões do builder coincidem no log estruturado"
}
Write-Host ""
exit 0
