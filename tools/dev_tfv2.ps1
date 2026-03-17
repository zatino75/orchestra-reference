# 파워셀덮어쓰기
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Chat {
  param(
    [Parameter(Mandatory=$true)][string]$Base,
    [Parameter(Mandatory=$true)][hashtable]$BodyObj
  )
  $json = $BodyObj | ConvertTo-Json -Depth 50
  return Invoke-RestMethod -Method Post -Uri ("{0}/api/chat" -f $Base) -ContentType "application/json" -Body $json
}

function Assert-Bool {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][bool]$Actual,
    [Parameter(Mandatory=$true)][bool]$Expected
  )
  if ($Actual -ne $Expected) {
    throw ("[ASSERT FAIL] {0}: expected={1} actual={2}" -f $Name, $Expected, $Actual)
  }
  Write-Host ("[PASS] {0}" -f $Name)
}

function Test-TFV2SummaryFusion {
  param(
    [Parameter(Mandatory=$true)][string]$Base,
    [Parameter(Mandatory=$true)][string]$ProjectId,
    [Parameter(Mandatory=$true)][string]$ThreadId
  )

  # 0) healthz
  $hz = Invoke-RestMethod -Method Get -Uri ("{0}/healthz" -f $Base)
  if (-not $hz.ok) { throw "core healthz failed" }
  Write-Host ("[OK] healthz service={0} uptime_s={1}" -f $hz.service, $hz.uptime_s)

  # 1) summary 저장(테스트 고정 값)
  $summary = "TFV2_SUMMARY_DEMO: 이 스레드의 요약을 기반으로 자동 융합하고, 앵커 토큰을 답변에 포함해야 합니다."
  $saveBody = @{
    project_id = $ProjectId
    thread_id  = $ThreadId
    summary    = $summary
    source     = "test"
  } | ConvertTo-Json -Depth 20
  $saveResp = Invoke-RestMethod -Method Post -Uri ("{0}/api/thread/summary/save" -f $Base) -ContentType "application/json" -Body $saveBody
  if (-not $saveResp.ok) { throw "summary save failed" }
  Write-Host "[OK] summary saved"

  # 2) TEST A: intent-only (selected_pins_ids 없음) => summary 주입되어야 함
  $respA = Invoke-Chat -Base $Base -BodyObj @{
    project_id = $ProjectId
    thread_id  = $ThreadId
    messages = @(
      @{ role="user"; content="저번 내용 참고해서 한 줄로 요약해줘. 앵커 토큰도 그대로 포함해." }
    )
  }

  Write-Host "=== TEST A contracts ==="
  ($respA.meta.core.contracts | ConvertTo-Json -Depth 30) | Write-Host
  Write-Host "=== TEST A debug ==="
  ($respA.meta.orchestra.debug | ConvertTo-Json -Depth 30) | Write-Host
  Write-Host "=== TEST A content ==="
  ($respA.content | ConvertTo-Json -Depth 30) | Write-Host

  Assert-Bool -Name "A enforced"   -Actual ([bool]$respA.meta.core.contracts.injected_context_enforced) -Expected $true
  Assert-Bool -Name "A anchor_hit" -Actual ([bool]$respA.meta.core.contracts.injected_context_anchor_hit) -Expected $true

  # 3) TEST B: no-intent => 주입되면 안 됨
  $respB = Invoke-Chat -Base $Base -BodyObj @{
    project_id = $ProjectId
    thread_id  = $ThreadId
    messages = @(
      @{ role="user"; content="그냥 아무 말이나 한 줄로 답해줘." }
    )
  }

  Write-Host "=== TEST B contracts ==="
  ($respB.meta.core.contracts | ConvertTo-Json -Depth 30) | Write-Host
  Write-Host "=== TEST B debug ==="
  ($respB.meta.orchestra.debug | ConvertTo-Json -Depth 30) | Write-Host
  Write-Host "=== TEST B content ==="
  ($respB.content | ConvertTo-Json -Depth 30) | Write-Host

  Assert-Bool -Name "B enforced" -Actual ([bool]$respB.meta.core.contracts.injected_context_enforced) -Expected $false

  Write-Host "`n[ALL PASS] TFV2 Summary Fusion 테스트 완료"
}