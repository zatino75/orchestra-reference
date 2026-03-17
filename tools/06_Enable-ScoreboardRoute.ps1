param(
  [string]$ProjectRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-AtomicUtf8 {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Text
  )

  $dir = Split-Path -LiteralPath $Path -Parent
  if (-not (Test-Path -LiteralPath $dir)) { throw "Parent dir not found: $dir" }

  $tmp = Join-Path $dir (".tmp_" + [Guid]::NewGuid().ToString("n") + "_" + (Split-Path -Leaf $Path))
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($tmp, $Text, $utf8NoBom)
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}

$indexPath = Join-Path $ProjectRoot "server\src\index.ts"

# 수정 전 상태 체크(필수)
$it = Get-Item -LiteralPath $indexPath -ErrorAction Stop
$raw = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8

[pscustomobject]@{
  file = $it.FullName
  length = $it.Length
  lastWriteTime = $it.LastWriteTime
} | ConvertTo-Json -Depth 4 | Write-Output

$importLine = 'import apiScoreboardRouter from "./routes/apiScoreboard.js";'
$mountLine  = 'app.use("/api", apiScoreboardRouter);'

$changed = $false
$new = $raw

# 1) import 주입(이미 있으면 스킵)
if ($new -notmatch "apiScoreboardRouter") {
  $lines = $new -split "`r?`n"
  $lastImport = -1
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "^\s*import\s+") { $lastImport = $i; continue }
    if ($lastImport -ge 0) { break }
  }
  if ($lastImport -lt 0) { throw "No import block found in index.ts" }

  $out = New-Object System.Collections.Generic.List[string]
  for ($i=0; $i -lt $lines.Count; $i++) {
    $out.Add($lines[$i]) | Out-Null
    if ($i -eq $lastImport) { $out.Add($importLine) | Out-Null }
  }
  $new = ($out -join "`n")
  $changed = $true
}

# 2) mount 주입(이미 있으면 스킵)
if ($new -notmatch [regex]::Escape($mountLine)) {
  $lines = $new -split "`r?`n"
  $insertAt = -1

  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'app\.use\("?/api/promote"?,') { $insertAt = $i + 1; break }
  }
  if ($insertAt -lt 0) {
    for ($i=0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match 'app\.use\("?/api/chat"?,') { $insertAt = $i + 1; break }
    }
  }
  if ($insertAt -lt 0) {
    for ($i=0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match 'app\.use\(express\.json') { $insertAt = $i + 1; break }
    }
  }
  if ($insertAt -lt 0) { throw "Could not find insertion point for mount line in index.ts" }

  $out = New-Object System.Collections.Generic.List[string]
  for ($i=0; $i -lt $lines.Count; $i++) {
    if ($i -eq $insertAt) { $out.Add($mountLine) | Out-Null }
    $out.Add($lines[$i]) | Out-Null
  }
  $new = ($out -join "`n")
  $changed = $true
}

if (-not $changed) {
  [pscustomobject]@{ ok = $true; changed = $false; note = "index.ts already contains apiScoreboardRouter import/mount" } |
    ConvertTo-Json -Depth 4 | Write-Output
  exit 0
}

Write-AtomicUtf8 -Path $indexPath -Text $new

$it2 = Get-Item -LiteralPath $indexPath -ErrorAction Stop
[pscustomobject]@{
  ok = $true
  changed = $true
  file = $it2.FullName
  length = $it2.Length
  lastWriteTime = $it2.LastWriteTime
} | ConvertTo-Json -Depth 4 | Write-Output