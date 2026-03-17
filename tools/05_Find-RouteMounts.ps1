param(
  [string]$ProjectRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$serverSrc = Join-Path $ProjectRoot "server\src"

$needles = @(
  "apiScoreboard",
  "apiScoreboardRouter",
  "debugRoutes",
  "apiChat",
  "router",
  "app.use(",
  "express()",
  "listen(",
  "createServer"
)

$files = Get-ChildItem -LiteralPath $serverSrc -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match "\.(ts|js)$" }

$hits = New-Object "System.Collections.Generic.List[object]"
foreach ($n in $needles) {
  $m = $files | Select-String -Pattern $n -SimpleMatch -ErrorAction SilentlyContinue
  foreach ($x in $m) {
    $hits.Add([pscustomobject]@{
      needle = $n
      file   = $x.Path
      line   = $x.LineNumber
      text   = $x.Line.Trim()
    }) | Out-Null
  }
}

# 마운트/엔트리 후보 라인만 우선
$mountHits = $hits.ToArray() | Where-Object {
  $_.text -match "app\.use\(" -or
  $_.text -match "import .*apiScoreboard" -or
  $_.text -match "from .*apiScoreboard" -or
  $_.text -match "apiScoreboardRouter" -or
  $_.text -match "listen\(" -or
  $_.text -match "express\(\)"
}

$grouped = $mountHits |
  Group-Object file |
  ForEach-Object {
    [pscustomobject]@{
      file  = $_.Name
      count = $_.Count
      hits  = ($_.Group | Sort-Object line | Select-Object -First 80)
    }
  } |
  Sort-Object count -Descending

[pscustomobject]@{
  serverSrc = $serverSrc
  filesScanned = @($files).Count
  mountHitFiles = $grouped
} | ConvertTo-Json -Depth 10 | Write-Output