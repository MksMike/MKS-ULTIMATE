# tools/verify-parity.ps1
#
# Valida paridade bit-a-bit entre uma sessão live do Producer e uma
# reconstrução via Replayer sobre o .mkstick capturado em paralelo.
# Materializa ADR-024 §regra 7.
#
# Pipeline canônico (executado pelo operador antes de rodar este script):
#   (a) Rodar Producer em chart real por >=1h → gera live.mksbk + live.log
#   (b) Rodar TickRecorder em Service em paralelo → gera live.mkstick
#   (c) Rodar Replayer (EA em qualquer chart, com InpTickFilePath=live.mkstick)
#       → gera replay.mksbk + replay.log
#
# Este script:
#   1. Compara live.mksbk vs replay.mksbk byte-a-byte (fc /b)
#   2. Reporta primeira divergência em caso de falha
#   3. Reporta tamanho/contagem de bricks em sucesso
#   4. (Opcional) Compara linhas de decisão dos logs quando flag passado
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

# Normaliza para Windows-style backslashes — `fc` recusa `/`.
$LiveMksbk   = (Resolve-Path -LiteralPath $LiveMksbk).Path
$ReplayMksbk = (Resolve-Path -LiteralPath $ReplayMksbk).Path

Write-Info "live   = $LiveMksbk"
Write-Info "replay = $ReplayMksbk"

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
# 3. Comparação byte-a-byte via fc /b. fc é nativo Windows e retorna
#    exit 0 em igualdade, !=0 em divergência. Saída inclui o offset
#    da primeira divergência.
#------------------------------------------------------------------#
Write-Header "fc /b live.mksbk replay.mksbk"

$fcOutput = & cmd /c "fc /b `"$LiveMksbk`" `"$ReplayMksbk`"" 2>&1
$fcExit   = $LASTEXITCODE

if ($fcExit -eq 0) {
  Write-Ok "byte-a-byte IDÊNTICOS ($liveSize bytes, ~$([Math]::Round(($liveSize - 256) / 72.0)) bricks)"
} else {
  Write-Fail "byte-a-byte DIVERGEM (fc exit=$fcExit)"
  Write-Host ""
  Write-Host "Primeiras divergências reportadas pelo fc:" -ForegroundColor Yellow
  Write-Host $fcOutput -ForegroundColor DarkYellow
  Write-Host ""
  Write-Info "Offsets do header (.mksbk): 0-255 header, 256+ records de 72 bytes."
  Write-Info "Divergência em offset < 256 = metadata (header, proveniência, geometry)."
  Write-Info "Divergência em offset >= 256 = brick data (open/high/low/close, seq, time)."
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
