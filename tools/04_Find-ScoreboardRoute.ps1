param(
  [string]$ProjectRoot = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$needles = @(
  "/api/scoreboard",
  "/scoreboard",
  "scoreboard",
  "router.get(",
  "buildScoreboard",
  "getScoreboard",
  "verify-chat.ps1",
  "verify-chat"
)

$files = Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object {
    $_.FullName -notmatch "\\node_modules\\" -and
    $_.FullName -match "\.(ts|js|ps1|mjs|cjs)$"
  }

$hits = New-Object System.Collections.Generic.List[object]
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

$priority = @($hits) | Where-Object {
  $_.file -match "\\server\\src\\" -or
  $_.file -match "\\server\\dist\\" -or
  $_.file -match "\\tools\\verify-chat\.ps1$" -or
  $_.file -match "\\routes?\\" -or
  $_.file -match "\\app\.ts$" -or
  $_.file -match "\\index\.ts$"
}

[pscustomobject]@{
  hitCountAll      = @($hits).Count
  hitCountPriority = @($priority).Count
  priorityHits     = ($priority | Select-Object -First 300)
} | ConvertTo-Json -Depth 6 | Write-Output