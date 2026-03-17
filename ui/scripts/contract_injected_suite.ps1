# contract_injected_suite.ps1 (v3)
# 목적:
# - injected_context + project_context(project_id/thread_id) + selected_pins 계약을 함께 회귀 테스트
# - 핵심: 서버가 project_id/thread_id를 top-level에서만 인정하는 케이스 대응
#
# Contract Schema v1 (테스트 기준, 서버/클라이언트 공통 기대):
# (A) 요청(payload) MUST include (top-level):
#   - project_id (string, non-empty)
#   - thread_id  (string, non-empty)
#   - injected_context (string, non-empty; anchor 포함 권장)
#   - project_context.project_context_summary (string, non-empty)
# (B) selected pins:
#   - selected_pins_ids: array (0..N)  // "present"는 배열 존재 여부
#   - selected_pins:     array (0..N)
# (C) 서버 응답(meta.core.contracts) MUST include booleans and counts:
#   - injected_context_enforced, project_context_enforced
#   - project_id_present, thread_id_present
#   - project_context_summary_present
#   - selected_pins_ids_present, selected_pins_present
#   - selected_pins_count (int)

$ErrorActionPreference = "Stop"

function Write-Json([object]$obj, [int]$depth = 12) {
  $obj | ConvertTo-Json -Depth $depth
}

function Fail([string]$msg) {
  Write-Host "FAIL: $msg" -ForegroundColor Red
  exit 1
}

function Assert-True([string]$name, $value) {
  if ($value -ne $true) { Fail "$name expected true, got: $value" }
}

function Assert-EqInt([string]$name, [int]$value, [int]$expected) {
  if ($value -ne $expected) { Fail "$name expected == $expected, got: $value" }
}

function Assert-AtLeast([string]$name, [int]$value, [int]$min) {
  if ($value -lt $min) { Fail "$name expected >= $min, got: $value" }
}

function Get-ContractsOrFail($resp) {
  if ($null -eq $resp) { Fail "response is null" }
  if ($null -eq $resp.meta) { Fail "response.meta missing" }
  if ($null -eq $resp.meta.core) { Fail "response.meta.core missing" }
  if ($null -eq $resp.meta.core.contracts) { Fail "response.meta.core.contracts missing" }
  return $resp.meta.core.contracts
}

function Preview-Content($resp) {
  try {
    $txt = ""
    if ($resp.content -is [string]) { $txt = $resp.content }
    elseif ($resp.content -is [System.Collections.IEnumerable]) {
      $first = @($resp.content)[0]
      $txt = ($first | ConvertTo-Json -Depth 8)
    }
    if ([string]::IsNullOrWhiteSpace($txt)) { return }
    if ($txt.Length -gt 240) { $txt = $txt.Substring(0,240) + "..." }
    Write-Host "OK content preview:" -ForegroundColor Green
    Write-Host $txt
  } catch {}
}

$baseUrl = "http://127.0.0.1:8000"
$uri = "$baseUrl/api/chat"

$provider = "deepseek"
$mode = "chat"

$injected = @"
[Injected Context]
- 계약 테스트용 컨텍스트입니다.
- 반드시 이 텍스트가 injected_context로 서버에 전달되어야 합니다.
- ANCHOR: orangebus42
"@.Trim()

function New-Pin([string]$id, [string]$title, [string]$text, [string]$projectId, [string]$threadId, [string]$msgId) {
  $now = [int][double]::Parse((Get-Date -UFormat %s))
  return @{
    id = $id
    type = "pin"
    title = $title
    text = $text
    tags = @("tagA","tagB")
    projectId = $projectId
    sourceThreadId = $threadId
    sourceMessageId = $msgId
    createdAt = $now
    updatedAt = $now
  }
}

function Invoke-Case(
  [string]$caseName,
  [hashtable]$body,
  [int]$expectedPinsCountMin,
  [Nullable[int]]$expectedPinsCountExact = $null
) {
  Write-Host ""
  Write-Host "=== CASE: $caseName ===" -ForegroundColor Cyan

  $resp = Invoke-RestMethod -Method Post -Uri $uri -ContentType "application/json" -Body (Write-Json $body)
  $contracts = Get-ContractsOrFail $resp

  Write-Host "OK contracts:" -ForegroundColor Green
  Write-Host (Write-Json $contracts 10)

  # 공통 MUST (Schema v1)
  Assert-True "injected_context_enforced"        $contracts.injected_context_enforced
  Assert-True "project_context_enforced"         $contracts.project_context_enforced
  Assert-True "project_id_present"               $contracts.project_id_present
  Assert-True "thread_id_present"                $contracts.thread_id_present
  Assert-True "project_context_summary_present"  $contracts.project_context_summary_present
  Assert-True "selected_pins_ids_present"        $contracts.selected_pins_ids_present
  Assert-True "selected_pins_present"            $contracts.selected_pins_present

  $count = 0
  try { $count = [int]$contracts.selected_pins_count } catch { $count = -999 }
  Assert-AtLeast "selected_pins_count" $count $expectedPinsCountMin
  if ($expectedPinsCountExact -ne $null) {
    Assert-EqInt "selected_pins_count" $count ([int]$expectedPinsCountExact)
  }

  Preview-Content $resp
  Write-Host "PASS CASE: $caseName" -ForegroundColor Green
}

# -----------------------
# CASE 1) baseline (핀 1개) - 기존 v2와 동일 의미
# -----------------------
$projectId1 = "p_contract_injected"
$threadId1  = "t_contract_injected"
$clientReq1 = "req_contract_" + [Guid]::NewGuid().ToString("N")

$pins1Ids = @("pin_1")
$pins1 = @(
  (New-Pin -id "pin_1" -title "Pin 1" -text "이것은 선택된 핀 1 입니다." -projectId $projectId1 -threadId $threadId1 -msgId "m1")
)

$body1 = @{
  client_request_id = $clientReq1
  project_id = $projectId1
  thread_id  = $threadId1
  mode       = $mode
  provider   = $provider
  messages   = @(@{ role="user"; content="contract injected suite test (baseline)" })
  injected_context    = $injected
  selected_pins_ids   = $pins1Ids
  selected_pins       = $pins1
  project_context = @{
    project_id = $projectId1
    thread_id  = $threadId1
    project_context_summary = "요약 테스트 (contract_injected_suite v3 baseline)"
  }
  context = @{
    project_context_summary = "요약 테스트 (contract_injected_suite v3 baseline)"
    selected_pins_ids = $pins1Ids
    selected_pins = $pins1
  }
}

Invoke-Case -caseName "baseline (pins=1)" -body $body1 -expectedPinsCountMin 1 -expectedPinsCountExact 1

# -----------------------
# CASE 2) pins = 0 (빈 배열) - "present"는 true여야 하고 count는 0이어야 함
# -----------------------
$projectId2 = "p_contract_injected"
$threadId2  = "t_contract_injected_empty_pins"
$clientReq2 = "req_contract_" + [Guid]::NewGuid().ToString("N")

$pins0Ids = @()
$pins0 = @()

$body2 = @{
  client_request_id = $clientReq2
  project_id = $projectId2
  thread_id  = $threadId2
  mode       = $mode
  provider   = $provider
  messages   = @(@{ role="user"; content="contract injected suite test (pins=0)" })
  injected_context    = $injected
  selected_pins_ids   = $pins0Ids
  selected_pins       = $pins0
  project_context = @{
    project_id = $projectId2
    thread_id  = $threadId2
    project_context_summary = "요약 테스트 (contract_injected_suite v3 pins=0)"
  }
  context = @{
    project_context_summary = "요약 테스트 (contract_injected_suite v3 pins=0)"
    selected_pins_ids = $pins0Ids
    selected_pins = $pins0
  }
}

Invoke-Case -caseName "pins=0 (empty arrays present)" -body $body2 -expectedPinsCountMin 0 -expectedPinsCountExact 0

# -----------------------
# CASE 3) pins = many (3개)
# -----------------------
$projectId3 = "p_contract_injected"
$threadId3  = "t_contract_injected_many_pins"
$clientReq3 = "req_contract_" + [Guid]::NewGuid().ToString("N")

$pinsManyIds = @("pin_1","pin_2","pin_3")
$pinsMany = @(
  (New-Pin -id "pin_1" -title "Pin 1" -text "선택된 핀 1" -projectId $projectId3 -threadId $threadId3 -msgId "m1"),
  (New-Pin -id "pin_2" -title "Pin 2" -text "선택된 핀 2" -projectId $projectId3 -threadId $threadId3 -msgId "m2"),
  (New-Pin -id "pin_3" -title "Pin 3" -text "선택된 핀 3" -projectId $projectId3 -threadId $threadId3 -msgId "m3")
)

$body3 = @{
  client_request_id = $clientReq3
  project_id = $projectId3
  thread_id  = $threadId3
  mode       = $mode
  provider   = $provider
  messages   = @(@{ role="user"; content="contract injected suite test (pins=3)" })
  injected_context    = $injected
  selected_pins_ids   = $pinsManyIds
  selected_pins       = $pinsMany
  project_context = @{
    project_id = $projectId3
    thread_id  = $threadId3
    project_context_summary = "요약 테스트 (contract_injected_suite v3 pins=3)"
  }
  context = @{
    project_context_summary = "요약 테스트 (contract_injected_suite v3 pins=3)"
    selected_pins_ids = $pinsManyIds
    selected_pins = $pinsMany
  }
}

Invoke-Case -caseName "pins=3 (many)" -body $body3 -expectedPinsCountMin 3

# -----------------------
# CASE 4) home -> thread 진입 시나리오(요지: 새 thread_id로 첫 요청도 계약 통과)
# - UI '홈'을 서버가 직접 알 수는 없으므로,
#   "새 스레드 첫 요청"을 동일 프로젝트 내 새로운 thread_id로 시뮬레이션.
# -----------------------
$projectId4 = "p_contract_injected"
$threadId4  = "t_contract_home_to_thread_first"
$clientReq4 = "req_contract_" + [Guid]::NewGuid().ToString("N")

$body4 = @{
  client_request_id = $clientReq4
  project_id = $projectId4
  thread_id  = $threadId4
  mode       = $mode
  provider   = $provider
  messages   = @(@{ role="user"; content="contract injected suite test (home->thread first message)" })
  injected_context    = $injected
  selected_pins_ids   = @()
  selected_pins       = @()
  project_context = @{
    project_id = $projectId4
    thread_id  = $threadId4
    project_context_summary = "요약 테스트 (contract_injected_suite v3 home->thread first)"
  }
  context = @{
    project_context_summary = "요약 테스트 (contract_injected_suite v3 home->thread first)"
    selected_pins_ids = @()
    selected_pins = @()
  }
}

Invoke-Case -caseName "home->thread (first request, pins=0)" -body $body4 -expectedPinsCountMin 0 -expectedPinsCountExact 0

# -----------------------
# CASE 5) thread 이동 시나리오(요지: 이동 직후 첫 요청도 계약 통과)
# - 같은 project_id에서 thread_id를 바꿔 연속 호출로 시뮬레이션
# -----------------------
$projectId5 = "p_contract_injected"
$threadA    = "t_contract_move_A"
$threadB    = "t_contract_move_B"

$clientReq5a = "req_contract_" + [Guid]::NewGuid().ToString("N")
$clientReq5b = "req_contract_" + [Guid]::NewGuid().ToString("N")

$body5a = @{
  client_request_id = $clientReq5a
  project_id = $projectId5
  thread_id  = $threadA
  mode       = $mode
  provider   = $provider
  messages   = @(@{ role="user"; content="contract injected suite test (before move: thread A)" })
  injected_context    = $injected
  selected_pins_ids   = @("pin_A1")
  selected_pins       = @(
    (New-Pin -id "pin_A1" -title "Pin A1" -text "이동 전 스레드 A 핀" -projectId $projectId5 -threadId $threadA -msgId "mA1")
  )
  project_context = @{
    project_id = $projectId5
    thread_id  = $threadA
    project_context_summary = "요약 테스트 (contract_injected_suite v3 move A)"
  }
  context = @{
    project_context_summary = "요약 테스트 (contract_injected_suite v3 move A)"
    selected_pins_ids = @("pin_A1")
    selected_pins = @(
      (New-Pin -id "pin_A1" -title "Pin A1" -text "이동 전 스레드 A 핀" -projectId $projectId5 -threadId $threadA -msgId "mA1")
    )
  }
}

$body5b = @{
  client_request_id = $clientReq5b
  project_id = $projectId5
  thread_id  = $threadB
  mode       = $mode
  provider   = $provider
  messages   = @(@{ role="user"; content="contract injected suite test (after move: thread B first request)" })
  injected_context    = $injected
  selected_pins_ids   = @()
  selected_pins       = @()
  project_context = @{
    project_id = $projectId5
    thread_id  = $threadB
    project_context_summary = "요약 테스트 (contract_injected_suite v3 move B first)"
  }
  context = @{
    project_context_summary = "요약 테스트 (contract_injected_suite v3 move B first)"
    selected_pins_ids = @()
    selected_pins = @()
  }
}

Invoke-Case -caseName "thread move (before move: A, pins=1)" -body $body5a -expectedPinsCountMin 1 -expectedPinsCountExact 1
Invoke-Case -caseName "thread move (after move: B first, pins=0)" -body $body5b -expectedPinsCountMin 0 -expectedPinsCountExact 0

Write-Host ""
Write-Host "PASS ALL: contract_injected_suite v3 (expanded regression cases)" -ForegroundColor Green
exit 0