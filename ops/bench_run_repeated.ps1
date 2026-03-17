param(
  [int]$Runs = 50,
  [ValidateSet("both","conflict","normal")]
  [string]$BenchProfile = "both",
  [string]$BenchsetPath = ".\ops\benchsets\bench70_v001.json",

  # 재현성(기본 PASS) 기준
  [int]$MinConflictOrchJA = 1,
  [double]$ConflictWindowTotalTarget = 50.0,
  [double]$ConflictWindowTotalTol = 1.0,
  [int]$NormalOrchJAExpected = 0,
  [double]$NormalWindowTotalExpected = 0.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-AtomicUtf8 {
  param(
    [Parameter(Mandatory=$true)][string]$LiteralPath,
    [Parameter(Mandatory=$true)][string]$Content
  )
  $fullPath = $LiteralPath
  if (-not [System.IO.Path]::IsPathRooted($fullPath)) { $fullPath = Join-Path (Get-Location).Path $fullPath }
  $fullPath = [System.IO.Path]::GetFullPath($fullPath)
  $dir = Split-Path -Parent $fullPath
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $tmp = Join-Path $dir (".__tmp_{0}.txt" -f ([Guid]::NewGuid().ToString("N")))
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($tmp, $Content, $enc)
  Move-Item -LiteralPath $tmp -Destination $fullPath -Force
}

function Mean([double[]]$xs) { if ($xs.Count -eq 0) { return $null }; ($xs | Measure-Object -Average).Average }
function Std([double[]]$xs) {
  if ($xs.Count -lt 2) { return $null }
  $m = (Mean $xs)
  $sum = 0.0
  foreach ($x in $xs) { $sum += [math]::Pow(($x - $m), 2) }
  [math]::Sqrt($sum / ($xs.Count - 1))
}
function TCI95([double[]]$xs) {
  $n = $xs.Count
  if ($n -lt 2) { return $null }
  $m = Mean $xs
  $s = Std $xs
  if ($null -eq $s) { return $null }
  $se = $s / [math]::Sqrt($n)
  $z = 1.96
  return [pscustomobject]@{ n=$n; mean=$m; lo=($m - $z*$se); hi=($m + $z*$se); std=$s; se=$se }
}
function CohenD_PairedText([double[]]$deltas) {
  $n = $deltas.Count
  if ($n -lt 2) { return $null }
  $m = Mean $deltas
  $s = Std $deltas
  if ($null -eq $s) { return [pscustomobject]@{ n=$n; dText="undefined (std=null)"; note="std(delta)=null" } }
  if ($s -eq 0.0) {
    if ($m -gt 0.0) { return [pscustomobject]@{ n=$n; dText="INF"; note="std(delta)=0 and mean(delta)>0" } }
    if ($m -lt 0.0) { return [pscustomobject]@{ n=$n; dText="-INF"; note="std(delta)=0 and mean(delta)<0" } }
    return [pscustomobject]@{ n=$n; dText="0"; note="std(delta)=0 and mean(delta)=0" }
  }
  return [pscustomobject]@{ n=$n; dText=("{0}" -f ($m/$s)); note=$null }
}

function Get-LatestOutDir {
  $base = Join-Path (Get-Location).Path "ui\ops"
  $d = Get-ChildItem -LiteralPath $base -Directory -Filter "bench_split_out_*" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $d) { throw "no_outDir_found" }
  return $d.FullName
}

function Parse-ReportPatchLines([string]$compareTxtPath) {
  if (-not (Test-Path -LiteralPath $compareTxtPath)) { return $null }
  $txt = Get-Content -LiteralPath $compareTxtPath -Raw

  function M([string]$pat) {
    $m = [regex]::Match($txt, $pat)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
  }

  $orchJA=$null; $singleJA=$null; $deltaJA=$null; $wct=$null
  $singleLeaf=$null; $orchLeaf=$null

  $v = M "orch\.window\.judgeApplied\.total\s*=\s*(\d+)"
  if ($v -ne $null) { $orchJA = [int]$v }
  $v = M "single\.window\.judgeApplied\.total\s*=\s*(\d+)"
  if ($v -ne $null) { $singleJA = [int]$v }
  $v = M "delta\.window\.judgeApplied\.total\s*=\s*([0-9\-]+)"
  if ($v -ne $null) { $deltaJA = [int]$v }
  $v = M "window\.conflict\.total\s*=\s*([0-9\.]+)"
  if ($v -ne $null) { $wct = [double]$v }

  $v = M "SingleDir:\s*([^\r\n]+)"
  if ($v -ne $null) { $singleLeaf = $v.Trim() }
  $v = M "OrchDir\s*:\s*([^\r\n]+)"
  if ($v -ne $null) { $orchLeaf = $v.Trim() }

  return [pscustomobject]@{ orchJA=$orchJA; singleJA=$singleJA; deltaJA=$deltaJA; wct=$wct; singleLeaf=$singleLeaf; orchLeaf=$orchLeaf }
}

function ArrCount($x) {
  if ($null -eq $x) { return 0 }
  if ($x -is [System.Collections.IDictionary]) { return [int]$x.Count }
  if ($x -is [string]) { return 1 }
  try { return [int](@($x).Length) } catch { return 1 }
}

function Read-OrchObservedGC([string]$orchDir) {
  $files = Get-ChildItem -LiteralPath $orchDir -File -Filter "orchestra_*.json" | Sort-Object Name
  if ($null -eq $files -or $files.Count -eq 0) { return $null }

  $cite = New-Object System.Collections.Generic.List[double]
  $sel  = New-Object System.Collections.Generic.List[double]

  foreach ($f in $files) {
    $j = $null
    try { $j = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { continue }

    $c = 0
    try { $c = ArrCount $j.meta.orchestra.citations } catch { $c = 0 }
    $cite.Add([double]$c) | Out-Null

    $s = 0
    try { $s = ArrCount $j.meta.orchestra.debug.injectionLog.selected } catch { $s = 0 }
    $sel.Add([double]$s) | Out-Null
  }

  return [pscustomobject]@{
    avgCitations = Mean ($cite.ToArray())
    avgSelected  = Mean ($sel.ToArray())
    n = $files.Count
  }
}

function TryGetPath($obj, [string]$path) {
  $cur = $obj
  foreach ($p in ($path -split "\.")) {
    if ($null -eq $cur) { return $null }
    try { $cur = $cur.$p } catch { return $null }
  }
  return $cur
}
function TryNum($v) { try { return [double]$v } catch { return $null } }

function Read-VerificationFromScoreboard([string]$dir) {
  $sbPath = Join-Path $dir "scoreboard.json"
  if (-not (Test-Path -LiteralPath $sbPath)) { return $null }

  $j = $null
  try { $j = Get-Content -LiteralPath $sbPath -Raw | ConvertFrom-Json } catch { return $null }
  if ($null -eq $j) { return $null }

  $sb = $j.scoreboard
  if ($null -eq $sb) { return $null }

  $fail = TryNum (TryGetPath $sb "window.verification.failRate")
  $wfs  = TryNum (TryGetPath $sb "window.verification.weightedFailWindow.score")

  return [pscustomobject]@{ failRate=$fail; weightedFailScore=$wfs; sbPath=$sbPath }
}

function Pass-ConflictBasic($conf) {
  if ($null -eq $conf) { return $false }
  return ($conf.orchJA -ge $MinConflictOrchJA) -and
    ($conf.wct -ge ($ConflictWindowTotalTarget - $ConflictWindowTotalTol)) -and
    ($conf.wct -le ($ConflictWindowTotalTarget + $ConflictWindowTotalTol))
}
function Pass-NormalBasic($norm) {
  if ($null -eq $norm) { return $false }
  return ($norm.orchJA -eq $NormalOrchJAExpected) -and ($norm.wct -eq $NormalWindowTotalExpected)
}

$rows = @()

for ($i=1; $i -le $Runs; $i++) {
  & ".\ops\bench_70_split.ps1" -BenchProfile $BenchProfile -BenchsetPath $BenchsetPath | Out-Null

  $outDir = Get-LatestOutDir

  $confTxt = Join-Path $outDir "compare_report.txt"
  $normTxt = Join-Path $outDir "compare_report_normal.txt"

  $conf = Parse-ReportPatchLines $confTxt
  $norm = Parse-ReportPatchLines $normTxt

  $passBasic = $true
  if ($BenchProfile -eq "both" -or $BenchProfile -eq "conflict") { $passBasic = $passBasic -and (Pass-ConflictBasic $conf) }
  if ($BenchProfile -eq "both" -or $BenchProfile -eq "normal") {
    if ($BenchProfile -eq "both") { $passBasic = $passBasic -and (Pass-NormalBasic $norm) }
    else { $passBasic = $passBasic -and (Pass-NormalBasic $conf) }
  }
  if (-not $passBasic) { throw ("FAILED basic thresholds on run {0}" -f $i) }

  $orchDir = $null
  $singleDir = $null
  if ($conf -and $conf.orchLeaf)   { $orchDir = Join-Path $outDir $conf.orchLeaf }
  if ($conf -and $conf.singleLeaf) { $singleDir = Join-Path $outDir $conf.singleLeaf }

  if ($null -eq $orchDir -or -not (Test-Path -LiteralPath $orchDir)) { throw ("orchDir_not_found: {0}" -f $orchDir) }
  if ($null -eq $singleDir -or -not (Test-Path -LiteralPath $singleDir)) { throw ("singleDir_not_found: {0}" -f $singleDir) }

  $obs = Read-OrchObservedGC $orchDir
  if ($null -eq $obs) { throw "observed_GC_null" }

  $verOrch = Read-VerificationFromScoreboard $orchDir
  $verSingle = Read-VerificationFromScoreboard $singleDir
  if ($null -eq $verOrch) { throw "verification_orch_null" }
  if ($null -eq $verSingle) { throw "verification_single_null" }

  $deltaFail = $null
  if ($verOrch.failRate -ne $null -and $verSingle.failRate -ne $null) { $deltaFail = [double]$verOrch.failRate - [double]$verSingle.failRate }

  $deltaWfs = $null
  if ($verOrch.weightedFailScore -ne $null -and $verSingle.weightedFailScore -ne $null) { $deltaWfs = [double]$verOrch.weightedFailScore - [double]$verSingle.weightedFailScore }

  $rows += [pscustomobject]@{
    run = $i
    outDir = $outDir

    conflict_deltaJA = $(if($conf){$conf.deltaJA}else{$null})
    conflict_wct     = $(if($conf){$conf.wct}else{$null})

    grounding_delta_avgCitations = [double]$obs.avgCitations
    consistency_delta_avgSelected = [double]$obs.avgSelected

    verification_orch_failRate = $verOrch.failRate
    verification_single_failRate = $verSingle.failRate
    verification_delta_failRate = $deltaFail

    verification_orch_weightedFailScore = $verOrch.weightedFailScore
    verification_single_weightedFailScore = $verSingle.weightedFailScore
    verification_delta_weightedFailScore = $deltaWfs

    normal_deltaJA = $(if($norm){$norm.deltaJA}else{$null})
    normal_wct     = $(if($norm){$norm.wct}else{$null})

    PASS_basic = $true
  }
}

function Vec([object[]]$xs) { @($xs | Where-Object { $_ -ne $null } | ForEach-Object { [double]$_ }) }

$G = Vec ($rows | ForEach-Object { $_.grounding_delta_avgCitations })
$C = Vec ($rows | ForEach-Object { $_.consistency_delta_avgSelected })

$H1d = Vec ($rows | ForEach-Object { $_.verification_delta_failRate })
$H2d = Vec ($rows | ForEach-Object { $_.verification_delta_weightedFailScore })

$ciG = TCI95 $G
$ciC = TCI95 $C
$ciH1d = TCI95 $H1d
$ciH2d = TCI95 $H2d

$esG = CohenD_PairedText $G
$esC = CohenD_PairedText $C
$esH1d = CohenD_PairedText $H1d
$esH2d = CohenD_PairedText $H2d

function CI_PositiveWin($ci) { return ($ci -ne $null) -and ($ci.lo -gt 0.0) }
function CI_NegativeWin($ci) { return ($ci -ne $null) -and ($ci.hi -lt 0.0) }

$verdict = [ordered]@{
  conflict = [ordered]@{
    grounding_win = CI_PositiveWin $ciG
    consistency_win = CI_PositiveWin $ciC
    hallucination_win_failRate = CI_NegativeWin $ciH1d
    hallucination_win_weighted = CI_NegativeWin $ciH2d
  }
}

$summary = [ordered]@{
  runs = $Runs
  benchProfile = $BenchProfile
  passRate_basic = 1.0
  metrics = [ordered]@{
    grounding_delta_avgCitations_ci95 = $ciG
    grounding_effectSize = $esG
    consistency_delta_avgSelected_ci95 = $ciC
    consistency_effectSize = $esC
    verification_delta_failRate_ci95 = $ciH1d
    verification_effectSize_failRate = $esH1d
    verification_delta_weightedFailScore_ci95 = $ciH2d
    verification_effectSize_weighted = $esH2d
  }
  verdict = $verdict
}

$base = Join-Path (Get-Location).Path "ui\ops"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$sumTxt   = Join-Path $base ("bench_repeat_summary_{0}.txt" -f $stamp)
$sumJson  = Join-Path $base ("bench_repeat_summary_{0}.json" -f $stamp)
$rowsJson = Join-Path $base ("bench_repeat_rows_{0}.json" -f $stamp)

function LineCI($name, $ci) {
  if ($null -eq $ci) { return ("{0}: (null)" -f $name) }
  return ("{0}: mean={1} std={2} CI95=[{3},{4}] n={5}" -f $name,$ci.mean,$ci.std,$ci.lo,$ci.hi,$ci.n)
}
function LineD($name, $d) {
  if ($null -eq $d) { return ("{0}: (null)" -f $name) }
  $s = ("{0}: d={1}" -f $name,$d.dText)
  if ($d.note) { $s += (" | note={0}" -f $d.note) }
  return $s
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("BENCH REPEAT SUMMARY (OBSERVED grounding/consistency + verification delta from scoreboard)")
$lines.Add(("Runs: {0}" -f $summary.runs))
$lines.Add(("BenchProfile: {0}" -f $summary.benchProfile))
$lines.Add(("PassRate(basic): {0:P2}" -f $summary.passRate_basic))
$lines.Add("")

$lines.Add("[CONFLICT] deltas (orch - single)")
$lines.Add((LineCI "grounding.delta_avgCitations(meta.orchestra.citations)" $ciG))
$lines.Add((LineD  "grounding.delta_avgCitations" $esG))
$lines.Add((LineCI "consistency.delta_avgSelected(injectionLog.selected)" $ciC))
$lines.Add((LineD  "consistency.delta_avgSelected" $esC))
$lines.Add((LineCI "hallucination.delta_failRate(scoreboard.window.verification.failRate)" $ciH1d))
$lines.Add((LineD  "hallucination.delta_failRate" $esH1d))
$lines.Add((LineCI "hallucination.delta_weightedFailScore(scoreboard.window.verification.weightedFailWindow.score)" $ciH2d))
$lines.Add((LineD  "hallucination.delta_weightedFailScore" $esH2d))
$lines.Add("")

$lines.Add("[VERDICT]")
$lines.Add(("conflict.grounding_win={0} (rule: CI.lo>0)" -f $summary.verdict.conflict.grounding_win))
$lines.Add(("conflict.consistency_win={0} (rule: CI.lo>0)" -f $summary.verdict.conflict.consistency_win))
$lines.Add(("conflict.hallucination_win_failRate={0} (rule: CI.hi<0)" -f $summary.verdict.conflict.hallucination_win_failRate))
$lines.Add(("conflict.hallucination_win_weighted={0} (rule: CI.hi<0)" -f $summary.verdict.conflict.hallucination_win_weighted))
$lines.Add("")

$lines.Add("Latest rows (first 5):")
$lines.Add((($rows | Select-Object -First 5 | Format-Table -AutoSize | Out-String -Width 400)))

Write-AtomicUtf8 -LiteralPath $sumTxt   -Content ($lines -join "`r`n")
Write-AtomicUtf8 -LiteralPath $sumJson  -Content (($summary | ConvertTo-Json -Depth 40))
Write-AtomicUtf8 -LiteralPath $rowsJson -Content (($rows | ConvertTo-Json -Depth 15))