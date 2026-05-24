# tools/compile-all.ps1
#
# Compila todos os .mq5 do MKS-ULTIMATE via MetaEditor64 headless e
# reporta consolidado. Util para sanity check pre-commit ou CI futuro.
#
# Diferente do watch-compile.ps1 (que assiste mudancas e compila
# incrementalmente), este roda uma vez e sai. Util quando se quer
# garantir que TUDO compila apos um refactor amplo.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File tools\compile-all.ps1
#
# Parametros:
#   -Editor       Path do MetaEditor64.exe
#                 (default: C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe)
#   -TerminalRoot Path do terminal data path (onde estao as junctions p/
#                 MQL5\Include\MKS-ULTIMATE, etc.).
#                 (auto-detecta via %APPDATA%\MetaQuotes\Terminal\)
#   -Quiet        Suprime saida arquivo-a-arquivo (so summary)
#
# Exit codes:
#   0 = todos compilaram com 0 erros e 0 warnings
#   1 = algum arquivo teve erro de compile
#   2 = algum arquivo teve warning (mas nenhum erro)
#   3 = erro de setup (MetaEditor nao encontrado, terminal root invalido)

param(
  [string]$Editor       = "C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe",
  [string]$TerminalRoot = "",
  [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Write-Header([string]$msg) {
  Write-Host ""
  Write-Host "=== $msg ===" -ForegroundColor Cyan
}
function Write-Ok([string]$msg)   { Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "  !   $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg) { Write-Host "  X   $msg" -ForegroundColor Red }
function Write-Info([string]$msg) { Write-Host "      $msg" -ForegroundColor DarkGray }

#------------------------------------------------------------------#
# 1. Validar inputs / auto-detectar terminal data path
#------------------------------------------------------------------#
Write-Header "compile-all (sanity check via MetaEditor64 headless)"

if (-not (Test-Path -LiteralPath $Editor)) {
  Write-Fail "MetaEditor nao encontrado em: $Editor"
  Write-Info "Passe o path via -Editor"
  exit 3
}

if ($TerminalRoot -eq "") {
  # Procura o data path que tem o junction MKS-ULTIMATE em MQL5\Include
  $terminalsRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
  if (-not (Test-Path -LiteralPath $terminalsRoot)) {
    Write-Fail "MetaQuotes Terminal nao encontrado em: $terminalsRoot"
    exit 3
  }
  $candidates = Get-ChildItem -LiteralPath $terminalsRoot -Directory `
    | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "MQL5\Include\MKS-ULTIMATE") }
  if ($candidates.Count -eq 0) {
    Write-Fail "Nenhum terminal data path com junction MQL5\Include\MKS-ULTIMATE encontrado"
    Write-Info "Passe o path explicitamente via -TerminalRoot"
    exit 3
  }
  $TerminalRoot = $candidates[0].FullName
}

if (-not (Test-Path -LiteralPath $TerminalRoot)) {
  Write-Fail "Terminal data path nao encontrado: $TerminalRoot"
  exit 3
}

Write-Info "Editor       = $Editor"
Write-Info "TerminalRoot = $TerminalRoot"

#------------------------------------------------------------------#
# 2. Lista todos os .mq5 do MKS-ULTIMATE (Experts, Services, Scripts,
#    Indicators). Cada root tem um junction para o repo, entao os
#    arquivos sao os mesmos do branch corrente.
#------------------------------------------------------------------#
$roots = @(
  @{ rel = "MQL5\Experts\MKS-ULTIMATE"; label = "Experts"    },
  @{ rel = "MQL5\Services\MKS-ULTIMATE"; label = "Services"  },
  @{ rel = "MQL5\Scripts\MKS-ULTIMATE"; label = "Scripts"    },
  @{ rel = "MQL5\Indicators\MKS-ULTIMATE"; label = "Indicators" }
)

$allFiles = @()
foreach ($r in $roots) {
  $absRoot = Join-Path $TerminalRoot $r.rel
  if (-not (Test-Path -LiteralPath $absRoot)) {
    Write-Warn "$($r.label) root nao encontrado: $absRoot (pulando)"
    continue
  }
  $found = Get-ChildItem -Path $absRoot -Recurse -Include "*.mq5" -ErrorAction SilentlyContinue
  foreach ($f in $found) {
    $allFiles += @{
      label = $r.label
      full  = $f.FullName
      rel   = $f.FullName.Substring($TerminalRoot.Length + 1)  # path relativo p/ MetaEditor
      name  = $f.Name
    }
  }
}

if ($allFiles.Count -eq 0) {
  Write-Fail "Nenhum .mq5 encontrado em qualquer root"
  exit 3
}

Write-Info "Total de .mq5 a compilar: $($allFiles.Count)"

#------------------------------------------------------------------#
# 3. Compila cada arquivo via MetaEditor64 /compile + /log.
#    MetaEditor escreve log em UTF-16 LE BOM; fallback p/ UTF-8.
#------------------------------------------------------------------#
function Invoke-Compile([string]$relPath) {
  $logFile = [System.IO.Path]::GetTempFileName()
  $absLog  = "$logFile"
  $procArgs = @("/compile:`"$relPath`"", "/log:`"$absLog`"")

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  Push-Location $TerminalRoot
  try {
    Start-Process -FilePath $Editor -ArgumentList $procArgs -Wait -WindowStyle Hidden | Out-Null
  } finally {
    Pop-Location
  }
  $sw.Stop()

  $output = ""
  if (Test-Path -LiteralPath $absLog) {
    try { $output = Get-Content -LiteralPath $absLog -Encoding Unicode -Raw } catch { }
    if ([string]::IsNullOrWhiteSpace($output)) {
      try { $output = Get-Content -LiteralPath $absLog -Encoding UTF8 -Raw } catch { }
    }
    Remove-Item -LiteralPath $absLog -Force -ErrorAction SilentlyContinue
  }

  $errors   = 0
  $warnings = 0
  $issues   = @()
  foreach ($line in ($output -split "`r?`n")) {
    if ($line -match ':\s*(error|warning)\s') {
      if ($Matches[1] -eq 'error') { $errors++ } else { $warnings++ }
      $issues += $line.Trim()
    }
  }

  return @{
    errors   = $errors
    warnings = $warnings
    issues   = $issues
    elapsed  = $sw.ElapsedMilliseconds
  }
}

#------------------------------------------------------------------#
# 4. Loop principal
#------------------------------------------------------------------#
Write-Header "compilando $($allFiles.Count) arquivo(s)"

$totalErrors   = 0
$totalWarnings = 0
$failedFiles   = @()
$warnedFiles   = @()
$totalElapsed  = 0

foreach ($f in $allFiles) {
  $r = Invoke-Compile $f.rel
  $totalElapsed  += $r.elapsed
  $totalErrors   += $r.errors
  $totalWarnings += $r.warnings

  if ($r.errors -gt 0) {
    $failedFiles += $f.name
    Write-Fail ("{0,-50} {1} erro(s), {2} warning(s), {3}ms" -f $f.name, $r.errors, $r.warnings, $r.elapsed)
    if (-not $Quiet) {
      foreach ($l in $r.issues) { Write-Host "        $l" -ForegroundColor DarkRed }
    }
  } elseif ($r.warnings -gt 0) {
    $warnedFiles += $f.name
    Write-Warn ("{0,-50} 0 erros, {1} warning(s), {2}ms" -f $f.name, $r.warnings, $r.elapsed)
    if (-not $Quiet) {
      foreach ($l in $r.issues) { Write-Host "        $l" -ForegroundColor DarkYellow }
    }
  } else {
    if (-not $Quiet) {
      Write-Ok ("{0,-50} 0/0 ({1}ms)" -f $f.name, $r.elapsed)
    }
  }
}

#------------------------------------------------------------------#
# 5. Summary + exit code
#------------------------------------------------------------------#
Write-Header "summary"
$totalSec = [Math]::Round($totalElapsed / 1000.0, 1)
Write-Info "arquivos compilados: $($allFiles.Count)"
Write-Info "tempo total:         $totalSec s"
Write-Info "erros totais:        $totalErrors"
Write-Info "warnings totais:     $totalWarnings"
Write-Host ""

if ($totalErrors -gt 0) {
  Write-Fail "FALHA — $($failedFiles.Count) arquivo(s) com erro:"
  foreach ($n in $failedFiles) { Write-Host "        $n" -ForegroundColor DarkRed }
  exit 1
}
if ($totalWarnings -gt 0) {
  Write-Warn "WARNINGS — $($warnedFiles.Count) arquivo(s):"
  foreach ($n in $warnedFiles) { Write-Host "        $n" -ForegroundColor DarkYellow }
  exit 2
}

Write-Ok "TODOS COMPILAM LIMPOS"
exit 0
