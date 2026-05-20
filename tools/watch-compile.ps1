# Watcher de compile incremental para MKS-ULTIMATE.
#
# Constrói o grafo reverso de #include uma vez no startup. Em cada save
# de .mqh em Core/ ou .mq5 em Scripts/MKS-ULTIMATE/, identifica os .mq5
# afetados e os compila via MetaEditor64.exe headless.
#
# Uso: powershell -ExecutionPolicy Bypass -File tools\watch-compile.ps1
#      Ctrl+C para sair.

param(
  [string]$Editor = "C:\Program Files\MetaTrader 5 EXNESS\MetaEditor64.exe",
  [int]$PollMs = 500
)

$ErrorActionPreference = "Stop"

$repoRoot    = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$includeRoot = Join-Path $repoRoot "MQL5\Include\MKS-ULTIMATE"
$scriptsRoot = Join-Path $repoRoot "MQL5\Scripts\MKS-ULTIMATE"

if (-not (Test-Path -LiteralPath $Editor)) {
  Write-Host "MetaEditor não encontrado em: $Editor" -ForegroundColor Red
  exit 1
}

function Get-IncludesFromFile([string]$file) {
  if (-not (Test-Path -LiteralPath $file)) { return @() }
  $content = Get-Content -LiteralPath $file -Raw -ErrorAction SilentlyContinue
  if ([string]::IsNullOrEmpty($content)) { return @() }
  $includeMatches = [regex]::Matches($content, '#include\s*<MKS-ULTIMATE/([^>]+)>')
  $result = @()
  foreach ($m in $includeMatches) {
    $rel = $m.Groups[1].Value -replace '/', '\'
    $result += (Join-Path $includeRoot $rel)
  }
  return $result
}

function Get-IncludeClosure([string]$entryFile) {
  $visited = New-Object 'System.Collections.Generic.HashSet[string]'
  $queue   = New-Object 'System.Collections.Generic.Queue[string]'
  [void]$queue.Enqueue($entryFile)
  while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    $key = $current.ToLowerInvariant()
    if (-not $visited.Add($key)) { continue }
    foreach ($inc in (Get-IncludesFromFile $current)) {
      if (Test-Path -LiteralPath $inc) { [void]$queue.Enqueue($inc) }
    }
  }
  return $visited
}

function Get-ReverseMap {
  $files = Get-ChildItem -Path $scriptsRoot -Recurse -Filter "*.mq5" -ErrorAction SilentlyContinue
  $map = @{}
  foreach ($mq5 in $files) {
    $closure = Get-IncludeClosure $mq5.FullName
    foreach ($mqh in $closure) {
      if ($mqh -ieq $mq5.FullName.ToLowerInvariant()) { continue }
      if (-not $map.ContainsKey($mqh)) { $map[$mqh] = @() }
      $map[$mqh] += $mq5.FullName
    }
  }
  return @{ Map = $map; EntryCount = $files.Count }
}

Write-Host "Construindo grafo de inclusões..."
$state = Get-ReverseMap
$reverseMap = $state.Map
Write-Host "  $($state.EntryCount) entry points, $($reverseMap.Count) headers mapeados."

function Get-AffectedTargets([string]$changedPath) {
  $key = $changedPath.ToLowerInvariant()
  if ($key.EndsWith(".mq5")) { return @($changedPath) }
  if ($reverseMap.ContainsKey($key)) { return $reverseMap[$key] }
  return @()
}

function Invoke-Compile([string]$mq5File) {
  $logFile = [System.IO.Path]::GetTempFileName()
  Start-Process -FilePath $Editor `
    -ArgumentList @("/compile:`"$mq5File`"", "/log:`"$logFile`"") `
    -Wait -WindowStyle Hidden | Out-Null

  $output = ""
  if (Test-Path -LiteralPath $logFile) {
    # MetaEditor escreve log em UTF-16 LE BOM; fallback p/ UTF-8 se vier vazio.
    try { $output = Get-Content -LiteralPath $logFile -Encoding Unicode -Raw } catch { }
    if ([string]::IsNullOrWhiteSpace($output)) {
      try { $output = Get-Content -LiteralPath $logFile -Encoding UTF8 -Raw } catch { }
    }
    Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
  }

  $errors = 0
  $warnings = 0
  $issueLines = @()
  foreach ($line in ($output -split "`r?`n")) {
    if ($line -match ':\s*(error|warning)\s') {
      if ($Matches[1] -eq 'error') { $errors++ } else { $warnings++ }
      $issueLines += $line.Trim()
    }
  }

  $name = Split-Path $mq5File -Leaf
  if ($errors -gt 0) {
    Write-Host "  X $name — $errors erro(s), $warnings warning(s)" -ForegroundColor Red
    foreach ($l in $issueLines) { Write-Host "    $l" -ForegroundColor DarkRed }
  } elseif ($warnings -gt 0) {
    Write-Host "  ! $name — 0 erros, $warnings warning(s)" -ForegroundColor Yellow
    foreach ($l in $issueLines) { Write-Host "    $l" -ForegroundColor DarkYellow }
  } else {
    Write-Host "  OK $name" -ForegroundColor Green
  }
}

$lastSeen = @{}
foreach ($p in @($includeRoot, $scriptsRoot)) {
  Get-ChildItem -Path $p -Recurse -Include "*.mqh","*.mq5" -ErrorAction SilentlyContinue | ForEach-Object {
    $lastSeen[$_.FullName] = $_.LastWriteTimeUtc
  }
}

Write-Host ""
Write-Host "Watch ativo:"
Write-Host "  $includeRoot"
Write-Host "  $scriptsRoot"
Write-Host "Editor: $Editor"
Write-Host "Ctrl+C para sair."
Write-Host ""

while ($true) {
  Start-Sleep -Milliseconds $PollMs
  $changes = @()
  foreach ($p in @($includeRoot, $scriptsRoot)) {
    Get-ChildItem -Path $p -Recurse -Include "*.mqh","*.mq5" -ErrorAction SilentlyContinue | ForEach-Object {
      $prev = $lastSeen[$_.FullName]
      if ($null -eq $prev -or $_.LastWriteTimeUtc -gt $prev) {
        $changes += $_.FullName
        $lastSeen[$_.FullName] = $_.LastWriteTimeUtc
      }
    }
  }
  if ($changes.Count -eq 0) { continue }

  # Rebuild a cada ciclo com mudanças — captura .mqh novos ou #include adicionados.
  $reverseMap = (Get-ReverseMap).Map

  $targets = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($c in $changes) {
    foreach ($t in (Get-AffectedTargets $c)) { [void]$targets.Add($t) }
  }
  if ($targets.Count -eq 0) { continue }

  $changedNames = ($changes | ForEach-Object { Split-Path $_ -Leaf }) -join ", "
  Write-Host "[$(Get-Date -Format 'HH:mm:ss')] mudou: $changedNames" -ForegroundColor Cyan
  foreach ($t in $targets) { Invoke-Compile $t }
}
