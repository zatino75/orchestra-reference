Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path      # ...\orchestra\ui
$projectRoot = Split-Path -Parent $here                      # ...\orchestra
$atomic = Join-Path $projectRoot "scripts\write_atomic.ps1"
if (-not (Test-Path -LiteralPath $atomic)) { throw "missing: $atomic" }

# 생성할 verify 파일 경로(프로젝트 루트 기준)
$verifyRel = "ui\verify_ui_render.ps1"
$verifyAbs = Join-Path $projectRoot $verifyRel

# ✅ 중첩 here-string 금지: 줄 배열로 구성
$lines = @(
  'Set-StrictMode -Version Latest',
  '$ErrorActionPreference = "Stop"',
  '',
  '$uiRoot = Split-Path -Parent $MyInvocation.MyCommand.Path',
  '',
  'function Section([string]$title) {',
  '  Write-Host ""',
  '  Write-Host ("==== " + $title + " ====")',
  '}',
  '',
  'Section "환경"',
  'Write-Host ("UIRoot: " + $uiRoot)',
  'Write-Host ("PWD: " + (Get-Location).Path)',
  'Write-Host ("PSVersion: " + $PSVersionTable.PSVersion.ToString())',
  '',
  'Section "ChatView.tsx 존재 여부"',
  '$chatView = Join-Path $uiRoot "src\components\ChatView.tsx"',
  'if (Test-Path -LiteralPath $chatView) { Write-Host "OK: src\components\ChatView.tsx" } else { throw "MISSING: src\components\ChatView.tsx" }',
  '',
  'Write-Host ""',
  'Write-Host "DONE"'
)

$content = ($lines -join "`r`n") + "`r`n"

# ✅ 원자적 쓰기: 외부 pwsh 재실행 금지(경로 튐 리스크 제거) -> 현재 프로세스에서 직접 호출
& $atomic -TargetPath $verifyRel -Content $content
Write-Host ("OK: wrote " + $verifyAbs)

# 실행은 ui 기준으로 고정
Push-Location $here
try {
  pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here "verify_ui_render.ps1")
}
finally {
  Pop-Location
}