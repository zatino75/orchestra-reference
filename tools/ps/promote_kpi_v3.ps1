param(
  [string] $ProjectRoot,
  [string] $BenchDir,
  [string] $ReqLogDir,
  [double] $Eps
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($null -eq $ProjectRoot) { $ProjectRoot = "" }
if ($null -eq $BenchDir -or [string]::IsNullOrWhiteSpace($BenchDir)) { $BenchDir = "server\data\logs\_bench" }
if ($null -eq $ReqLogDir) { $ReqLogDir = "" }
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

function Has-Prop {
  param($obj, [string]$name)
  if ($null -eq $obj) { return $false }
  if ($obj -is [System.Array]) { return $false }
  return ($null -ne $obj.PSObject.Properties[$name])
}

function Get-PropValue {
  param($obj, [string]$name)
  if ($null -eq $obj) { return $null }
  if ($obj -is [System.Array]) { return $null }
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p) { return $null }
  return $p.Value
}

function To-Array {
  param($v)
  if ($null -eq $v) { return @() }
  if ($v -is [System.Array]) { return @($v) }
  return @($v)
}

function Safe-NumOrNull {
  param($v)
  if ($null -eq $v) { return $null }
  try {
    $n = [double]$v
    if ([double]::IsNaN($n) -or [double]::IsInfinity($n)) { return $null }
    return $n
  } catch { return $null }
}

function Read-JsonRaw {
  param([string] $Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  try { return ($raw | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Normalize-TextKey {
  param([string]$s)
  if ([string]::IsNullOrWhiteSpace($s)) { return "" }
  $t = $s.ToLowerInvariant()
  $t = ($t -replace "\s+", " ").Trim()
  return $t
}

function Claim-KeyFromText {
  param([string]$s)
  $t = Normalize-TextKey $s
  if ([string]::IsNullOrWhiteSpace($t)) { return "" }
  return "t:" + $t
}

function Find-ArraysByNameDeep {
  param($root, [string[]]$names)

  $found = New-Object System.Collections.Generic.List[object]

  function Walk {
    param($node)

    if ($null -eq $node) { return }

    if ($node -is [System.Array]) {
      foreach ($x in $node) { Walk $x }
      return
    }

    # object
    $props = $node.PSObject.Properties
    foreach ($p in $props) {
      $n = $p.Name
      $v = $p.Value

      if ($names -contains $n) {
        if ($v -is [System.Array]) {
          foreach ($e in $v) { [void]$found.Add($e) }
        } else {
          # sometimes single object
          [void]$found.Add($v)
        }
      }

      Walk $v
    }
  }

  Walk $root
  return @($found.ToArray())
}

function Extract-SectionBullets {
  param([string]$text, [string[]]$sectionHeads)

  if ([string]::IsNullOrWhiteSpace($text)) { return @() }

  $lines = $text -split "`r?`n"
  $out = New-Object System.Collections.Generic.List[string]

  $in = $false
  foreach ($ln in $lines) {
    $t = $ln.Trim()
    if ([string]::IsNullOrWhiteSpace($t)) { continue }

    # section start?
    foreach ($h in $sectionHeads) {
      if ($t -match ("^\s*"+[regex]::Escape($h)+"\s*[:：]?\s*$")) { $in = $true; continue }
      if ($t -match ("^\s*#+\s*"+[regex]::Escape($h)+"\s*$")) { $in = $true; continue }
    }

    # section end heuristics
    if ($in -and ($t -match "^\s*(Evidence|Claims|Decisions|Derived|Conflicts)\s*[:：]?\s*$" -and ($sectionHeads -notcontains ($t -replace "[:：]","").Trim()))) {
      $in = $false
    }

    if (-not $in) { continue }

    # bullets
    if ($t -match "^\s*[-*•]\s+(.+)$") {
      $val = $Matches[1].Trim()
      if (-not [string]::IsNullOrWhiteSpace($val)) { [void]$out.Add($val) }
      continue
    }
    if ($t -match "^\s*\d+[\.\)]\s+(.+)$") {
      $val = $Matches[1].Trim()
      if (-not [string]::IsNullOrWhiteSpace($val)) { [void]$out.Add($val) }
      continue
    }
  }

  return @($out.ToArray())
}

function Find-LatestReqLogDir {
  param([string]$ProjectRoot)
  $base = Join-Path $ProjectRoot "server\.orx_logs"
  if (-not (Test-Path -LiteralPath $base)) { return "" }
  $cand = @(Get-ChildItem -LiteralPath $base -Directory -Recurse -ErrorAction SilentlyContinue |
    Where-Object { ($_.FullName -like "*\bench\reqlog_*") -or ($_.FullName -like "*\bench\reqlogP_*") } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1)
  if ($cand.Count -gt 0) { return $cand[0].FullName }
  return ""
}

function List-RespFiles {
  param([string]$dir)
  if ([string]::IsNullOrWhiteSpace($dir)) { return @() }
  if (-not (Test-Path -LiteralPath $dir)) { return @() }
  $all = @()
  $all += @(Get-ChildItem -LiteralPath $dir -File -Filter "resp_*.json" -ErrorAction SilentlyContinue)
  $all += @(Get-ChildItem -LiteralPath $dir -File -Filter "resp_*.js"  -ErrorAction SilentlyContinue)
  $all += @(Get-ChildItem -LiteralPath $dir -File -Filter "resp_*.mjs" -ErrorAction SilentlyContinue)
  $all += @(Get-ChildItem -LiteralPath $dir -File -Filter "resp_*.cjs" -ErrorAction SilentlyContinue)
  return @($all | Sort-Object LastWriteTime)
}

# ---- main ----
$ProjectRoot = Resolve-ProjectRoot -HintRoot $ProjectRoot -BenchRel $BenchDir
$benchPath = Join-Path $ProjectRoot $BenchDir

# --- Write-Host block
Write-Host ("[promote_kpi_v3] ProjectRoot=" + $ProjectRoot)
Write-Host ("[promote_kpi_v3] BenchPath=" + $benchPath)

$benchFiles = @()
if (Test-Path -LiteralPath $benchPath) {
  $benchFiles = @(Get-ChildItem -LiteralPath $benchPath -File -Filter "bench_*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
}

# --- Write-Host block
Write-Host ("[promote_kpi_v3] BenchFiles=" + $benchFiles.Count)

# schema probe
$benchTopKeys = @()
$rowsCount = 0
$hasSummarySignals = $false
$rowsArr = @()

if ($benchFiles.Count -gt 0) {
  $b = Read-JsonRaw -Path $benchFiles[-1].FullName
  if ($null -ne $b) {
    $obj = $b
    if ($b -is [System.Array] -and $b.Length -gt 0) { $obj = $b[0] }
    if ($null -ne $obj -and $obj -isnot [System.Array]) {
      $benchTopKeys = @($obj.PSObject.Properties.Name)
      if (Has-Prop $obj "rows") {
        $rowsArr = To-Array (Get-PropValue $obj "rows")
        $rowsCount = $rowsArr.Count
        if ($rowsCount -gt 0) {
          $rk = @($rowsArr[0].PSObject.Properties.Name)
          $hasSummarySignals = (($rk -contains "log_totalConflictCount") -or ($rk -contains "runtime_claimConflictCount"))
        }
      }
    }
  }
}

# alt_metrics from rows
function Avg-OfRows {
  param($rowsArr, [string]$propName)
  $sum = 0.0
  $cnt = 0
  foreach ($r in $rowsArr) {
    if ($null -eq $r -or ($r -is [System.Array])) { continue }
    $pv = $r.PSObject.Properties[$propName]
    if ($null -eq $pv) { continue }
    $n = Safe-NumOrNull $pv.Value
    if ($null -eq $n) { continue }
    $sum += $n
    $cnt += 1
  }
  if ($cnt -le 0) { return $null }
  return ($sum / $cnt)
}

function Pct-TrueRows {
  param($rowsArr, [string]$propName)
  $t = 0
  $cnt = 0
  foreach ($r in $rowsArr) {
    if ($null -eq $r -or ($r -is [System.Array])) { continue }
    $pv = $r.PSObject.Properties[$propName]
    if ($null -eq $pv) { continue }
    $cnt += 1
    if ($pv.Value -eq $true) { $t += 1 }
  }
  if ($cnt -le 0) { return $null }
  return ([double]$t / [double]$cnt)
}

$jrPct = $null
$avgClaim = $null
$avgTotal = $null
$avgResolved = $null

if ($rowsArr.Count -gt 0) {
  $jrPct = Pct-TrueRows $rowsArr "log_judgeRequired"
  if ($null -eq $jrPct) { $jrPct = Pct-TrueRows $rowsArr "runtime_judgeRequired" }
  $avgClaim = Avg-OfRows $rowsArr "log_claimConflictCount"
  if ($null -eq $avgClaim) { $avgClaim = Avg-OfRows $rowsArr "runtime_claimConflictCount" }
  $avgTotal = Avg-OfRows $rowsArr "log_totalConflictCount"
  $avgResolved = Avg-OfRows $rowsArr "log_judgeResolvedCount"
}

# ---- evolution KPI inputs (try deep arrays first, then text heuristics) ----
$claimTexts = New-Object System.Collections.Generic.List[string]
$conflictTexts = New-Object System.Collections.Generic.List[string]

# Find reqlog dir
if ([string]::IsNullOrWhiteSpace($ReqLogDir)) {
  $ReqLogDir = Find-LatestReqLogDir -ProjectRoot $ProjectRoot
}

$usedReq = ""
$usedRespDir = ""

if (-not [string]::IsNullOrWhiteSpace($ReqLogDir)) {
  $usedReq = $ReqLogDir
  $orchDir = Join-Path $ReqLogDir "orchestra"
  $respDir = $ReqLogDir
  if (Test-Path -LiteralPath $orchDir) { $respDir = $orchDir }
  $usedRespDir = $respDir

  # --- Write-Host block
  Write-Host ("[promote_kpi_v3] ReqLogDir=" + $usedReq)
  Write-Host ("[promote_kpi_v3] RespDir=" + $usedRespDir)

  $respFiles = List-RespFiles -dir $respDir

  # --- Write-Host block
  Write-Host ("[promote_kpi_v3] RespFiles=" + $respFiles.Count)

  foreach ($rf in $respFiles) {
    $o = Read-JsonRaw -Path $rf.FullName
    if ($null -eq $o) { continue }

    # 1) deep arrays by key name
    $claimsDeep = Find-ArraysByNameDeep -root $o -names @("claims")
    foreach ($c in $claimsDeep) {
      if ($c -is [string]) {
        if (-not [string]::IsNullOrWhiteSpace($c)) { [void]$claimTexts.Add($c) }
      } else {
        $t = Get-PropValue $c "text"
        if ([string]::IsNullOrWhiteSpace([string]$t)) { $t = Get-PropValue $c "content" }
        if (-not [string]::IsNullOrWhiteSpace([string]$t)) { [void]$claimTexts.Add([string]$t) }
      }
    }

    $confDeep = Find-ArraysByNameDeep -root $o -names @("conflicts")
    foreach ($x in $confDeep) {
      if ($x -is [string]) {
        if (-not [string]::IsNullOrWhiteSpace($x)) { [void]$conflictTexts.Add($x) }
      } else {
        $t = Get-PropValue $x "text"
        if ([string]::IsNullOrWhiteSpace([string]$t)) { $t = Get-PropValue $x "summary" }
        if (-not [string]::IsNullOrWhiteSpace([string]$t)) { [void]$conflictTexts.Add([string]$t) }
      }
    }

    # 2) text heuristics from text/content
    $txt = Get-PropValue $o "text"
    if ([string]::IsNullOrWhiteSpace([string]$txt)) { $txt = Get-PropValue $o "content" }
    if (-not [string]::IsNullOrWhiteSpace([string]$txt)) {
      $cs = Extract-SectionBullets -text ([string]$txt) -sectionHeads @("Claims", "Claim", "클레임", "주장")
      foreach ($c in $cs) { [void]$claimTexts.Add($c) }

      $xs = Extract-SectionBullets -text ([string]$txt) -sectionHeads @("Conflicts", "Conflict", "충돌", "모순")
      foreach ($x in $xs) { [void]$conflictTexts.Add($x) }
    }
  }
}

# Compute repeat + canonicalization from claimTexts (heuristic)
$totalClaims = $claimTexts.Count
$repeatAvail = ($totalClaims -gt 0)
$canonAvail = ($totalClaims -gt 0)

$repeatRate = $null
$canonRate = $null
$repeatInstances = 0
$uniqueClaims = 0

if ($repeatAvail) {
  $map = @{}
  foreach ($c in $claimTexts) {
    $k = Claim-KeyFromText $c
    if ([string]::IsNullOrWhiteSpace($k)) { continue }
    if ($map.ContainsKey($k)) { $map[$k] = $map[$k] + 1 } else { $map[$k] = 1 }
  }
  $uniqueClaims = $map.Keys.Count
  $repeatInstances = [Math]::Max(0, ($totalClaims - $uniqueClaims))
  $repeatRate = [double]$repeatInstances / [double]$totalClaims

  # canonicalization proxy: unique/total (0..1). (Higher => better canonicalization)
  $canonRate = [double]$uniqueClaims / [double]([Math]::Max(1, $totalClaims))
}

# conflict recurrence from conflictTexts (heuristic)
$totalConf = $conflictTexts.Count
$recurAvail = ($totalConf -gt 0)
$recurRate = $null
$resolvedPairKeys = 0
$recurrentPairKeys = 0

if ($recurAvail) {
  $cmap = @{}
  foreach ($x in $conflictTexts) {
    $k = Normalize-TextKey $x
    if ([string]::IsNullOrWhiteSpace($k)) { continue }
    if ($cmap.ContainsKey($k)) { $cmap[$k] = $cmap[$k] + 1 } else { $cmap[$k] = 1 }
  }
  $resolvedPairKeys = $cmap.Keys.Count
  $recurrentPairKeys = (@($cmap.Keys | Where-Object { $cmap[$_] -ge 2 })).Count
  if ($resolvedPairKeys -gt 0) { $recurRate = [double]$recurrentPairKeys / [double]$resolvedPairKeys } else { $recurRate = 0.0 }
}

([pscustomobject]@{
  ok = $true
  projectRoot = $ProjectRoot
  benchDir = $benchPath
  benchFiles = $benchFiles.Count

  schema = [pscustomobject]@{
    benchTopKeys = $benchTopKeys
    rowsCount = $rowsCount
    hasSummarySignals = $hasSummarySignals
    note = "Your bench rows are scalar-only; evolution KPIs must be derived from reqlog resp text/meta unless arrays exist."
  }

  totals = [pscustomobject]@{
    rows = $rowsCount
    claimTexts = $totalClaims
    conflictTexts = $totalConf
  }

  promote_kpi_v3 = [pscustomobject]@{
    repeat_claim = [pscustomobject]@{
      available = $repeatAvail
      reason = $(if ($repeatAvail) { "Heuristic from resp text/meta" } else { "No Claims found in resp text/meta (no claims arrays and no Claims section bullets)." })
      totalInstances = $totalClaims
      repeatInstances = $repeatInstances
      rate = $repeatRate
    }
    canonicalization = [pscustomobject]@{
      available = $canonAvail
      reason = $(if ($canonAvail) { "Proxy unique/total from extracted claim texts" } else { "No Claims extracted" })
      checks = $totalClaims
      canonicalKeys = $uniqueClaims
      kept = $uniqueClaims
      rate = $canonRate
    }
    conflict_recurrence = [pscustomobject]@{
      available = $recurAvail
      reason = $(if ($recurAvail) { "Heuristic from Conflicts section/arrays" } else { "No Conflicts extracted" })
      resolvedPairKeys = $resolvedPairKeys
      recurrentPairKeys = $recurrentPairKeys
      rate = $recurRate
    }
  }

  alt_metrics = [pscustomobject]@{
    available = ($rowsArr.Count -gt 0)
    judgeRequired_pct = $jrPct
    avg_runtime_or_log_claimConflictCount = $avgClaim
    avg_log_totalConflictCount = $avgTotal
    avg_log_judgeResolvedCount = $avgResolved
  }

  debug = [pscustomobject]@{
    reqlogDir = $usedReq
    respDir = $usedRespDir
  }
}) | ConvertTo-Json -Depth 60