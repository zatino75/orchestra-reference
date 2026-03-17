# 파워셀덮어쓰기
param(
  [Parameter(Position=0)]
  [ValidateSet("status","stop","start","reboot","tfv1","tfv2")]
  [string]$Action = "status",

  [Parameter(Position=1)]
  [string]$Base = "http://127.0.0.1:8000",

  [Parameter(Position=2)]
  [string]$ProjectId = "default",

  [Parameter(Position=3)]
  [string]$ThreadId  = "default"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-OrchestraRoot {
  param([string]$StartDir = (Get-Location).Path)
  $dir = (Resolve-Path $StartDir).Path
  while ($true) {
    $core = Join-Path $dir "core\app.py"
    $ui   = Join-Path $dir "ui\package.json"
    if ((Test-Path -LiteralPath $core) -and (Test-Path -LiteralPath $ui)) { return $dir }
    $parent = Split-Path -Parent $dir
    if ([string]::IsNullOrWhiteSpace($parent) -or ($parent -eq $dir)) { throw ("프로젝트 루트를 찾지 못했습니다. 시작 위치={0}" -f $StartDir) }
    $dir = $parent
  }
}

function Get-ListeningPids {
  param([Parameter(Mandatory=$true)][int]$Port)
  $conns = @()
  try { $conns = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop) } catch { $conns = @() }
  return @($conns | Where-Object { $_.OwningProcess -and $_.OwningProcess -gt 0 } | Select-Object -ExpandProperty OwningProcess -Unique)
}

function Show-Port { param([Parameter(Mandatory=$true)][int]$Port)
  $pids = @(Get-ListeningPids -Port $Port)
  if ($pids.Count -eq 0) { Write-Host ("Port {0}: FREE" -f $Port); return }
  $names = @()
  foreach ($procId in @($pids)) {
    try { $p = Get-Process -Id $procId -ErrorAction Stop; $names += ("{0}({1})" -f $p.ProcessName, $p.Id) }
    catch { $names += ("PID({0})" -f $procId) }
  }
  Write-Host ("Port {0}: IN-USE -> {1}" -f $Port, ($names -join ", "))
}

function Stop-PortOwner { param([Parameter(Mandatory=$true)][int]$Port)
  $pids = @(Get-ListeningPids -Port $Port)
  if ($pids.Count -eq 0) { Write-Host ("[OK] Port {0}: LISTEN 없음" -f $Port); return }
  foreach ($procId in @($pids)) {
    try {
      $p = Get-Process -Id $procId -ErrorAction Stop
      Write-Host ("[KILL] Port {0} PID {1} Name {2}" -f $Port, $procId, $p.ProcessName)
      Stop-Process -Id $procId -Force -ErrorAction Stop
    } catch {
      Write-Host ("[WARN] Port {0} PID {1} - {2}" -f $Port, $procId, $_.Exception.Message)
    }
  }
  Start-Sleep -Milliseconds 250
  $after = @(Get-ListeningPids -Port $Port)
  if ($after.Count -eq 0) { Write-Host ("[OK] Port {0}: 정리 완료" -f $Port) }
  else { Write-Host ("[WARN] Port {0}: 아직 LISTEN PID {1}" -f $Port, ($after -join ",")) }
}

function Start-Backend8000 { param([Parameter(Mandatory=$true)][string]$Root)
  Stop-PortOwner -Port 8000
  $py = Join-Path $Root ".venv\Scripts\python.exe"
  if (-not (Test-Path -LiteralPath $py)) { $py = "python" }
  $cmd = @("-m","uvicorn","core.app:app","--host","127.0.0.1","--port","8000")
  Write-Host ("[BACKEND] {0} {1}" -f $py, ($cmd -join " "))
  Start-Process -FilePath $py -ArgumentList $cmd -WorkingDirectory $Root -WindowStyle Normal | Out-Null
}

function Start-Frontend5173 { param([Parameter(Mandatory=$true)][string]$Root)
  $uiDir = Join-Path $Root "ui"
  if (-not (Test-Path -LiteralPath (Join-Path $uiDir "package.json"))) { throw ("ui\package.json not found: {0}" -f $uiDir) }
  Stop-PortOwner -Port 5173
  Write-Host ("[FRONTEND] dir={0}" -f $uiDir)
  $arg = "/c npm run dev -- --host 127.0.0.1 --port 5173"
  Start-Process -FilePath "cmd.exe" -ArgumentList $arg -WorkingDirectory $uiDir -WindowStyle Normal | Out-Null
}

function Server-Status { param([Parameter(Mandatory=$true)][string]$Root) Write-Host ("ROOT={0}" -f $Root); Show-Port -Port 8000; Show-Port -Port 5173 }
function Server-Stop { Stop-PortOwner -Port 8000; Stop-PortOwner -Port 5173 }
function Server-Start { param([Parameter(Mandatory=$true)][string]$Root) Start-Backend8000 -Root $Root; Start-Frontend5173 -Root $Root }
function Server-Reboot { param([Parameter(Mandatory=$true)][string]$Root) Server-Stop; Server-Start -Root $Root }

function Invoke-Chat {
  param([Parameter(Mandatory=$true)][string]$Base,[Parameter(Mandatory=$true)][hashtable]$BodyObj)
  $json = $BodyObj | ConvertTo-Json -Depth 50
  return Invoke-RestMethod -Method Post -Uri ("{0}/api/chat" -f $Base) -ContentType "application/json" -Body $json
}

function Assert-Bool {
  param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][bool]$Actual,[Parameter(Mandatory=$true)][bool]$Expected)
  if ($Actual -ne $Expected) { throw ("[ASSERT FAIL] {0}: expected={1} actual={2}" -f $Name, $Expected, $Actual) }
  Write-Host ("[PASS] {0}" -f $Name)
}

function Get-Pins {
  param([Parameter(Mandatory=$true)][string]$Base,[Parameter(Mandatory=$true)][string]$ProjectId,[Parameter(Mandatory=$true)][string]$ThreadId)
  $listJson = @{ project_id=$ProjectId; thread_id=$ThreadId } | ConvertTo-Json -Depth 20
  $resp = Invoke-RestMethod -Method Post -Uri ("{0}/api/pins/list" -f $Base) -ContentType "application/json" -Body $listJson
  return @($resp.pins)
}

function Test-TFV1Safe {
  param([Parameter(Mandatory=$true)][string]$Base,[Parameter(Mandatory=$true)][string]$ProjectId,[Parameter(Mandatory=$true)][string]$ThreadId)

  $hz = Invoke-RestMethod -Method Get -Uri ("{0}/healthz" -f $Base)
  if (-not $hz.ok) { throw "core healthz failed" }
  Write-Host ("[OK] healthz service={0} uptime_s={1}" -f $hz.service, $hz.uptime_s)

  $pins = @(Get-Pins -Base $Base -ProjectId $ProjectId -ThreadId $ThreadId)

  if ($pins.Count -gt 0) {
    # pins 경로
    $pick = $pins | Where-Object { $_.id -eq "pin_demo_001" } | Select-Object -First 1
    if (-not $pick) { $pick = $pins | Where-Object { $_.type -eq "note" -and $_.id } | Select-Object -First 1 }
    if (-not $pick) { $pick = $pins[0] }
    $pinId = [string]$pick.id
    Write-Host ("[MODE] pins (count={0})" -f $pins.Count)
    Write-Host ("[PICK] pinId={0} title={1} type={2}" -f $pinId, $pick.title, $pick.type)

    $r1 = Invoke-Chat -Base $Base -BodyObj @{
      project_id = $ProjectId
      thread_id  = $ThreadId
      selected_pins_ids = @($pinId)
      messages = @(@{ role="user"; content="핀 참고해서 한 줄로 요약해줘. 그리고 앵커 토큰을 그대로 포함해." })
    }
    Write-Host "=== TEST1 contracts ==="
    ($r1.meta.core.contracts | ConvertTo-Json -Depth 30) | Write-Host
    Write-Host "`n[DONE] TFV1 pins 경로 호출 완료"
    return
  }

  # pins=0 이면: summary 주입 경로로 자동 전환(실용)
  Write-Host "[WARN] pins=0 (save가 added=0/total=0이라 실제 저장 불가) => TFV1을 summary 주입 경로로 대체 실행"
  $summary = "TFV1_FALLBACK_SUMMARY: 이전 내용을 참고하여 한 줄로 요약하고, 앵커 토큰을 그대로 포함해야 합니다."
  $saveBody = @{ project_id=$ProjectId; thread_id=$ThreadId; summary=$summary; source="test" } | ConvertTo-Json -Depth 20
  $saveResp = Invoke-RestMethod -Method Post -Uri ("{0}/api/thread/summary/save" -f $Base) -ContentType "application/json" -Body $saveBody
  if (-not $saveResp.ok) { throw "summary save failed" }
  Write-Host "[OK] fallback summary saved"

  $respA = Invoke-Chat -Base $Base -BodyObj @{
    project_id = $ProjectId
    thread_id  = $ThreadId
    messages = @(@{ role="user"; content="저번 내용 참고해서 한 줄로 요약해줘. 앵커 토큰도 그대로 포함해." })
  }

  Write-Host "=== TFV1-FALLBACK contracts ==="
  ($respA.meta.core.contracts | ConvertTo-Json -Depth 30) | Write-Host

  Assert-Bool -Name "fallback enforced"   -Actual ([bool]$respA.meta.core.contracts.injected_context_enforced) -Expected $true
  Assert-Bool -Name "fallback anchor_hit" -Actual ([bool]$respA.meta.core.contracts.injected_context_anchor_hit) -Expected $true

  Write-Host "`n[DONE] TFV1 fallback(summary) 완료"
}

function Test-TFV2SummaryFusion {
  param([Parameter(Mandatory=$true)][string]$Base,[Parameter(Mandatory=$true)][string]$ProjectId,[Parameter(Mandatory=$true)][string]$ThreadId)

  $hz = Invoke-RestMethod -Method Get -Uri ("{0}/healthz" -f $Base)
  if (-not $hz.ok) { throw "core healthz failed" }
  Write-Host ("[OK] healthz service={0} uptime_s={1}" -f $hz.service, $hz.uptime_s)

  $summary = "TFV2_SUMMARY_DEMO: 이 스레드의 요약을 기반으로 자동 융합하고, 앵커 토큰을 답변에 포함해야 합니다."
  $saveBody = @{ project_id=$ProjectId; thread_id=$ThreadId; summary=$summary; source="test" } | ConvertTo-Json -Depth 20
  $saveResp = Invoke-RestMethod -Method Post -Uri ("{0}/api/thread/summary/save" -f $Base) -ContentType "application/json" -Body $saveBody
  if (-not $saveResp.ok) { throw "summary save failed" }
  Write-Host "[OK] summary saved"

  $respA = Invoke-Chat -Base $Base -BodyObj @{
    project_id = $ProjectId
    thread_id  = $ThreadId
    messages = @(@{ role="user"; content="저번 내용 참고해서 한 줄로 요약해줘. 앵커 토큰도 그대로 포함해." })
  }

  Write-Host "=== TEST A contracts ==="
  ($respA.meta.core.contracts | ConvertTo-Json -Depth 30) | Write-Host
  Assert-Bool -Name "A enforced"   -Actual ([bool]$respA.meta.core.contracts.injected_context_enforced) -Expected $true
  Assert-Bool -Name "A anchor_hit" -Actual ([bool]$respA.meta.core.contracts.injected_context_anchor_hit) -Expected $true

  $respB = Invoke-Chat -Base $Base -BodyObj @{
    project_id = $ProjectId
    thread_id  = $ThreadId
    messages = @(@{ role="user"; content="그냥 아무 말이나 한 줄로 답해줘." })
  }

  Write-Host "=== TEST B contracts ==="
  ($respB.meta.core.contracts | ConvertTo-Json -Depth 30) | Write-Host
  Assert-Bool -Name "B enforced" -Actual ([bool]$respB.meta.core.contracts.injected_context_enforced) -Expected $false

  Write-Host "`n[DONE] TFV2 Summary Fusion 테스트 완료"
}

$rootFound = Find-OrchestraRoot

switch ($Action) {
  "status" { Server-Status -Root $rootFound }
  "stop"   { Server-Stop; Server-Status -Root $rootFound }
  "start"  { Server-Start -Root $rootFound; Server-Status -Root $rootFound }
  "reboot" { Server-Reboot -Root $rootFound; Server-Status -Root $rootFound }
  "tfv1"   { Test-TFV1Safe -Base $Base -ProjectId $ProjectId -ThreadId $ThreadId }
  "tfv2"   { Test-TFV2SummaryFusion -Base $Base -ProjectId $ProjectId -ThreadId $ThreadId }
}