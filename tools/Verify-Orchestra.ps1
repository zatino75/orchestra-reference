param(
  [string]$BaseUrl   = "http://localhost:8000",
  [string]$ProjectId = "guard-test",
  [string]$ThreadId  = "t1",

  [string]$SingleProvider = "openai",
  [string[]]$Providers = @("openai","gemini","claude","perplexity","extra"),

  [switch]$UseFixedProjectId,

  [int]$MinClaimMultiplier = 5,
  [int]$MinOrchModelConflictsUnique = 1,

  [switch]$VerifyLatestEndpoints = $true)

Set-StrictMode -Version Latest
. "$PSScriptRoot\Verify-OrchestraOps.ps1"
$ErrorActionPreference = "Stop"

function Fail([string]$msg) { Write-Host ""; Write-Host "❌ FAIL: $msg"; exit 1 }
function Pass([string]$msg) { Write-Host ""; Write-Host "✅ PASS: $msg"; exit 0 }
function Assert([bool]$cond, [string]$msg) { if (-not $cond) { Fail $msg } }

function Post-Report([string]$projectId, [object[]]$testset) {
  $body = @{
    projectId        = $projectId
    threadId         = $ThreadId
    mode             = "verify_orchestra"
    single_provider  = $SingleProvider
    providers        = $Providers
    testset          = $testset
  } | ConvertTo-Json -Depth 20

  $u = "$BaseUrl/api/report"
  $r = Invoke-RestMethod -Method Post -Uri $u -ContentType "application/json" -Body $body
  if (-not $r) { throw "report empty response" }
  if (-not $r.id) { throw "report id missing" }
  return $r
}

function Get-ReportLatest([string]$projectId) {
  $u = "$BaseUrl/api/report/latest?projectId=$projectId"
  return Invoke-RestMethod -Method Get -Uri $u
}

function Get-ReportById([string]$projectId, [string]$id) {
  $u = "$BaseUrl/api/report/$($id)?projectId=$projectId"
  return Invoke-RestMethod -Method Get -Uri $u
}

function Get-ProjectDir([string]$projectId) {
  $root = (Get-Location).Path
  $p1 = Join-Path $root ("server\projects\" + $projectId)
  if (Test-Path -LiteralPath $p1) { return $p1 }
  $p2 = Join-Path $root ("projects\" + $projectId)
  if (Test-Path -LiteralPath $p2) { return $p2 }
  throw "projectDir not found: $projectId"
}

function Read-JsonlTail([string]$path, [int]$tail=300) {
  if (-not (Test-Path -LiteralPath $path)) { return @() }
  $lines = Get-Content -LiteralPath $path -Tail $tail
  $out = @()
  foreach ($ln in $lines) {
    try { $out += ($ln | ConvertFrom-Json) } catch { }
  }
  return $out
}

# v3: unique project run (avoid dedupe pollution)
$runTag = ("vo_" + [Guid]::NewGuid().ToString("N").Substring(0,8))
$projectIdRun = if ($UseFixedProjectId) { $ProjectId } else { ($ProjectId + "__" + $runTag) }
$ts = (Get-Date).ToString("o")

Write-Host ""
Write-Host "=== VERIFY ORCHESTRA (DETERMINISTIC v3 / UNIQUE PROJECT) ==="
Write-Host ("base         : " + $BaseUrl)
Write-Host ("projectId_in : " + $ProjectId)
Write-Host ("projectId_run: " + $projectIdRun)
Write-Host ("threadId     : " + $ThreadId)
Write-Host ("single       : " + $SingleProvider)
Write-Host ("providers    : " + ($Providers -join ","))
Write-Host ("runTag       : " + $runTag)
Write-Host ("ts           : " + $ts)
Write-Host ("fixedProject : " + [bool]$UseFixedProjectId)

# deterministic testset (10)
$testset = @(
  @{ id="C01_port_allow";       message="ENTITY:$runTag rule: backend_port MUST be 8000. front_port MUST be 5173." },
  @{ id="C02_port_deny";        message="ENTITY:$runTag rule: backend_port MUST NOT be 9000. front_port MUST NOT be 3000." },
  @{ id="C03_restart_manual";   message="ENTITY:$runTag rule: restart MUST be manual by user (no auto restart in scripts)." },
  @{ id="C04_restart_auto";     message="ENTITY:$runTag claim: system MAY auto restart services." },
  @{ id="C05_injection_must";   message="ENTITY:$runTag rule: injection engine MUST run once per request and log reasons." },
  @{ id="C06_injection_skip";   message="ENTITY:$runTag claim: injection may be skipped for performance." },
  @{ id="C07_thread_pool";      message="ENTITY:$runTag rule: knowledge is projectId pooled across threads." },
  @{ id="C08_thread_isolated";  message="ENTITY:$runTag claim: each thread MUST be isolated (no cross-thread scan)." },
  @{ id="C09_schema_guard";     message="ENTITY:$runTag rule: scoreboard_definition MUST include schema_version and canonical_kpi." },
  @{ id="C10_adapter_contract"; message="ENTITY:$runTag rule: response contract MUST be unified; provider differences end at adapter." }
)

$r = Post-Report -projectId $projectIdRun -testset $testset

Write-Host ""
Write-Host "=== VERIFY RESULT (v3) ==="
Write-Host ("report_id   : " + $r.id)
Write-Host ("report_path : " + $r.report_path)
Write-Host ("items       : " + $r.testset_count)
Write-Host ("single      : " + $r.single_provider)
Write-Host ("providers   : " + ($r.providers -join ","))

Assert ($r.testset_count -eq 10) ("expected 10 items but got " + $r.testset_count)
Assert ($r.single_provider -eq $SingleProvider) ("single_provider mismatch: " + $r.single_provider)

$k = $r.kpi_summary
Assert ($null -ne $k) "kpi_summary missing in report response"
Assert ($k.PSObject.Properties.Name -contains "claim_multiplier") "kpi_summary.claim_multiplier missing"

# claim_multiplier is numeric-like
$cm = [double]$k.claim_multiplier
Assert ($cm -ge $MinClaimMultiplier) ("claim_multiplier too low: " + $cm + " (need >= " + $MinClaimMultiplier + ")")

# claims.jsonl: select assistant claims for this report_id
$projectDir = Get-ProjectDir $projectIdRun
$claimsLog = Join-Path $projectDir "claims.jsonl"
Assert (Test-Path -LiteralPath $claimsLog) ("MISSING claims.jsonl: " + $claimsLog)

$reportId = [string]$r.id
$tailClaims = Read-JsonlTail -path $claimsLog -tail 5000

$prefix = "as_" + $reportId + "_"
$asClaims = @($tailClaims | Where-Object {
  $_ -and $_.source -eq "assistant" -and ([string]$_.evidence_id).StartsWith($prefix)
})

Assert ($asClaims.Count -gt 0) ("no assistant claims found for this report_id in claims.jsonl (evidence_id prefix mismatch): report_id=" + $reportId)

# providers_with_claims: no HashSet/ToArray (deterministic, PS-safe)
$provMap = @{}
foreach ($c in $asClaims) {
  $p = [string]$c.provider_resolved
  if (-not $p) { $p = [string]$c.provider_requested }
  if (-not $p) { $p = "unknown" }
  $provMap[$p] = $true
}
$providersWithClaims = @($provMap.Keys | Sort-Object)

foreach ($p in $Providers) {
  Assert ($providersWithClaims -contains $p) ("provider has no claims in this report run: " + $p)
}

# model-conflict unique keys (cheap deterministic):
# group by (entity|predicate) then if provider objects differ => 1 conflict
$byKey = @{}
foreach ($c in $asClaims) {
  $ent = [string]$c.entity
  if (-not $ent) { $ent = "unknown" }

  $pred = [string]$c.predicate
  if (-not $pred) { $pred = "text" }

  $k2 = $ent + "|" + $pred

  $prov = [string]$c.provider_resolved
  if (-not $prov) { $prov = [string]$c.provider_requested }
  if (-not $prov) { $prov = "unknown" }

  $obj = [string]$c.object
  if (-not $obj) { $obj = [string]$c.text }

  if (-not $byKey.ContainsKey($k2)) { $byKey[$k2] = @{} }
  $byKey[$k2][$prov] = $obj
}

$conflictsUnique = 0
foreach ($k2 in $byKey.Keys) {
  $m = $byKey[$k2]
  $vals = @()
  foreach ($v in $m.Values) {
    $vv = ([string]$v).Trim().ToLowerInvariant()
    if ($vv -ne "") { $vals += $vv }
  }
  $vals = @($vals | Select-Object -Unique)
  if ($vals.Count -ge 2) { $conflictsUnique++ }
}

Write-Host ""
Write-Host ("providers_with_claims           : " + ($providersWithClaims -join ","))
Write-Host ("orch_model_conflicts_unique_keys: " + $conflictsUnique)

Assert ($conflictsUnique -ge $MinOrchModelConflictsUnique) ("orch_model_conflicts_unique_keys too low: " + $conflictsUnique + " (need >= " + $MinOrchModelConflictsUnique + ")")

if ($VerifyLatestEndpoints) {
  $latest = Get-ReportLatest -projectId $projectIdRun
  Assert ($latest.id -eq $reportId) ("latest.id mismatch: got " + $latest.id + " expected " + $reportId)

  $get = Get-ReportById -projectId $projectIdRun -id $reportId
  Assert ($get.id -eq $reportId) ("get.id mismatch: got " + $get.id + " expected " + $reportId)
  Assert ($get.report_path -eq $r.report_path) ("get.report_path mismatch")
}

Write-Host ""
Write-Host ("claim_multiplier                 : " + $cm)
Write-Host ("report_id                        : " + $reportId)
Write-Host ("report_path                      : " + $r.report_path)

Pass ("orchestra report OK on fresh project (claim_multiplier >= " + $MinClaimMultiplier + ", model_conflicts >= " + $MinOrchModelConflictsUnique + "). projectId_run=" + $projectIdRun)