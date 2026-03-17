param(
  [Parameter(Mandatory=$true)][string]$CompareJson,
  [double]$MinImprovementScore = 2.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
  param([Parameter(Mandatory=$true)][string]$Path)
  $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
  return ($raw | ConvertFrom-Json -ErrorAction Stop)
}

function ArrCount {
  param($x)
  if ($null -eq $x) { return 0 }
  if ($x -is [System.Collections.IDictionary]) { return [int]$x.Count }
  if ($x -is [string]) { return 1 }
  try { return [int](@($x).Length) } catch { return 1 }
}

function To-Num {
  param($v)
  if ($null -eq $v) { return [double]::NaN }
  try {
    if ($v -is [string] -and [string]::IsNullOrWhiteSpace($v)) { return [double]::NaN }
    return [double]$v
  } catch { return [double]::NaN }
}

function Is-NaN([double]$x) { return [double]::IsNaN($x) }

function Get-Deep($obj, [string[]]$path) {
  $cur = $obj
  foreach ($k in $path) {
    if ($null -eq $cur) { return $null }
    if ($cur -is [System.Collections.IDictionary]) {
      if (-not $cur.ContainsKey($k)) { return $null }
      $cur = $cur[$k]
    } else {
      try {
        $p = $cur.PSObject.Properties[$k]
        if ($null -eq $p) { return $null }
        $cur = $p.Value
      } catch { return $null }
    }
  }
  return $cur
}

function Pick-First($obj, [object[]]$paths) {
  foreach ($p in $paths) {
    $v = Get-Deep $obj $p
    if ($null -ne $v) { return $v }
  }
  return $null
}

function Delta([double]$a, [double]$b) {
  if (Is-NaN $a -or Is-NaN $b) { return [double]::NaN }
  return ($a - $b)
}

function Find-AdjacentNormalCompareJson {
  param([Parameter(Mandatory=$true)][string]$PrimaryCompareJsonPath)
  $dir = Split-Path -Parent (Resolve-Path -LiteralPath $PrimaryCompareJsonPath).Path
  $p1 = Join-Path $dir "compare_report_normal.json"
  if (Test-Path -LiteralPath $p1) { return $p1 }
  return $null
}

# outDir 확정
$cmp = Read-JsonFile -Path $CompareJson

$outDir = Get-Deep $cmp @("outDir")
if ([string]::IsNullOrWhiteSpace([string]$outDir)) {
  $outDir = Split-Path -Parent (Resolve-Path -LiteralPath $CompareJson).Path
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$judgeJson = Join-Path $outDir "judge_quality.json"
$judgeTxt  = Join-Path $outDir "judge_quality.txt"
$judgeNormalJson = Join-Path $outDir "judge_quality_normal.json"
$judgeNormalTxt  = Join-Path $outDir "judge_quality_normal.txt"

# -----------------------------
# PRIMARY (conflict) evaluation
# -----------------------------
$S = Get-Deep $cmp @("single","scoreboard")
$O = Get-Deep $cmp @("orchestra","scoreboard")

$qs_s    = To-Num (Pick-First $S @(@("qualityScore"), @("scoreboard","qualityScore")))
$qs_o    = To-Num (Pick-First $O @(@("qualityScore"), @("scoreboard","qualityScore")))
$qr_s    = To-Num (Pick-First $S @(@("qualityScoreRaw"), @("scoreboard","qualityScoreRaw")))
$qr_o    = To-Num (Pick-First $O @(@("qualityScoreRaw"), @("scoreboard","qualityScoreRaw")))

$capped_s = [bool](Pick-First $S @(@("qualityScoreCapped"), @("scoreboard","qualityScoreCapped")))
$capped_o = [bool](Pick-First $O @(@("qualityScoreCapped"), @("scoreboard","qualityScoreCapped")))
$anyCapped = ($capped_s -or $capped_o)

$avgCit_s = To-Num (Pick-First $S @(@("window","grounding","avgCitableIdsCount"), @("grounding","avgCitableIdsCount")))
$avgCit_o = To-Num (Pick-First $O @(@("window","grounding","avgCitableIdsCount"), @("grounding","avgCitableIdsCount")))

$avgInj_s = To-Num (Pick-First $S @(@("window","grounding","avgInjectedDecisionCount"), @("grounding","avgInjectedDecisionCount")))
$avgInj_o = To-Num (Pick-First $O @(@("window","grounding","avgInjectedDecisionCount"), @("grounding","avgInjectedDecisionCount")))

$failRate_s = To-Num (Pick-First $S @(@("window","verification","failRate"), @("verification","failRate")))
$failRate_o = To-Num (Pick-First $O @(@("window","verification","failRate"), @("verification","failRate")))

$wFail_s = To-Num (Pick-First $S @(@("window","verification","weightedFailWindow","score"), @("verification","weightedFailWindow","score")))
$wFail_o = To-Num (Pick-First $O @(@("window","verification","weightedFailWindow","score"), @("verification","weightedFailWindow","score")))
if (Is-NaN $wFail_s) { $wFail_s = 0.0 }
if (Is-NaN $wFail_o) { $wFail_o = 0.0 }

$confTot_s = To-Num (Pick-First $S @(@("window","conflict","total"), @("conflict","total")))
$confTot_o = To-Num (Pick-First $O @(@("window","conflict","total"), @("conflict","total")))
$confRes_s = To-Num (Pick-First $S @(@("window","conflict","resolveRate"), @("conflict","resolveRate")))
$confRes_o = To-Num (Pick-First $O @(@("window","conflict","resolveRate"), @("conflict","resolveRate")))

$judgeApplied_s = To-Num (Pick-First $S @(@("judgeApplied")))
$judgeApplied_o = To-Num (Pick-First $O @(@("judgeApplied")))

$confAllTot_s = To-Num (Pick-First $S @(@("conflict","total")))
$confAllTot_o = To-Num (Pick-First $O @(@("conflict","total")))

$d_qs   = Delta $qs_o $qs_s
$d_qr   = Delta $qr_o $qr_s
$d_cit  = Delta $avgCit_o $avgCit_s
$d_inj  = Delta $avgInj_o $avgInj_s
$d_fr   = Delta $failRate_o $failRate_s
$d_wf   = Delta $wFail_o $wFail_s
$d_crr  = Delta $confRes_o $confRes_s
$d_ctot = Delta $confTot_o $confTot_s

$score = 0.0
$notes = New-Object System.Collections.Generic.List[string]
$reasons = New-Object System.Collections.Generic.List[string]
$hardReasons = New-Object System.Collections.Generic.List[string]
$hardOk = $true

# hard gates: conflict signal must exist
if (Is-NaN $confTot_o) { $hardOk = $false; $hardReasons.Add("hardgate_conflict_window_total_nan") }
elseif ($confTot_o -lt 1) { $hardOk = $false; $hardReasons.Add("hardgate_conflict_window_total_lt_1") }

if (Is-NaN $judgeApplied_o) { $hardOk = $false; $hardReasons.Add("hardgate_judgeApplied_nan") }
elseif ($judgeApplied_o -lt 1) { $hardOk = $false; $hardReasons.Add("hardgate_judgeApplied_lt_1") }

# provider failures gate
$successOrchFail = To-Num (Get-Deep $cmp @("success","orchestra_fail"))
if (-not (Is-NaN $successOrchFail)) {
  if ($successOrchFail -gt 0) { $hardOk = $false; $hardReasons.Add("hardgate_orchestra_failures_gt_0") }
}

# scoring signals
if (-not (Is-NaN $d_qs)) {
  if ($d_qs -gt 0) { $score += 2.0; $notes.Add("qualityScore improved (+2)") }
  elseif ($d_qs -lt 0) { $score -= 3.0; $reasons.Add("qualityScore_regressed"); $notes.Add("qualityScore regressed (-3)") }
}

if (-not (Is-NaN $d_qr)) {
  if ($d_qr -gt 0) {
    $score += ($anyCapped ? 2.0 : 1.0)
    $notes.Add(("qualityScoreRaw improved (+{0})" -f ($anyCapped ? 2 : 1)))
  } elseif ($d_qr -lt 0) {
    $score -= 1.5
    $reasons.Add("qualityScoreRaw_regressed")
    $notes.Add("qualityScoreRaw regressed (-1.5)")
  }
}

if (-not (Is-NaN $d_cit)) {
  if ($d_cit -gt 0) { $score += 2.0; $notes.Add("avgCitableIdsCount improved (+2)") }
  elseif ($d_cit -lt 0) { $score -= 1.0; $notes.Add("avgCitableIdsCount regressed (-1)") }
}

if (-not (Is-NaN $d_inj)) {
  if ($d_inj -gt 0) { $score += 0.5; $notes.Add("avgInjectedDecisionCount improved (+0.5)") }
  elseif ($d_inj -lt 0) { $score -= 0.5; $notes.Add("avgInjectedDecisionCount regressed (-0.5)") }
}

if (-not (Is-NaN $d_fr)) {
  if ($d_fr -gt 0.02) { $score -= 3.0; $reasons.Add("verification_failRate_worse"); $notes.Add("verification failRate worse (-3)") }
  elseif ($d_fr -lt -0.02) { $score += 2.0; $notes.Add("verification failRate improved (+2)") }
}

if (-not (Is-NaN $d_wf)) {
  if ($d_wf -gt 0.25) { $score -= 3.0; $reasons.Add("weightedFailScore_worse"); $notes.Add("weightedFailScore worse (-3)") }
  elseif ($d_wf -lt -0.25) { $score += 2.5; $notes.Add("weightedFailScore improved (+2.5)") }
}

if (-not (Is-NaN $d_crr)) {
  if ($d_crr -gt 0) { $score += 1.0; $notes.Add("conflictResolveRate improved (+1)") }
  elseif ($d_crr -lt 0) { $score -= 1.0; $notes.Add("conflictResolveRate regressed (-1)") }
}

# verdict
$verdict = "FAIL"
$scoreRounded = [Math]::Round($score, 3)

if ($hardOk -and $score -ge $MinImprovementScore -and -not ($reasons.Contains("verification_failRate_worse") -or $reasons.Contains("weightedFailScore_worse") -or $reasons.Contains("qualityScore_regressed"))) {
  $verdict = "PASS"
} else {
  if (-not $hardOk) { $reasons.AddRange(@($hardReasons)) }
  if ($reasons.Count -eq 0) { $reasons.Add("insufficient_core_signal_improvement") }
}

$decision = [ordered]@{
  verdict = $verdict
  minImprovementScore = $MinImprovementScore
  improvementScore = $scoreRounded
  anyQualityScoreCapped = $anyCapped
  hardGates = [ordered]@{
    ok = $hardOk
    reasons = @($hardReasons)
    conflict_window_total_orch = $confTot_o
    judgeApplied_orch = $judgeApplied_o
    orchestra_failures = $successOrchFail
  }
  reasons = @($reasons)
  notes = @($notes)
}

$metrics = [ordered]@{
  qualityScore = @{ single=$qs_s; orch=$qs_o; delta=$d_qs; capped_single=$capped_s; capped_orch=$capped_o }
  qualityScoreRaw = @{ single=$qr_s; orch=$qr_o; delta=$d_qr }
  avgCitableIdsCount = @{ single=$avgCit_s; orch=$avgCit_o; delta=$d_cit }
  avgInjectedDecisionCount = @{ single=$avgInj_s; orch=$avgInj_o; delta=$d_inj }
  verificationFailRate = @{ single=$failRate_s; orch=$failRate_o; delta=$d_fr }
  weightedFailScore = @{ single=$wFail_s; orch=$wFail_o; delta=$d_wf }
  conflictTotalWindow = @{ single=$confTot_s; orch=$confTot_o; delta=$d_ctot }
  conflictResolveRateWindow = @{ single=$confRes_s; orch=$confRes_o; delta=$d_crr }
  judgeApplied = @{ single=$judgeApplied_s; orch=$judgeApplied_o; delta=(Delta $judgeApplied_o $judgeApplied_s) }
  conflictTotalAll = @{ single=$confAllTot_s; orch=$confAllTot_o; delta=(Delta $confAllTot_o $confAllTot_s) }
}

$out = [ordered]@{
  ok = $true
  ts = (Get-Date).ToString("s")
  compareJson = (Resolve-Path -LiteralPath $CompareJson).Path
  outDir = $outDir
  decision = $decision
  metrics = $metrics
}

($out | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $judgeJson -Encoding utf8

$txt = New-Object System.Collections.Generic.List[string]
$txt.Add(("VERDICT: {0}" -f $verdict))
$txt.Add(("ImprovementScore: {0} (min={1})" -f $decision.improvementScore, $MinImprovementScore))
$txt.Add(("AnyQualityScoreCapped: {0}" -f $anyCapped))
$txt.Add(("HardGates: ok={0} reasons={1}" -f $decision.hardGates.ok, (($decision.hardGates.reasons | ForEach-Object { $_ }) -join ", ")))
$txt.Add("Reasons: " + (($decision.reasons | ForEach-Object { $_ }) -join ", "))
$txt.Add("")
$txt.Add("Signals:")
$txt.Add(("  qualityScore: single={0} orch={1} delta={2} cappedS={3} cappedO={4}" -f $qs_s, $qs_o, $d_qs, $capped_s, $capped_o))
$txt.Add(("  qualityScoreRaw: single={0} orch={1} delta={2}" -f $qr_s, $qr_o, $d_qr))
$txt.Add(("  avgCitableIdsCount: single={0} orch={1} delta={2}" -f $avgCit_s, $avgCit_o, $d_cit))
$txt.Add(("  avgInjectedDecisionCount: single={0} orch={1} delta={2}" -f $avgInj_s, $avgInj_o, $d_inj))
$txt.Add(("  verificationFailRate: single={0} orch={1} delta={2}" -f $failRate_s, $failRate_o, $d_fr))
$txt.Add(("  weightedFailScore: single={0} orch={1} delta={2}" -f $wFail_s, $wFail_o, $d_wf))
$txt.Add(("  conflictTotal(window): single={0} orch={1} delta={2}" -f $confTot_s, $confTot_o, $d_ctot))
$txt.Add(("  conflictResolveRate(window): single={0} orch={1} delta={2}" -f $confRes_s, $confRes_o, $d_crr))
$txt.Add(("  judgeApplied(all): single={0} orch={1}" -f $judgeApplied_s, $judgeApplied_o))
$txt.Add(("  conflictTotal(all): single={0} orch={1}" -f $confAllTot_s, $confAllTot_o))
$txt.Add("")
$txt.Add("Notes:")
foreach ($n in $decision.notes) { $txt.Add("  - " + $n) }
$txt | Set-Content -LiteralPath $judgeTxt -Encoding utf8

# -----------------------------
# NORMAL (soft gates, WARN/FAIL only; never affects CI exit)
# -----------------------------
$normalPath = Find-AdjacentNormalCompareJson -PrimaryCompareJsonPath $CompareJson
if ($null -ne $normalPath) {
  $n = Read-JsonFile -Path $normalPath
  $Sn = Get-Deep $n @("single","scoreboard")
  $On = Get-Deep $n @("orchestra","scoreboard")

  $n_confTot = To-Num (Pick-First $On @(@("window","conflict","total"), @("conflict","total")))
  $n_judgeApplied = To-Num (Pick-First $On @(@("judgeApplied")))

  $n_avgCit_s = To-Num (Pick-First $Sn @(@("window","grounding","avgCitableIdsCount"), @("grounding","avgCitableIdsCount")))
  $n_avgCit_o = To-Num (Pick-First $On @(@("window","grounding","avgCitableIdsCount"), @("grounding","avgCitableIdsCount")))

  $n_avgInj_s = To-Num (Pick-First $Sn @(@("window","grounding","avgInjectedDecisionCount"), @("grounding","avgInjectedDecisionCount")))
  $n_avgInj_o = To-Num (Pick-First $On @(@("window","grounding","avgInjectedDecisionCount"), @("grounding","avgInjectedDecisionCount")))

  $n_fail_s = To-Num (Pick-First $Sn @(@("window","verification","failRate"), @("verification","failRate")))
  $n_fail_o = To-Num (Pick-First $On @(@("window","verification","failRate"), @("verification","failRate")))

  $n_d_cit = Delta $n_avgCit_o $n_avgCit_s
  $n_d_inj = Delta $n_avgInj_o $n_avgInj_s
  $n_d_fail = Delta $n_fail_o $n_fail_s

  $warn = New-Object System.Collections.Generic.List[string]
  $okSoft = $true

  # TODO-1 핵심: 측정 불가(NaN/누락)는 통과 금지
  if (Is-NaN $n_d_inj) { $okSoft = $false; $warn.Add("MetricUndefined:delta_avgInjectedDecisionCount") }
  if (Is-NaN $n_d_cit) { $okSoft = $false; $warn.Add("MetricUndefined:delta_avgCitableIdsCount") }
  if (Is-NaN $n_d_fail) { $okSoft = $false; $warn.Add("MetricUndefined:delta_verificationFailRate") }

  # soft rules (정의된 값만 평가)
  if (-not (Is-NaN $n_confTot)) {
    if ($n_confTot -gt 2) { $okSoft = $false; $warn.Add("softgate_conflict_window_total_gt_2") }
  }
  if (-not (Is-NaN $n_judgeApplied)) {
    if ($n_judgeApplied -gt 0) { $okSoft = $false; $warn.Add("softgate_judgeApplied_gt_0") }
  }

  if (-not (Is-NaN $n_d_inj)) {
    if ($n_d_inj -le 0) { $okSoft = $false; $warn.Add("softgate_delta_avgInjectedDecisionCount_le_0") }
  }
  if (-not (Is-NaN $n_d_cit)) {
    if ($n_d_cit -le 0) { $okSoft = $false; $warn.Add("softgate_delta_avgCitableIdsCount_le_0") }
  }
  if (-not (Is-NaN $n_d_fail)) {
    if ($n_d_fail -gt 0.02) { $okSoft = $false; $warn.Add("softgate_verification_failRate_worse") }
  }

  $normalOut = [ordered]@{
    ok = $true
    ts = (Get-Date).ToString("s")
    compareJson = (Resolve-Path -LiteralPath $normalPath).Path
    soft = [ordered]@{
      ok = $okSoft
      warnings = @($warn)
      thresholds = @{
        conflict_window_total_max = 2
        judgeApplied_max = 0
        delta_avgInjectedDecisionCount_min = 0.0001
        delta_avgCitableIdsCount_min = 0.0001
        verification_failRate_delta_max = 0.02
      }
    }
    metrics = [ordered]@{
      conflictTotalWindow_orch = $n_confTot
      judgeApplied_orch = $n_judgeApplied
      delta_avgInjectedDecisionCount = $n_d_inj
      delta_avgCitableIdsCount = $n_d_cit
      delta_verificationFailRate = $n_d_fail
    }
  }

  ($normalOut | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath $judgeNormalJson -Encoding utf8

  $tn = New-Object System.Collections.Generic.List[string]
  $tn.Add("NORMAL PROFILE (soft gates only)")
  $tn.Add(("SoftOK: {0}" -f $okSoft))
  $tn.Add("Warnings: " + (($warn | ForEach-Object { $_ }) -join ", "))
  $tn.Add("")
  $tn.Add(("conflictTotal(window)_orch = {0}" -f $n_confTot))
  $tn.Add(("judgeApplied_orch = {0}" -f $n_judgeApplied))
  $tn.Add(("delta_avgInjectedDecisionCount = {0}" -f $n_d_inj))
  $tn.Add(("delta_avgCitableIdsCount = {0}" -f $n_d_cit))
  $tn.Add(("delta_verificationFailRate = {0}" -f $n_d_fail))
  $tn | Set-Content -LiteralPath $judgeNormalTxt -Encoding utf8
}

"[judge done]"
"JSON: $judgeJson"
"TXT : $judgeTxt"
if (Test-Path -LiteralPath $judgeNormalJson) {
  "NORMAL JSON: $judgeNormalJson"
  "NORMAL TXT : $judgeNormalTxt"
}