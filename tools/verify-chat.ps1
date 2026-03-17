param(
  [string]$BaseUrl   = "http://localhost:8000",
  [string]$ProjectId = "guard-test",
  [string]$ThreadId  = "t1",
  [string[]]$Providers = @("openai","gemini","claude","perplexity","extra"),

  [switch]$UseFixedProjectId,   # 기본: OFF (매 실행마다 고유 projectId 생성)
  [int]$MinSelectedInjection = 1,
  [int]$MaxSelectedInjection = 5,

  [int]$MaxRepeatDeltaConflictsUnique = 0,
  [int]$MaxRepeatDeltaDecisionsUnique = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg) { Write-Host ""; Write-Host "❌ FAIL: $msg"; exit 1 }
function Pass([string]$msg) { Write-Host ""; Write-Host "✅ PASS: $msg"; exit 0 }
function Assert([bool]$cond, [string]$msg) { if (-not $cond) { Fail $msg } }

function Get-Scoreboard([string]$projectId) {
  $u = "$BaseUrl/api/scoreboard?projectId=$projectId"
  $r = Invoke-RestMethod -Method Get -Uri $u
  if (-not $r) { throw "scoreboard empty response" }
  if (-not $r.totals) { throw "scoreboard.totals missing" }
  return $r
}

function Post-Chat([string]$projectId, [string]$provider, [string]$message, [string]$mode="verify_chat") {
  $body = @{
    projectId = $projectId
    threadId  = $ThreadId
    mode      = $mode
    provider  = $provider
    message   = $message
  } | ConvertTo-Json -Depth 10

  $u = "$BaseUrl/api/chat"
  $r = Invoke-RestMethod -Method Post -Uri $u -ContentType "application/json" -Body $body
  if (-not $r) { throw "chat empty response" }
  if (-not $r.id) { throw "chat id missing" }
  return $r
}

function Get-ProjectDir([string]$projectId) {
  $root = (Get-Location).Path
  $p1 = Join-Path $root ("server\projects\" + $projectId)
  if (Test-Path -LiteralPath $p1) { return $p1 }
  $p2 = Join-Path $root ("projects\" + $projectId)
  if (Test-Path -LiteralPath $p2) { return $p2 }
  throw "projectDir not found: $projectId"
}

function Read-JsonlTail([string]$path, [int]$tail=50) {
  if (-not (Test-Path -LiteralPath $path)) { return @() }
  $lines = Get-Content -LiteralPath $path -Tail $tail
  $out = @()
  foreach ($ln in $lines) { try { $out += ($ln | ConvertFrom-Json) } catch { } }
  return $out
}

$runTs = (Get-Date).ToString("o")
$runTag = ("vc_" + [Guid]::NewGuid().ToString("N").Substring(0,8))
$entity = "ENTITY:" + $runTag

$projectIdRun = if ($UseFixedProjectId) { $ProjectId } else { ($ProjectId + "__" + $runTag) }

Write-Host ""
Write-Host "=== VERIFY CHAT (DETERMINISTIC v3 / UNIQUE PROJECT) ==="
Write-Host ("base         : " + $BaseUrl)
Write-Host ("projectId_in : " + $ProjectId)
Write-Host ("projectId_run: " + $projectIdRun)
Write-Host ("threadId     : " + $ThreadId)
Write-Host ("providers    : " + ($Providers -join ","))
Write-Host ("runTag       : " + $runTag)
Write-Host ("entity       : " + $entity)
Write-Host ("ts           : " + $runTs)
Write-Host ("fixedProject : " + [bool]$UseFixedProjectId)

# A) baseline scoreboard (for this run project)
$sb0 = Get-Scoreboard $projectIdRun
$tot0 = $sb0.totals

Assert ($tot0.PSObject.Properties.Name -contains "inject_runs") "scoreboard.totals.inject_runs missing"
Assert ($tot0.PSObject.Properties.Name -contains "conflicts_unique") "scoreboard.totals.conflicts_unique missing"
Assert ($tot0.PSObject.Properties.Name -contains "decisions_unique") "scoreboard.totals.decisions_unique missing"
Assert ($tot0.PSObject.Properties.Name -contains "claims") "scoreboard.totals.claims missing"

# B) provider routing smoke (5 calls)
$reqIds = @()
$rows = @()

foreach ($p in $Providers) {
  $msg = "ROUTING $entity provider=$p ts=$runTs"
  $r = Post-Chat -projectId $projectIdRun -provider $p -message $msg -mode "verify_chat_routing"

  $reqIds += [string]$r.id

  $provRes = [string]$r.provider
  $adapterId = $null
  $resolved  = $null
  try { $adapterId = [string]$r.meta.adapter.adapter_id } catch { }
  try { $resolved  = [string]$r.meta.adapter.provider_resolved } catch { }

  $rows += [pscustomobject]@{
    provider_req = $p
    provider_res = $provRes
    adapter_id   = $adapterId
    resolved     = $resolved
    id           = [string]$r.id
  }

  Assert ($provRes -eq $p) ("provider routing mismatch: req=$p res=$provRes id=$($r.id)")
  Assert ([bool]$adapterId) ("meta.adapter.adapter_id missing: id=$($r.id)")
  Assert ([bool]$resolved)  ("meta.adapter.provider_resolved missing: id=$($r.id)")
}

Write-Host ""
Write-Host "=== ROUTING CHECK ==="
$rows | Format-Table -AutoSize | Out-String | Write-Host

# C) claim extraction sanity + conflict/judge/dedupe on fresh project
# seed → claims must increase
$seedMsg = "SEED $entity backend_port MUST be 8000. front_port MUST be 5173. ts=$runTs"
$rSeed = Post-Chat -projectId $projectIdRun -provider "openai" -message $seedMsg -mode "verify_chat_conflict_seed"
$reqIds += [string]$rSeed.id

$sb1 = Get-Scoreboard $projectIdRun
$tot1 = $sb1.totals

$deltaClaimsSeed = [int]$tot1.claims - [int]$tot0.claims
Assert ($deltaClaimsSeed -ge 1) ("claims did not increase after seed (claim extractor may not be firing): delta=$deltaClaimsSeed")

# conflict → conflicts_unique + decisions_unique must increase
$confMsg = "CONFLICT $entity backend_port MUST be 9000. front_port MUST be 3000. ts=$runTs"
$rC1 = Post-Chat -projectId $projectIdRun -provider "openai" -message $confMsg -mode "verify_chat_conflict_1"
$reqIds += [string]$rC1.id

$sb2 = Get-Scoreboard $projectIdRun
$tot2 = $sb2.totals

$deltaClaimsC1 = [int]$tot2.claims - [int]$tot1.claims
Assert ($deltaClaimsC1 -ge 1) ("claims did not increase after conflict msg (extractor issue): delta=$deltaClaimsC1")

$deltaC1 = [int]$tot2.conflicts_unique - [int]$tot1.conflicts_unique
$deltaD1 = [int]$tot2.decisions_unique - [int]$tot1.decisions_unique
Assert ($deltaC1 -ge 1) ("conflicts_unique did not increase on first conflict: delta=$deltaC1")
Assert ($deltaD1 -ge 1) ("decisions_unique did not increase on first conflict: delta=$deltaD1")

# repeat → unique should not increase
$rC2 = Post-Chat -projectId $projectIdRun -provider "openai" -message $confMsg -mode "verify_chat_conflict_repeat"
$reqIds += [string]$rC2.id

$sb3 = Get-Scoreboard $projectIdRun
$tot3 = $sb3.totals

$deltaC2 = [int]$tot3.conflicts_unique - [int]$tot2.conflicts_unique
$deltaD2 = [int]$tot3.decisions_unique - [int]$tot2.decisions_unique
Assert ($deltaC2 -le $MaxRepeatDeltaConflictsUnique) ("repeat conflict increased conflicts_unique: delta=$deltaC2 max=$MaxRepeatDeltaConflictsUnique")
Assert ($deltaD2 -le $MaxRepeatDeltaDecisionsUnique) ("repeat conflict increased decisions_unique: delta=$deltaD2 max=$MaxRepeatDeltaDecisionsUnique")

# D) inject_log integrity check: req_id entries exist + required fields
$projectDir = Get-ProjectDir $projectIdRun
$injectLog = Join-Path $projectDir "inject_log.jsonl"
Assert (Test-Path -LiteralPath $injectLog) ("missing inject_log.jsonl at " + $injectLog)

$tail = Read-JsonlTail -path $injectLog -tail 300
$set = New-Object System.Collections.Generic.HashSet[string]
$reqIds | ForEach-Object { [void]$set.Add([string]$_) }

$mine = @($tail | Where-Object { $set.Contains([string]$_.req_id) })
Assert ($mine.Count -ge $reqIds.Count) ("inject_log does not contain enough entries for this run: have=$($mine.Count) need=$($reqIds.Count)")

foreach ($o in $mine) {
  Assert ([bool]$o.ts) "inject_log.ts missing"
  Assert ([bool]$o.req_id) "inject_log.req_id missing"
  Assert ([bool]$o.provider_requested) "inject_log.provider_requested missing"
  Assert ([bool]$o.provider_resolved)  "inject_log.provider_resolved missing"
  Assert ([bool]$o.adapter_id)         "inject_log.adapter_id missing"
  Assert ($null -ne $o.candidates)     "inject_log.candidates missing"
  Assert ($null -ne $o.selected)       "inject_log.selected missing"
  Assert ($null -ne $o.rejected)       "inject_log.rejected missing"
  Assert ($null -ne $o.finalInjectedLength) "inject_log.finalInjectedLength missing"

  $selCount = @($o.selected).Count
  Assert ($selCount -ge $MinSelectedInjection) ("inject_log selected too low: $selCount")
  Assert ($selCount -le $MaxSelectedInjection) ("inject_log selected too high: $selCount")
}

Write-Host ""
Write-Host "=== SCOREBOARD DELTAS (RUN PROJECT) ==="
[pscustomobject]@{
  projectId_run = $projectIdRun

  claims_0 = [int]$tot0.claims
  claims_1 = [int]$tot1.claims
  claims_2 = [int]$tot2.claims
  claims_3 = [int]$tot3.claims
  delta_claims_seed = $deltaClaimsSeed
  delta_claims_conflict = $deltaClaimsC1

  conflicts_unique_1 = [int]$tot1.conflicts_unique
  conflicts_unique_2 = [int]$tot2.conflicts_unique
  conflicts_unique_3 = [int]$tot3.conflicts_unique
  delta_conflict_first  = $deltaC1
  delta_conflict_repeat = $deltaC2

  decisions_unique_1 = [int]$tot1.decisions_unique
  decisions_unique_2 = [int]$tot2.decisions_unique
  decisions_unique_3 = [int]$tot3.decisions_unique
  delta_decision_first  = $deltaD1
  delta_decision_repeat = $deltaD2
} | Format-List | Out-String | Write-Host

Pass ("chat pipeline OK on fresh project (claim extraction + conflict+judge + dedupe + inject_log). projectId_run=" + $projectIdRun)