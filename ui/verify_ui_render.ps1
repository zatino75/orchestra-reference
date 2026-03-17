Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$uiRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Section([string]$title) {
  Write-Host ""
  Write-Host ("==== " + $title + " ====")
}

Section "환경"
Write-Host ("UIRoot: " + $uiRoot)
Write-Host ("PWD: " + (Get-Location).Path)
Write-Host ("PSVersion: " + $PSVersionTable.PSVersion.ToString())

Section "ChatView.tsx 존재 여부"
$chatView = Join-Path $uiRoot "src\components\ChatView.tsx"
if (Test-Path -LiteralPath $chatView) { Write-Host "OK: src\components\ChatView.tsx" } else { throw "MISSING: src\components\ChatView.tsx" }

Section '"확인 필요." 문자열 검색'
$hits = Select-String -Path (Join-Path $uiRoot "src\**\*.ts*") -Pattern "확인 필요\." -List -ErrorAction SilentlyContinue
if ($null -eq $hits) {
  Write-Host "OK: 0건"
} else {
  $arr = @($hits)
  Write-Host ("FOUND: " + $arr.Length + " file(s)")
  $arr | ForEach-Object { Write-Host ("- " + $_.Path + ":" + $_.LineNumber) }
}

Section "ChatView.tsx 핵심 구현 체크(현재 코드 기준)"
$t = Get-Content -LiteralPath $chatView -Raw

$needles = @(
  "function buildProjectContext",
  "normalizeAssistantTurnsFromRaw",
  "ensureBlocksForTurn",
  "metaSummaryTableBlock",
  "fetch(""/api/chat""",
  """Content-Type"": ""application/json""",
  "project_context",
  "input_assets",
  "message: msg"
)

foreach ($n in $needles) {
  if ($t -match [regex]::Escape($n)) { Write-Host ("OK: " + $n) } else { Write-Host ("MISSING: " + $n) }
}

Write-Host ""
Write-Host "DONE"