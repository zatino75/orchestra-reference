Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True([bool]$cond, [string]$msg) { if (-not $cond) { throw "ASSERT FAIL: $msg" } }

function ArrCount($x) {
  if ($null -eq $x) { return 0 }
  if ($x -is [System.Collections.IDictionary]) { return [int]$x.Keys.Count }
  return [int](@($x).Count)
}

$base = "http://127.0.0.1:8000"

function Get-Json([string]$url) { Invoke-RestMethod -Method Get -Uri $url }

function Post-Json([string]$url, $bodyObj) {
  $json = ($bodyObj | ConvertTo-Json -Depth 20)
  Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json" -Body $json
}

function Post-Chat([string]$projectId, [string]$threadId, [string]$message, [string]$mode) {
  $req = @{ projectId=$projectId; threadId=$threadId; message=$message; mode=$mode }
  return (Post-Json "$base/api/chat" $req)
}

$openapi = Get-Json "$base/openapi.json"
Assert-True ($openapi.info.version -eq "2.0.4") "openapi version must be 2.0.4"

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$proj = "proj_smoke_v204_$stamp"

$rS  = Post-Chat $proj "tS" "port 99999 /api/chat core.app:app" "single"
$liS = Get-Json "$base/api/_debug/last_injection?projectId=$proj&threadId=tS"
$ljS = Get-Json "$base/api/_debug/last_judge?projectId=$proj&threadId=tS"

Assert-True ($rS.meta.orchestra.mode -eq "single") "single mode mismatch"
Assert-True ([int]$liS.lastInjection.candidateCount -eq 0) "single candidateCount must be 0"
Assert-True ([int]$liS.lastInjection.selectedDecisionCount -eq 0) "single selectedDecisionCount must be 0"
Assert-True ((ArrCount $liS.lastInjection.conflictsDetected) -eq 0) "single conflictsDetected must be empty"
Assert-True ((ArrCount $liS.lastInjection.rejectedDecisionIds) -eq 0) "single rejectedDecisionIds must be empty"
Assert-True ((ArrCount $ljS.lastJudge.decisionsMade) -eq 0) "single judge decisionsMade must be empty"
Assert-True ([int]$liS.lastInjection.finalInjectedLength -ge 1) "single finalInjectedLength must exist"

Post-Chat $proj "tA" "port 8000 /api/chat core.app:app" "orchestra" | Out-Null
Post-Chat $proj "tA" "port 8000" "orchestra" | Out-Null
Post-Chat $proj "tB" "port 9000" "orchestra" | Out-Null
Post-Chat $proj "tB" "port 9000" "orchestra" | Out-Null
Post-Chat $proj "tA" "port 8000" "orchestra" | Out-Null

$liA = Get-Json "$base/api/_debug/last_injection?projectId=$proj&threadId=tA"
$ljA = Get-Json "$base/api/_debug/last_judge?projectId=$proj&threadId=tA"

Assert-True ([int]$liA.lastInjection.candidateCount -ge 1) "orchestra candidateCount should be >= 1"
Assert-True ([int]$liA.lastInjection.selectedDecisionCount -ge 1) "orchestra selectedDecisionCount should be >= 1"
Assert-True ((ArrCount $liA.lastInjection.conflictsDetected) -ge 1) "orchestra conflictsDetected should be >= 1"
Assert-True ((ArrCount $ljA.lastJudge.decisionsMade) -ge 1) "orchestra decisionsMade should be >= 1"
Assert-True ([int]$liA.lastInjection.finalInjectedLength -ge 1) "orchestra finalInjectedLength must exist"

$d0 = @($ljA.lastJudge.decisionsMade)[0]
Assert-True ($null -ne $d0.pairKey -and "$($d0.pairKey)".Length -ge 1) "judge decisionsMade[0].pairKey missing"
Assert-True ($null -ne $d0.accepted -and "$($d0.accepted)".Length -ge 1) "judge decisionsMade[0].accepted missing"
Assert-True ((ArrCount $d0.rejected) -ge 1) "judge decisionsMade[0].rejected must have >= 1 item"
Assert-True ($null -ne $d0.reason -and "$($d0.reason)".Length -ge 1) "judge decisionsMade[0].reason missing"

$dl = Get-Json "$base/api/_debug/derived/list?projectId=$proj&limit=10"
Assert-True ($dl.ok -eq $true) "derived/list ok=false"
Assert-True ([int]$dl.count -ge 1) "derived/list empty"

$firstId = @($dl.items)[0].id
Assert-True ($null -ne $firstId -and "$firstId".Length -ge 1) "derived/list first id missing"

$dg = Get-Json "$base/api/_debug/derived/get?id=$firstId"
Assert-True ($dg.ok -eq $true) "derived/get ok=false"
Assert-True ($dg.item.id -eq $firstId) "derived/get id mismatch"

$sb = Get-Json "$base/api/_debug/scoreboard?projectId=$proj"
Assert-True ($sb.ok -eq $true) "scoreboard ok=false"
Assert-True ($sb.scoreboard.qualityScoreCapMin -eq 0.0) "scoreboard cap min missing"
Assert-True ($sb.scoreboard.qualityScoreCapMax -eq 100.0) "scoreboard cap max missing"
Assert-True ($sb.scoreboard.qualityScoreCapped -ne $null) "scoreboard capped bool missing"

Write-Host "PASS"
Write-Host ("projectId={0}" -f $proj)