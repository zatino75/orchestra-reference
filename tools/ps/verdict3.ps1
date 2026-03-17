param(
  [string] $ProjectRoot,
  [string] $BenchDir,
  [string] $KpiJsonPath,
  [double] $Eps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($null -eq $ProjectRoot) { $ProjectRoot = "" }
if ($null -eq $BenchDir -or [string]::IsNullOrWhiteSpace($BenchDir)) { $BenchDir = "server\data\logs\_bench" }
if ($null -eq $KpiJsonPath) { $KpiJsonPath = "" }
if ($null -eq $Eps -or $Eps -le 0) { $Eps = 0.000001 }

function Resolve-ProjectRoot {
  param([string] $HintRoot, [string] $BenchRel)

  if (-not [string]::IsNullOrWhiteSpace($HintRoot)) {
    $p = (Resolve-Path -LiteralPath $HintRoot).Path
    if (Test-Path -LiteralPath (Join-Path $p $BenchRel)) { return $p }
  }

  $cur = (Get-Location).Path
  while ($true) {
    if (Test-Path -LiteralPath (Join-Path $cur $BenchRel)) { return $cur }
    $parent = Split-Path -Path $cur -Parent
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cur) { break }
    $cur = $parent
  }

  throw "ProjectRoot auto-detect failed. Expected to find: $BenchRel"
}

function Read-Json {
  param([string] $Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { throw "Read-Json: Path is empty" }
  if (-not (Test-Path -LiteralPath $Path)) { throw "File not found: $Path" }
  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  return ($raw | ConvertFrom-Json -ErrorAction Stop)
}

function Get-PropValue {
  param($obj, [string]$name)
  if ($null -eq $obj) { return $null }
  if ($obj -is [System.Array]) { return $null }
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p) { return $null }
  return $p.Value
}

function Get-DeepValue {
  param($obj, [string]$path)
  if ($null -eq $obj) { return $null }
  $cur = $obj
  foreach ($seg in ($path.Split('.'))) {
    $cur = Get-PropValue $cur $seg
    if ($null -eq $cur) { return $null }
  }
  return $cur
}

function Safe-NumOrNull {
  param($v)
  if ($null -eq $v) { return $null }
  try { return [double]$v } catch { return $null }
}

$ProjectRoot = Resolve-ProjectRoot -HintRoot $ProjectRoot -BenchRel $BenchDir
$benchPath = Join-Path $ProjectRoot $BenchDir

# --- Write-Host block
Write-Host ("[verdict3] ProjectRoot=" + $ProjectRoot)
Write-Host ("[verdict3] BenchPath=" + $benchPath)

if ([string]::IsNullOrWhiteSpace($KpiJsonPath)) {
  $latest = @(Get-ChildItem -LiteralPath $benchPath -File -Filter "promote_kpi_v3_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  if ($latest.Count -gt 0) { $KpiJsonPath = $latest[0].FullName }
}

# --- Write-Host block
Write-Host ("[verdict3] KpiJsonPath=" + $KpiJsonPath)

$k = Read-Json -Path $KpiJsonPath

$repAvail = Get-DeepValue $k "promote_kpi_v3.repeat_claim.available"
$canAvail = Get-DeepValue $k "promote_kpi_v3.canonicalization.available"
$recAvail = Get-DeepValue $k "promote_kpi_v3.conflict_recurrence.available"

if ($null -eq $repAvail) { $repAvail = $false }
if ($null -eq $canAvail) { $canAvail = $false }
if ($null -eq $recAvail) { $recAvail = $false }

$repeat = Safe-NumOrNull (Get-DeepValue $k "promote_kpi_v3.repeat_claim.rate")
$canon  = Safe-NumOrNull (Get-DeepValue $k "promote_kpi_v3.canonicalization.rate")
$recur  = Safe-NumOrNull (Get-DeepValue $k "promote_kpi_v3.conflict_recurrence.rate")

$evoMeasurable = ($repAvail -or $canAvail -or $recAvail)

# measurable summary signals
$jrPct = Safe-NumOrNull (Get-DeepValue $k "alt_metrics.judgeRequired_pct")
$avgTC = Safe-NumOrNull (Get-DeepValue $k "alt_metrics.avg_log_totalConflictCount")
$avgJR = Safe-NumOrNull (Get-DeepValue $k "alt_metrics.avg_log_judgeResolvedCount")

$driftRules = @()

$detailRepeat = ""
if ($repAvail) { $detailRepeat = "repeat_claim.rate in [0,1]" } else { $detailRepeat = "repeat_claim N/A for this bench schema" }
$okRepeat = ((-not $repAvail) -or ($null -ne $repeat -and $repeat -ge 0 -and $repeat -le 1))
$driftRules += [pscustomobject]@{ id="drift_repeat_defined_or_na"; ok=$okRepeat; detail=$detailRepeat }

$detailCanon = ""
if ($canAvail) { $detailCanon = "canonicalization.rate in [0,1]" } else { $detailCanon = "canonicalization N/A for this bench schema" }
$okCanon = ((-not $canAvail) -or ($null -ne $canon -and $canon -ge 0 -and $canon -le 1))
$driftRules += [pscustomobject]@{ id="drift_canon_defined_or_na"; ok=$okCanon; detail=$detailCanon }

$detailRecur = ""
if ($recAvail) { $detailRecur = "conflict_recurrence.rate in [0,1]" } else { $detailRecur = "conflict_recurrence N/A for this bench schema" }
$okRecur = ((-not $recAvail) -or ($null -ne $recur -and $recur -ge 0 -and $recur -le 1))
$driftRules += [pscustomobject]@{ id="drift_recur_defined_or_na"; ok=$okRecur; detail=$detailRecur }

$driftRules += [pscustomobject]@{ id="drift_judgeRequiredPct_defined"; ok=($null -ne $jrPct -and $jrPct -ge 0 -and $jrPct -le 1); detail="alt_metrics.judgeRequired_pct in [0,1]" }
$driftRules += [pscustomobject]@{ id="drift_avgTotalConflict_defined"; ok=($null -ne $avgTC -and $avgTC -ge 0); detail="alt_metrics.avg_log_totalConflictCount >= 0" }
$driftRules += [pscustomobject]@{ id="drift_avgJudgeResolved_defined"; ok=($null -ne $avgJR -and $avgJR -ge 0); detail="alt_metrics.avg_log_judgeResolvedCount >= 0" }

$driftPass = (@($driftRules | Where-Object { $_.ok })).Count
$driftTotal = $driftRules.Count

$verdict = ""
$reason = ""

switch ($true) {
  (-not $evoMeasurable) {
    $verdict = "WARN"
    $reason = "Evolution KPIs (repeat/canonicalization/recurrence) are not measurable from current bench schema (rows only contain log_/runtime_ scalars). Rerun bench with detailed debug (claims/decisions/conflicts arrays) or compute evolution KPIs from request logs."
    break
  }
  ($driftPass -eq $driftTotal) { $verdict = "PASS"; $reason="All drift rules passed"; break }
  default { $verdict = "FAIL"; $reason="Some drift rules failed"; break }
}

([pscustomobject]@{
  ok = $true
  projectRoot = $ProjectRoot
  kpiJsonPath = $KpiJsonPath
  evoMeasurable = $evoMeasurable
  verdict3 = $verdict
  reason = $reason
  drift = [pscustomobject]@{ pass=$driftPass; total=$driftTotal; rules=$driftRules }
  snapshot = [pscustomobject]@{
    repeat_claim_rate = $repeat
    canonicalization_rate = $canon
    conflict_recurrence_rate = $recur
    judgeRequired_pct = $jrPct
    avg_log_totalConflictCount = $avgTC
    avg_log_judgeResolvedCount = $avgJR
  }
}) | ConvertTo-Json -Depth 60