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
  [string]$LiveMksbk   = "",
  [string]$ReplayMksbk = "",
  [string]$JournalA    = "",   # E2.1: decision journal TSV (run A / golden)
  [string]$JournalB    = "",   # E2.1: decision journal TSV (run B / replay)
  [string]$LiveLog     = "",
  [string]$ReplayLog   = ""
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
Write-Header "verify-parity (ADR-024 §regra 7 + E2.1 decision journal)"

# Modos de comparação: cada par é independente. .mksbk = paridade
# feed->brick (existente); JournalA/B = determinismo da DECISÃO (E2.1,
# sim<->sim: runner<->runner ou runner<->golden); Log = diff dos bricks
# no log estruturado (existente). Sem nenhum par válido não há o que
# provar — falha (nunca "OK" no vazio).
$doMksbk   = ($LiveMksbk -ne "" -and $ReplayMksbk -ne "")
$doJournal = ($JournalA  -ne "" -and $JournalB    -ne "")
$doLog     = ($LiveLog   -ne "" -and $ReplayLog   -ne "")

if (-not ($doMksbk -or $doJournal)) {
  Write-Fail "nada a comparar: passe -LiveMksbk/-ReplayMksbk (bricks) e/ou -JournalA/-JournalB (decision journal)."
  exit 3
}

if ($doMksbk) {

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

} # fim if ($doMksbk)

#------------------------------------------------------------------#
# 3b. Diff do DECISION JOURNAL (E2.1) — stream de ORDENS determinístico.
#     Compara dois decision journals TSV (CMksDecisionJournal). É o
#     sucessor do log-diff stub da seção 4: onde aquele filtrava linhas
#     de brick do .log, este compara o oráculo de paridade da DECISÃO.
#     Semântica sim<->sim (reframe E2): runner<->runner (determinismo) ou
#     runner<->golden (regressão). NÃO é live-broker<->replay — essa
#     paridade é estruturalmente impossível (o SL real dispara em ticks
#     que o sim não reproduz); ver docs/CHECKPOINT-2026-07-20-sessao.md §4.
#------------------------------------------------------------------#
if ($doJournal) {
  Write-Header "diff decision journal (E2.1 — stream de ordens, determinismo da decisão)"

  if (-not (Test-Path -LiteralPath $JournalA)) { Write-Fail "journal A não encontrado: $JournalA"; exit 3 }
  if (-not (Test-Path -LiteralPath $JournalB)) { Write-Fail "journal B não encontrado: $JournalB"; exit 3 }

  $JournalA = (Resolve-Path -LiteralPath $JournalA).Path
  $JournalB = (Resolve-Path -LiteralPath $JournalB).Path
  Write-Info "journalA = $JournalA"
  Write-Info "journalB = $JournalB"

  # Descarta linhas de comentário '#' (header do bundle pinado + rodapé
  # '# total='): o header carrega proveniência que PODE diferir e é
  # assertado à parte no E2.3; o que prova a paridade da decisão são as
  # linhas de dados + o cabeçalho de colunas. @() força array mesmo com
  # 0/1 linha.
  $linesA = @(Get-Content -LiteralPath $JournalA | Where-Object { $_ -notmatch '^\s*#' -and $_ -ne "" })
  $linesB = @(Get-Content -LiteralPath $JournalB | Where-Object { $_ -notmatch '^\s*#' -and $_ -ne "" })

  # Linhas de DECISÃO = não-comentário e não o cabeçalho de colunas ('ord\t...').
  $dataA = @($linesA | Where-Object { $_ -notmatch '^ord\t' })
  $dataB = @($linesB | Where-Object { $_ -notmatch '^ord\t' })

  Write-Info "journalA = $($dataA.Count) linhas de decisão"
  Write-Info "journalB = $($dataB.Count) linhas de decisão"

  # Passe vácuo (herda a guarda M18/E0.4): 0 decisões em AMBOS não prova
  # determinismo nenhum — sessão sem flip, journal não aberto, ou config
  # que nunca opera. Falha, nunca "OK".
  if ($dataA.Count -eq 0 -and $dataB.Count -eq 0) {
    Write-Fail "0 linhas de decisão em AMBOS os journals — nada a comparar (passe vácuo)."
    Write-Info "(sessão sem flip? runner não abriu o journal? config que nunca opera?)"
    exit 2
  }

  if ($linesA.Count -ne $linesB.Count) {
    Write-Fail "contagens divergem: A=$($linesA.Count) B=$($linesB.Count) (linhas não-comentário)"
    exit 2
  }

  $divergences = 0
  $firstDiff   = -1
  for ($i = 0; $i -lt $linesA.Count; $i++) {
    if ($linesA[$i] -ne $linesB[$i]) {
      if ($firstDiff -lt 0) { $firstDiff = $i }
      $divergences++
      if ($divergences -le 3) {
        Write-Fail "linha $i divergente:"
        Write-Host "  A: $($linesA[$i])" -ForegroundColor DarkRed
        Write-Host "  B: $($linesB[$i])" -ForegroundColor DarkRed
      }
    }
  }
  if ($divergences -eq 0) {
    Write-Ok "decision journals IDÊNTICOS ($($dataA.Count) decisões; header/rodapé ignorados)"
  } else {
    Write-Fail "$divergences linha(s) divergente(s) (1a em $firstDiff; acima de 3 omitidas)"
    exit 2
  }
}

#------------------------------------------------------------------#
# 4. Comparação opcional de logs — só roda se -LiveLog e -ReplayLog
#    passados.
#------------------------------------------------------------------#
if ($doLog) {
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
if ($doMksbk)   { Write-Ok "live e replay produzem o mesmo .mksbk byte-a-byte" }
if ($doJournal) { Write-Ok "decision journals idênticos no stream de ordens (determinismo da decisão)" }
if ($doLog)     { Write-Ok "decisões do builder coincidem no log estruturado" }
Write-Host ""
exit 0
