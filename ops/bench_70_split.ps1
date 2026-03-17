param(
  [string]$BenchsetPath = ".\ops\benchsets\bench70_v001.json",
  [string]$BaseUrl = "",
  [string]$ThreadPrefix = "",
  [string[]]$Providers = @(),
  [string]$SingleProjectId = "",
  [string]$OrchProjectId = "",
  [ValidateSet("conflict","normal","both")]
  [string]$BenchProfile = "both"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-Id { [Guid]::NewGuid().ToString("N").Substring(0,12) }

function ArrCount {
  param($x)
  if ($null -eq $x) { return 0 }
  if ($x -is [System.Collections.IDictionary]) { return [int]$x.Count }
  if ($x -is [string]) { return 1 }
  try { return [int](@($x).Length) } catch { return 1 }
}

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

function To-JsonSafe { param([Parameter(Mandatory=$true)]$Obj) return ($Obj | ConvertTo-Json -Depth 80) }
function Write-JsonAtomic { param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Obj) Write-AtomicUtf8 -LiteralPath $Path -Content (To-JsonSafe -Obj $Obj) }
function Write-TextAtomic { param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Text) Write-AtomicUtf8 -LiteralPath $Path -Content $Text }

function Invoke-JsonPostBytes {
  param([Parameter(Mandatory=$true)][string]$Url,[Parameter(Mandatory=$true)][hashtable]$BodyObj)
  $json = ($BodyObj | ConvertTo-Json -Depth 30 -Compress)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  Invoke-RestMethod -Method Post -Uri $Url -ContentType "application/json; charset=utf-8" -Body $bytes
}

function Post-Chat {
  param(
    [Parameter(Mandatory=$true)][string]$ProjectId,
    [Parameter(Mandatory=$true)][string]$Mode,
    [Parameter(Mandatory=$true)][string]$ThreadId,
    [Parameter(Mandatory=$true)][string]$Message,
    [Parameter(Mandatory=$true)][string[]]$ProvidersEff,
    [Parameter(Mandatory=$true)][string]$BaseUrlEff
  )
  $bodyObj = @{
    projectId = $ProjectId
    threadId  = $ThreadId
    message   = $Message
    mode      = $Mode
    provider  = ($ProvidersEff | Select-Object -First 1)
    providers = $ProvidersEff
  }
  Invoke-JsonPostBytes -Url ($BaseUrlEff.TrimEnd("/") + "/api/chat") -BodyObj $bodyObj
}

function Get-Scoreboard { param([Parameter(Mandatory=$true)][string]$ProjectId,[Parameter(Mandatory=$true)][string]$BaseUrlEff) Invoke-RestMethod -Method Get -Uri ($BaseUrlEff.TrimEnd("/") + "/api/_debug/scoreboard?projectId=$ProjectId") }
function Commit-Baseline { param([Parameter(Mandatory=$true)][string]$ProjectId,[Parameter(Mandatory=$true)][string]$BaseUrlEff) try { Invoke-RestMethod -Method Post -Uri ($BaseUrlEff.TrimEnd("/") + "/api/_debug/baseline/commit?projectId=$ProjectId") | Out-Null } catch { } }

function Resolve-ScriptStartDir {
  if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { return $PSScriptRoot }
  $p = $null
  try { $p = $PSCommandPath } catch { $p = $null }
  if (-not [string]::IsNullOrWhiteSpace($p)) { return (Split-Path -Parent $p) }
  try { $p = $MyInvocation.MyCommand.Path } catch { $p = $null }
  if (-not [string]::IsNullOrWhiteSpace($p)) { return (Split-Path -Parent $p) }
  return (Get-Location).Path
}

function Find-RepoRoot {
  param([Parameter(Mandatory=$true)][string]$StartDir)
  if ([string]::IsNullOrWhiteSpace($StartDir)) { $StartDir = (Get-Location).Path }
  $cur = (Resolve-Path -LiteralPath $StartDir).Path
  while ($true) {
    if (Test-Path -LiteralPath (Join-Path $cur "ops")) { return $cur }
    $parent = Split-Path -Parent $cur
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cur) { break }
    $cur = $parent
  }
  throw ("repo_root_not_found_from: {0}" -f $StartDir)
}

function GetPath($obj,$path){
  $cur=$obj
  foreach($p in ($path -split "\.")){
    if($null -eq $cur){ return $null }
    try { $cur = $cur.$p } catch { return $null }
  }
  return $cur
}
function GetNum($v){ try { return [double]$v } catch { return $null } }

function _TryReadJson { param([Parameter(Mandatory=$true)][string]$Path) try { if(-not (Test-Path -LiteralPath $Path)){return $null}; (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null } }

function _Get-WindowJudgeTotalFromScoreboardObj {
  param([Parameter(Mandatory=$true)]$ScoreboardObj)
  if ($null -eq $ScoreboardObj) { return $null }
  $sb = $ScoreboardObj.scoreboard
  if ($null -eq $sb) { return $null }
  $v = $null
  try { $v = $sb.window.judgeApplied.total } catch { $v = $null }
  if ($null -ne $v -and "$v" -ne "") { return [int]$v }
  try { $v = $sb.window.conflict.resolved } catch { $v = $null }
  if ($null -ne $v -and "$v" -ne "") { return [int]$v }
  return $null
}

function DirSlug {
  param([Parameter(Mandatory=$true)][string]$ProjectId)
  if ($ProjectId -match '^proj_single_(.+)$') { return $Matches[1] }
  if ($ProjectId -match '^proj_orch_(.+)$')   { return $Matches[1] }
  return $ProjectId
}

function Ensure-Dirs {
  param([Parameter(Mandatory=$true)][string]$OutDir,[Parameter(Mandatory=$true)][string]$SinglePid,[Parameter(Mandatory=$true)][string]$OrchPid)
  $singleSlug = DirSlug -ProjectId $SinglePid
  $orchSlug   = DirSlug -ProjectId $OrchPid
  $singleDir = Join-Path $OutDir ("single_{0}" -f $singleSlug)
  $orchDir   = Join-Path $OutDir ("orch_{0}" -f $orchSlug)
  New-Item -ItemType Directory -Path $singleDir -Force | Out-Null
  New-Item -ItemType Directory -Path $orchDir -Force | Out-Null
  return @{ singleDir=$singleDir; orchDir=$orchDir }
}

function Summarize-ObservedFromOrchResponses {
  param([Parameter(Mandatory=$true)][string]$OrchDir)

  $files = @(Get-ChildItem -LiteralPath $OrchDir -Filter "orchestra_*.json" -File -ErrorAction SilentlyContinue | Sort-Object Name)
  $total = $files.Count
  $withInjectionLog = 0
  $responsesWithConflicts = 0
  $conflictsDetectedTotal = 0
  $selectedTotal = 0
  $rejectedTotal = 0
  $rejectedByReason = @{}
  $finalInjectedLenMax = $null
  $judgeAppliedCount = 0

  foreach ($f in $files) {
    $j = _TryReadJson -Path $f.FullName
    if ($null -eq $j) { continue }

    $inj = $null
    try { $inj = $j.meta.orchestra.debug.injectionLog } catch { $inj = $null }

    if ($null -ne $inj) {
      $withInjectionLog++

      $conf = $null
      try { $conf = $inj.conflictsDetected } catch { $conf = $null }
      $c = ArrCount $conf
      $conflictsDetectedTotal += $c
      if ($c -gt 0) { $responsesWithConflicts++ }

      $sel = $null
      try { $sel = $inj.selected } catch { $sel = $null }
      $selectedTotal += (ArrCount $sel)

      $rej = $null
      try { $rej = $inj.rejected } catch { $rej = $null }
      $rCount = (ArrCount $rej)
      $rejectedTotal += $rCount
      if ($rCount -gt 0) {
        foreach ($r in @($rej)) {
          $reason = $null
          try { $reason = $r.reason } catch { $reason = $null }
          if ([string]::IsNullOrWhiteSpace($reason)) { $reason = "(unknown)" }
          if (-not $rejectedByReason.ContainsKey($reason)) { $rejectedByReason[$reason] = 0 }
          $rejectedByReason[$reason] = [int]$rejectedByReason[$reason] + 1
        }
      }

      $fil = $null
      try { $fil = $inj.finalInjectedLength } catch { $fil = $null }
      if ($null -ne $fil -and "$fil" -ne "") {
        $n = $null
        try { $n = [int]$fil } catch { $n = $null }
        if ($null -ne $n) {
          if ($null -eq $finalInjectedLenMax -or $n -gt $finalInjectedLenMax) { $finalInjectedLenMax = $n }
        }
      }

      $ja = $null
      try { $ja = $j.meta.orchestra.debug.judgeApplied } catch { $ja = $null }
      if ($ja -eq $true) { $judgeAppliedCount++ }
    }
  }

  return [ordered]@{
    responses_total = $total
    responses_with_injectionLog = $withInjectionLog
    responses_with_conflicts = $responsesWithConflicts
    conflictsDetected_total = $conflictsDetectedTotal
    selected_total = $selectedTotal
    rejected_total = $rejectedTotal
    rejected_by_reason = $rejectedByReason
    finalInjectedLength_max = $finalInjectedLenMax
    judgeApplied_count_observed = $judgeAppliedCount
  }
}

function Pick-ComparableScoreboardOrDelta {
  param([Parameter(Mandatory=$true)]$ScoreboardObj)

  if ($null -eq $ScoreboardObj) { return $null }

  # Prefer delta if present (new debugRoutes behavior)
  $d = $null
  try { $d = $ScoreboardObj.delta } catch { $d = $null }
  if ($null -ne $d) { return $d }

  # fallback to scoreboard
  $s = $null
  try { $s = $ScoreboardObj.scoreboard } catch { $s = $null }
  return $s
}

function Run-Scenario {
  param(
    [Parameter(Mandatory=$true)][object]$Scenario,
    [Parameter(Mandatory=$true)][string]$OutDir,
    [Parameter(Mandatory=$true)][string]$SinglePid,
    [Parameter(Mandatory=$true)][string]$OrchPid,
    [Parameter(Mandatory=$true)][string[]]$ProvidersEff,
    [Parameter(Mandatory=$true)][string]$BaseUrlEff,
    [Parameter(Mandatory=$true)][string]$CompareJsonName,
    [Parameter(Mandatory=$true)][string]$CompareTxtName
  )

  $scenarioName = [string]$Scenario.name
  $doSeed = [bool]$Scenario.doSeedConflict
  $prompts = @($Scenario.expandedPrompts)

  $dirs = Ensure-Dirs -OutDir $OutDir -SinglePid $SinglePid -OrchPid $OrchPid
  $singleDir = $dirs.singleDir
  $orchDir   = $dirs.orchDir

  Commit-Baseline -ProjectId $SinglePid -BaseUrlEff $BaseUrlEff
  Commit-Baseline -ProjectId $OrchPid   -BaseUrlEff $BaseUrlEff

  $triggerThread = "{0}_o" -f $ThreadPrefixEff

  if ($doSeed) {
    $seedA = "{0}_oA" -f $ThreadPrefixEff
    $seedB = "{0}_oB" -f $ThreadPrefixEff
    foreach ($m in @($Scenario.seed.seedA)) { try { Post-Chat -ProjectId $OrchPid -Mode "orchestra" -ThreadId $seedA -Message $m -ProvidersEff $ProvidersEff -BaseUrlEff $BaseUrlEff | Out-Null } catch { } }
    foreach ($m in @($Scenario.seed.seedB)) { try { Post-Chat -ProjectId $OrchPid -Mode "orchestra" -ThreadId $seedB -Message $m -ProvidersEff $ProvidersEff -BaseUrlEff $BaseUrlEff | Out-Null } catch { } }
  }

  $rowsSingle = @()
  $idx = 0
  foreach ($p in $prompts) {
    $idx++
    $threadId = "{0}_s" -f $ThreadPrefixEff
    $r=$null; $e=$null
    try { $r = Post-Chat -ProjectId $SinglePid -Mode "single" -ThreadId $threadId -Message $p -ProvidersEff $ProvidersEff -BaseUrlEff $BaseUrlEff } catch { $e = $_.Exception.Message }
    $rowsSingle += [pscustomobject]@{ idx=$idx; ok=[bool]$r; error=$e;  }
    if ($r) { Write-JsonAtomic -Path (Join-Path $singleDir ("single_{0:000}.json" -f $idx)) -Obj $r }
  }

  $rowsOrch = @()
  $idx = 0
  foreach ($p in $prompts) {
    $idx++
    $threadId = $triggerThread
    $r=$null; $e=$null
    try { $r = Post-Chat -ProjectId $OrchPid -Mode "orchestra" -ThreadId $threadId -Message $p -ProvidersEff $ProvidersEff -BaseUrlEff $BaseUrlEff } catch { $e = $_.Exception.Message }
    $provCount = ArrCount $r.providers
    $citeCount = ArrCount $r.meta.orchestra.citations
    $confCount = ArrCount $r.meta.orchestra.debug.injectionLog.conflictsDetected
    $rowsOrch += [pscustomobject]@{ idx=$idx; ok=[bool]$r; error=$e; ; provider_count=$provCount; citations_count=$citeCount; conflicts=$confCount }
    if ($r) { Write-JsonAtomic -Path (Join-Path $orchDir ("orchestra_{0:000}.json" -f $idx)) -Obj $r }
  }

  $sbSingle=$null; $sbOrch=$null
  try { $sbSingle = Get-Scoreboard -ProjectId $SinglePid -BaseUrlEff $BaseUrlEff } catch { $sbSingle = @{ ok=$false; error=($_ | Out-String) } }
  try { $sbOrch   = Get-Scoreboard -ProjectId $OrchPid   -BaseUrlEff $BaseUrlEff } catch { $sbOrch   = @{ ok=$false; error=($_ | Out-String) } }

  Write-JsonAtomic -Path (Join-Path $singleDir "summary_rows.json") -Obj $rowsSingle
  Write-JsonAtomic -Path (Join-Path $orchDir   "summary_rows.json") -Obj $rowsOrch
  Write-JsonAtomic -Path (Join-Path $singleDir "scoreboard.json")   -Obj $sbSingle
  Write-JsonAtomic -Path (Join-Path $orchDir   "scoreboard.json")   -Obj $sbOrch

  $observed = Summarize-ObservedFromOrchResponses -OrchDir $orchDir
  Write-JsonAtomic -Path (Join-Path $orchDir "observed_summary.json") -Obj $observed

  $S = Pick-ComparableScoreboardOrDelta -ScoreboardObj $sbSingle
  $O = Pick-ComparableScoreboardOrDelta -ScoreboardObj $sbOrch

  $compare = [ordered]@{
    outDir = $OutDir
    benchProfile = $scenarioName
    single = [ordered]@{ projectId=$SinglePid; dir=$singleDir; scoreboard=$S }
    orchestra = [ordered]@{ projectId=$OrchPid; dir=$orchDir; scoreboard=$O; observed=$observed }
    delta_orch_minus_single = [ordered]@{}
    providers = $ProvidersEff
  }

  if ($S -and $O) {
    $keys = @(
      "qualityScore","qualityScoreRaw",
      "window.conflict.resolveRate","window.conflict.total",
      "window.verification.failRate","window.verification.weightedFailWindow.score",
      "window.grounding.avgCitableIdsCount","window.grounding.avgInjectedDecisionCount",
      "judgeApplied","conflict.total","conflict.resolved"
    )
    foreach ($k in $keys) {
      $sVal = GetPath $S $k
      $oVal = GetPath $O $k
      $sn = GetNum $sVal
      $on = GetNum $oVal
      if ($sn -ne $null -and $on -ne $null) {
        $compare.delta_orch_minus_single[$k] = [double]($on - $sn)
      } else {
        $compare.delta_orch_minus_single[$k] = [ordered]@{ single=$sVal; orchestra=$oVal; delta=$null }
      }
    }

    # Also include counts delta if present on comparable objects
    $sCounts = GetPath $S "counts"
    $oCounts = GetPath $O "counts"
    if ($sCounts -and $oCounts) {
      foreach ($ck in @("evidence","claims","decisions","derived","inject_log","judge_log","promote_log")) {
        $sv = GetNum (GetPath $sCounts $ck)
        $ov = GetNum (GetPath $oCounts $ck)
        if ($sv -ne $null -and $ov -ne $null) {
          $compare.delta_orch_minus_single["counts.$ck"] = [double]($ov - $sv)
        } else {
          $compare.delta_orch_minus_single["counts.$ck"] = [ordered]@{ single=(GetPath $sCounts $ck); orchestra=(GetPath $oCounts $ck); delta=$null }
        }
      }
    }
  }

  $compareJson = Join-Path $OutDir $CompareJsonName
  $compareTxt  = Join-Path $OutDir $CompareTxtName
  Write-JsonAtomic -Path $compareJson -Obj $compare

  $oj = _Get-WindowJudgeTotalFromScoreboardObj -ScoreboardObj $sbOrch
  $sj = _Get-WindowJudgeTotalFromScoreboardObj -ScoreboardObj $sbSingle

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("BENCH SPLIT COMPARE REPORT")
  $lines.Add(("Profile: {0}" -f $scenarioName))
  $lines.Add(("OutDir: {0}" -f $OutDir))
  $lines.Add(("SingleDir: {0}" -f (Split-Path -Leaf $singleDir)))
  $lines.Add(("OrchDir  : {0}" -f (Split-Path -Leaf $orchDir)))
  $lines.Add(("Providers: {0}" -f ($ProvidersEff -join ",")))
  $lines.Add("")
  $lines.Add("[report_patch] parse-friendly lines")
  $lines.Add(("orch.window.judgeApplied.total = {0}" -f $(if($oj -ne $null){$oj}else{"(null)"})))
  $lines.Add(("single.window.judgeApplied.total = {0}" -f $(if($sj -ne $null){$sj}else{"(null)"})))
  if ($oj -ne $null -and $sj -ne $null) { $lines.Add(("delta.window.judgeApplied.total = {0}" -f ([int]$oj - [int]$sj))) }

  # counts delta lines (if present)
  $lines.Add(("orch.counts.evidence = {0}" -f $(if($O){(GetPath $O "counts.evidence")}else{"(null)"})))
  $lines.Add(("single.counts.evidence = {0}" -f $(if($S){(GetPath $S "counts.evidence")}else{"(null)"})))
  $lines.Add(("delta.counts.evidence = {0}" -f $(if($S -and $O){([int](GetPath $O "counts.evidence") - [int](GetPath $S "counts.evidence"))}else{"(null)"})))
  $lines.Add(("orch.counts.inject_log = {0}" -f $(if($O){(GetPath $O "counts.inject_log")}else{"(null)"})))
  $lines.Add(("single.counts.inject_log = {0}" -f $(if($S){(GetPath $S "counts.inject_log")}else{"(null)"})))
  $lines.Add(("delta.counts.inject_log = {0}" -f $(if($S -and $O){([int](GetPath $O "counts.inject_log") - [int](GetPath $S "counts.inject_log"))}else{"(null)"})))

  $lines.Add("")
  $lines.Add("DELTA (orch - single)")
  foreach ($k in $compare.delta_orch_minus_single.Keys) {
    $lines.Add(("  {0} = {1}" -f $k, ($compare.delta_orch_minus_single[$k] | ConvertTo-Json -Depth 10 -Compress)))
  }

  Write-TextAtomic -Path $compareTxt -Text ($lines -join "`r`n")

  return @{ outDir=$OutDir; singleDir=$singleDir; orchDir=$orchDir; compareJson=$compareJson; compareTxt=$compareTxt }
}

$startDir = Resolve-ScriptStartDir
$repoRoot = Find-RepoRoot -StartDir $startDir

if (-not (Test-Path -LiteralPath $BenchsetPath)) { throw ("benchset not found: {0}" -f $BenchsetPath) }
$benchset = Get-Content -LiteralPath $BenchsetPath -Raw | ConvertFrom-Json

$BaseUrlEff = $BaseUrl
if ([string]::IsNullOrWhiteSpace($BaseUrlEff)) { $BaseUrlEff = [string]$benchset.defaults.baseUrl }

$ThreadPrefixEff = $ThreadPrefix
if ([string]::IsNullOrWhiteSpace($ThreadPrefixEff)) { $ThreadPrefixEff = [string]$benchset.defaults.threadPrefix }

$ProvidersEff = $Providers
if ($null -eq $ProvidersEff -or $ProvidersEff.Count -eq 0) { $ProvidersEff = @($benchset.defaults.providers) }

$allow = @{}
foreach ($p in $ProvidersEff) { $allow[$p.ToLowerInvariant()] = $true }
if (-not [string]::IsNullOrWhiteSpace($SingleProjectId)) { if ($allow.ContainsKey($SingleProjectId.ToLowerInvariant())) { $SingleProjectId = "" } }
if (-not [string]::IsNullOrWhiteSpace($OrchProjectId))   { if ($allow.ContainsKey($OrchProjectId.ToLowerInvariant()))   { $OrchProjectId   = "" } }

if ([string]::IsNullOrWhiteSpace($SingleProjectId)) { $SingleProjectId = "proj_single_" + (New-Id) }
if ([string]::IsNullOrWhiteSpace($OrchProjectId))   { $OrchProjectId   = "proj_orch_"   + (New-Id) }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outDirRoot = $null
$uiOps = Join-Path $repoRoot "ui\ops"
if (Test-Path -LiteralPath $uiOps) { $outDirRoot = $uiOps } else { $outDirRoot = Join-Path $repoRoot "ops" }
New-Item -ItemType Directory -Path $outDirRoot -Force | Out-Null
$outDir = Join-Path $outDirRoot ("bench_split_out_{0}" -f $ts)
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

function Get-ScenarioByName([object]$benchset,[string]$name) {
  foreach ($s in @($benchset.scenarios)) { if ([string]$s.name -eq $name) { return $s } }
  throw ("scenario_not_found: {0}" -f $name)
}

$primary = $null

if ($BenchProfile -eq "conflict") {
  $sc = Get-ScenarioByName -benchset $benchset -name "conflict"
  $primary = Run-Scenario -Scenario $sc -OutDir $outDir -SinglePid $SingleProjectId -OrchPid $OrchProjectId -ProvidersEff $ProvidersEff -BaseUrlEff $BaseUrlEff -CompareJsonName "compare_report.json" -CompareTxtName "compare_report.txt"
}
elseif ($BenchProfile -eq "normal") {
  $sc = Get-ScenarioByName -benchset $benchset -name "normal"
  $primary = Run-Scenario -Scenario $sc -OutDir $outDir -SinglePid $SingleProjectId -OrchPid $OrchProjectId -ProvidersEff $ProvidersEff -BaseUrlEff $BaseUrlEff -CompareJsonName "compare_report.json" -CompareTxtName "compare_report.txt"
}
elseif ($BenchProfile -eq "both") {
  $sc1 = Get-ScenarioByName -benchset $benchset -name "conflict"
  $primary = Run-Scenario -Scenario $sc1 -OutDir $outDir -SinglePid $SingleProjectId -OrchPid $OrchProjectId -ProvidersEff $ProvidersEff -BaseUrlEff $BaseUrlEff -CompareJsonName "compare_report.json" -CompareTxtName "compare_report.txt"

  $orch2   = ($OrchProjectId + "_n_" + (New-Id))
  $single2 = ($SingleProjectId + "_n_" + (New-Id))
  $sc2 = Get-ScenarioByName -benchset $benchset -name "normal"
  Run-Scenario -Scenario $sc2 -OutDir $outDir -SinglePid $single2 -OrchPid $orch2 -ProvidersEff $ProvidersEff -BaseUrlEff $BaseUrlEff -CompareJsonName "compare_report_normal.json" -CompareTxtName "compare_report_normal.txt" | Out-Null
}
else {
  throw ("unknown BenchProfile: {0}" -f $BenchProfile)
}

"`n[split bench done]"
"OutDir: $($primary.outDir)"
"SingleDir: $($primary.singleDir)"
"OrchDir  : $($primary.orchDir)"
"Compare JSON: $($primary.compareJson)"
"Compare TXT : $($primary.compareTxt)"