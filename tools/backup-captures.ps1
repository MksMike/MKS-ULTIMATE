# tools/backup-captures.ps1
#
# Backup dos dados de captura do MKS-ULTIMATE (.mkstick / .mksbk / .log)
# para FORA da arvore do terminal MT5. Esses dados sao insubstituiveis
# (o tick feed nao se recaptura) e vivem so em MQL5\Files\MKS-ULTIMATE\,
# que e gitignorado e mora dentro do terminal — a desinstalacao do MT5
# em 2026-07-19 mostrou que a arvore do terminal pode sumir.
#
# Usa robocopy /MIR (espelha) por pasta. Idempotente — rodar de novo so
# copia o que mudou. Nao agenda nada; para diario, aponte o Task
# Scheduler para este script.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tools\backup-captures.ps1
#   powershell ... -Dest "D:\OneDrive\MKS-DATA"
#
# Parametros:
#   -Dest         Destino do backup (default: C:\dev\MKS-DATA)
#   -TerminalRoot Data path do terminal (auto-detecta via a junction)
#
# Exit codes:  0 = ok (incl. "nada novo")   3 = erro de setup

param(
  [string]$Dest         = "C:\dev\MKS-DATA",
  [string]$TerminalRoot = ""
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$m) { Write-Host "      $m" -ForegroundColor DarkGray }
function Write-Ok([string]$m)   { Write-Host "  OK  $m" -ForegroundColor Green }
function Write-Fail([string]$m) { Write-Host "  X   $m" -ForegroundColor Red }

Write-Host ""
Write-Host "=== backup-captures (.mkstick / .mksbk / .log) ===" -ForegroundColor Cyan

# Auto-detecta o terminal com a junction MKS-ULTIMATE (mesma logica do
# compile-all.ps1).
if ($TerminalRoot -eq "") {
  $terminalsRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
  if (-not (Test-Path -LiteralPath $terminalsRoot)) {
    Write-Fail "MetaQuotes Terminal nao encontrado em: $terminalsRoot"; exit 3
  }
  $cand = Get-ChildItem -LiteralPath $terminalsRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "MQL5\Files\MKS-ULTIMATE") }
  if ($cand.Count -eq 0) {
    Write-Fail "Nenhum terminal com MQL5\Files\MKS-ULTIMATE encontrado (nada capturado ainda?)."
    Write-Info "Passe o path via -TerminalRoot se o terminal estiver em outro lugar."
    exit 3
  }
  $TerminalRoot = $cand[0].FullName
}

$src = Join-Path $TerminalRoot "MQL5\Files\MKS-ULTIMATE"
if (-not (Test-Path -LiteralPath $src)) {
  Write-Fail "Origem nao encontrada: $src"; exit 3
}

Write-Info "origem  = $src"
Write-Info "destino = $Dest"

if (-not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }

# robocopy /MIR espelha; /XO nao — queremos preservar tudo, incluindo
# capturas antigas que ja sairam do terminal. Por isso NAO usamos /MIR
# (que apagaria no destino o que sumiu na origem). /E copia subarvore,
# /XN /XO /XC evita re-copiar identicos, /R:2 /W:5 tolera lock transitorio.
$roboArgs = @($src, $Dest, "/E", "/XN", "/XO", "/XC", "/R:2", "/W:5", "/NFL", "/NDL", "/NP")
robocopy @roboArgs | Out-Null
$code = $LASTEXITCODE

# robocopy: 0 = nada copiado; 1 = arquivos copiados; >=8 = erro real.
if ($code -ge 8) {
  Write-Fail "robocopy retornou codigo $code (erro). Verifique permissoes/lock."
  exit 3
}
if ($code -eq 0) { Write-Ok "backup em dia - nada novo para copiar." }
else             { Write-Ok "backup atualizado (robocopy code $code)." }
Write-Info "Dica: aponte o Task Scheduler para este script para backup diario."
exit 0
