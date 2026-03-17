Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Section([string]$t){ Write-Host ""; Write-Host "==== $t ====" }

$root = (Get-Location).Path
$chatView = Join-Path $root "src\components\ChatView.tsx"
$types = Join-Path $root "src\types\chat.ts"
$validator = Join-Path $root "src\lib\validateChatResponse.ts"

Section "환경"
Write-Host ("PWD: " + $root)
Write-Host ("PSVersion: " + $PSVersionTable.PSVersion.ToString())

Section "필수 파일"
if (Test-Path -LiteralPath $chatView) { Write-Host "OK: src/components/ChatView.tsx" } else { throw "MISSING: ChatView.tsx" }
if (Test-Path -LiteralPath $types) { Write-Host "OK: src/types/chat.ts" } else { throw "MISSING: src/types/chat.ts" }
if (Test-Path -LiteralPath $validator) { Write-Host "OK: src/lib/validateChatResponse.ts" } else { throw "MISSING: validator ts" }

$cv = Get-Content -LiteralPath $chatView -Raw
$ty = Get-Content -LiteralPath $types -Raw
$vd = Get-Content -LiteralPath $validator -Raw

Section "요청 계약 체크 (/api/chat body) - 현재 구현 기준"
if ($cv -match 'fetch\("/api/chat"' ) { Write-Host 'OK: fetch("/api/chat")' } else { Write-Host "FAIL: fetch(/api/chat) not found" }

# body: JSON.stringify({ ... }) 블록을 최대한 좁혀서 검사(오탐 방지)
$bodyBlock = $null
$reBody = [regex]::new('body\s*:\s*JSON\.stringify\s*\(\s*\{\s*(?<inner>[\s\S]*?)\s*\}\s*\)\s*,?', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$mBody = $reBody.Match($cv)
if ($mBody.Success) {
  $bodyBlock = $mBody.Groups["inner"].Value
  Write-Host "OK: located body: JSON.stringify({ ... })"
} else {
  Write-Host "FAIL: cannot locate body: JSON.stringify({ ... })"
  $bodyBlock = $cv  # fallback (전체에서라도 찾기)
}

# message: msg
if ($bodyBlock -match '\bmessage\s*:\s*msg\b' -or $bodyBlock -match '"message"\s*:\s*msg') {
  Write-Host "OK: body.message = msg"
} else {
  Write-Host "FAIL: body.message = msg not found"
}

# input_assets: freshInputAssets
if ($bodyBlock -match '\binput_assets\s*:\s*freshInputAssets\b' -or $bodyBlock -match '"input_assets"\s*:\s*freshInputAssets') {
  Write-Host "OK: body.input_assets = freshInputAssets"
} else {
  Write-Host "FAIL: body.input_assets mapping not found"
}

# project_context: (1) explicit mapping OR (2) shorthand "project_context,"
# - shorthand는 "project_context" 단독 키가 콤마/끝괄호로 닫히는 형태를 허용
if (
  ($bodyBlock -match '\bproject_context\s*:\s*project_context\b') -or
  ($bodyBlock -match '"project_context"\s*:\s*project_context') -or
  ($bodyBlock -match '(?<!\.)\bproject_context\b\s*(?:,|\})')
) {
  Write-Host "OK: body.project_context present (explicit or shorthand)"
} else {
  Write-Host "FAIL: body.project_context not found (explicit/shorthand)"
}

# prompt/mode는 현재 UI에서 사용하지 않는 것이 정상
if ($bodyBlock -match '\bprompt\s*:' ) { Write-Host "FAIL: request body includes prompt (unexpected)" } else { Write-Host "OK: no prompt in request body" }
if ($bodyBlock -match '\bmode\s*:' ) { Write-Host "WARN: request body includes mode (not required currently)" } else { Write-Host "OK: no mode in request body (expected)" }

Section "타입 정의 체크 (src/types/chat.ts) - 현재 파일 기준"
$need = @("export type Intent","export type ContentBlock","export type ChatRequest","export type ChatResponse")
foreach ($n in $need) {
  if ($ty -match [regex]::Escape($n)) { Write-Host ("OK: " + $n) } else { Write-Host ("FAIL: missing " + $n) }
}

Section "런타임 스키마 검증 적용 여부"
if ($cv -match "validateChatApiResponse") { Write-Host "OK: validateChatApiResponse used" } else { Write-Host "FAIL: validateChatApiResponse not used" }

Section "validator import/type sanity"
if ($vd -match 'import\s+type\s+\{\s*ChatResponse\s+as\s+ChatApiResponse\s*\}' ) { Write-Host "OK: validator imports ChatResponse as ChatApiResponse" } else { Write-Host "FAIL: validator import type mapping not found" }

Write-Host ""
Write-Host "DONE"