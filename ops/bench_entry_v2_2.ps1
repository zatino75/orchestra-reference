param(
  [string]$Base = "http://127.0.0.1:8000",
  [string]$ProjectId = "__bench__",
  [string]$ThreadId = "t01",
  [string]$TestsetPathLike = "server\data\tests\testset.jsonl",
  [string]$MarkerKey = "bench_run_id",
  [int[]]$TailCandidates = @(2000, 10000, 50000, 200000, 400000, 800000, 1200000, 1600000, 2000000, 3000000),
  [int]$PostRunBenchPresenceTailChars = 1600000
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-HostBlock { param([string[]]$Lines) Write-Host ""; $Lines | ForEach-Object { Write-Host $_ }; Write-Host "" }
function Ensure-Ok { param([bool]$Cond,[string]$Msg) if (-not $Cond) { throw $Msg } }

function Find-OrxRepoRoot {
  param([string]$StartDir)
  $d = (Resolve-Path -LiteralPath $StartDir).Path
  while ($true) {
    if ((Test-Path -LiteralPath (Join-Path $d "package.json")) -and (Test-Path -LiteralPath (Join-Path $d "server"))) { return $d }
    $p = Split-Path -Parent $d
    if ($p -eq $d) { break }
    $d = $p
  }
  throw "Repo root not found from: $StartDir"
}

function Resolve-OrxPath {
  param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$PathLike)
  $p = $PathLike
  if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $RepoRoot $PathLike }
  return (Resolve-Path -LiteralPath $p).Path
}

function Invoke-WebJson {
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][ValidateSet("GET","POST")][string]$Method,
    [object]$BodyObj = $null,
    [int]$TimeoutSec = 60
  )
  $params = @{
    Uri        = $Url
    Method     = $Method
    TimeoutSec = $TimeoutSec
    Headers    = @{ "Accept" = "application/json" }
  }
  if ($null -ne $BodyObj) {
    $params["ContentType"] = "application/json; charset=utf-8"
    $params["Body"] = ($BodyObj | ConvertTo-Json -Depth 60 -Compress)
  }
  try { return Invoke-RestMethod @params }
  catch { throw "HTTP failed: $Method $Url :: $($_.Exception.Message)" }
}

function Read-JsonlObjects {
  param([Parameter(Mandatory=$true)][string]$Path)
  Ensure-Ok (Test-Path -LiteralPath $Path) "Missing file: $Path"
  $raw = Get-Content -LiteralPath $Path -Raw
  $lines = $raw -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 }
  $out = @()
  foreach ($ln in $lines) {
    try { $out += ($ln | ConvertFrom-Json -ErrorAction Stop) } catch { }
  }
  return $out
}

function Get-FileTailText {
  param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][int]$Chars)
  $raw = Get-Content -LiteralPath $Path -Raw
  if ($raw.Length -le $Chars) { return $raw }
  return $raw.Substring($raw.Length - $Chars, $Chars)
}

function Try-GetStringProp {
  param([Parameter(Mandatory=$true)][object]$Obj,[Parameter(Mandatory=$true)][string]$PropName)
  $p = $Obj.PSObject.Properties.Match($PropName) | Select-Object -First 1
  if ($null -eq $p) { return @{ has=$false; value=$null } }
  $raw = $p.Value
  if ($null -eq $raw) { return @{ has=$true; value=$null } }
  return @{ has=$true; value=$raw.ToString() }
}

function Get-UserTextFromCase {
  param([Parameter(Mandatory=$true)][object]$CaseObj)
  $cands = @("userText","user_text","text","prompt","input","message","query")
  foreach ($k in $cands) {
    $t = Try-GetStringProp -Obj $CaseObj -PropName $k
    if ($t.has -and $null -ne $t.value -and $t.value.Trim().Length -gt 0) { return $t.value }
  }
  $cid = Try-GetStringProp -Obj $CaseObj -PropName "caseId"
  if ($cid.has -and $null -ne $cid.value -and $cid.value.Trim().Length -gt 0) { return ("case " + $cid.value) }
  return "probe"
}

function Get-ThreadIdFromCase {
  param([Parameter(Mandatory=$true)][object]$CaseObj,[Parameter(Mandatory=$true)][string]$DefaultThreadId)
  foreach ($k in @("threadId","thread_id","thread")) {
    $t = Try-GetStringProp -Obj $CaseObj -PropName $k
    if ($t.has -and $null -ne $t.value -and $t.value.Trim().Length -gt 0) { return $t.value }
  }
  return $DefaultThreadId
}

function Find-FinalizedLineByMetaMarkerAndCaseId {
  param(
    [Parameter(Mandatory=$true)][string]$FinalizedPath,
    [Parameter(Mandatory=$true)][string]$MarkerKey,
    [Parameter(Mandatory=$true)][string]$BenchRunId,
    [Parameter(Mandatory=$true)][string]$CaseId,
    [int[]]$TailCandidates,
    [int]$FallbackTailChars
  )

  $needle1 = """$MarkerKey"":""$BenchRunId"""
  $needle2 = """caseId"":""$CaseId"""

  foreach ($n in $TailCandidates) {
    $tail = Get-FileTailText -Path $FinalizedPath -Chars $n
    if (($tail -like "*$needle1*") -and ($tail -like "*$needle2*")) {
      $lines = $tail -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 }
      foreach ($ln in $lines) {
        if (($ln -like "*$needle1*") -and ($ln -like "*$needle2*")) {
          return @{ found=$true; line=$ln; tailChars=$n }
        }
      }
    }
  }

  if ($FallbackTailChars -gt 0) {
    $tail2 = Get-FileTailText -Path $FinalizedPath -Chars $FallbackTailChars
    if (($tail2 -like "*$needle1*") -and ($tail2 -like "*$needle2*")) {
      $lines2 = $tail2 -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 }
      foreach ($ln2 in $lines2) {
        if (($ln2 -like "*$needle1*") -and ($ln2 -like "*$needle2*")) {
          return @{ found=$true; line=$ln2; tailChars=$FallbackTailChars }
        }
      }
    }
  }

  return @{ found=$false; line=$null; tailChars=0 }
}

function Parse-JsonSafe {
  param([string]$Line)
  try { return ($Line | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Extract-ReqIdFromFinalizedObj {
  param([Parameter(Mandatory=$true)][object]$Obj)
  if ($null -ne $Obj.reqId -and ($Obj.reqId.ToString().Length -gt 0)) { return $Obj.reqId.ToString() }
  if ($null -ne $Obj.runId -and ($Obj.runId.ToString().Length -gt 0)) { return $Obj.runId.ToString() }
  if ($null -ne $Obj.meta -and $null -ne $Obj.meta.reqId -and ($Obj.meta.reqId.ToString().Length -gt 0)) { return $Obj.meta.reqId.ToString() }
  if ($null -ne $Obj.meta -and $null -ne $Obj.meta.runId -and ($Obj.meta.runId.ToString().Length -gt 0)) { return $Obj.meta.runId.ToString() }
  return $null
}

function Extract-CountsFromFinalizedObj {
  param([Parameter(Mandatory=$true)][object]$Obj)
  if ($null -ne $Obj.counts) { return $Obj.counts }
  if ($null -ne $Obj.finalized -and $null -ne $Obj.finalized.counts) { return $Obj.finalized.counts }
  if ($null -ne $Obj.meta -and $null -ne $Obj.meta.counts) { return $Obj.meta.counts }
  return $null
}

function Get-CountsValue {
  param([object]$CountsObj,[string]$Key,[int]$Default=0)
  if ($null -eq $CountsObj) { return $Default }
  try { $v = $CountsObj.$Key; if ($null -eq $v) { return $Default }; return [int]$v } catch { return $Default }
}

function Try-GetIntProp {
  param([Parameter(Mandatory=$true)][object]$Obj,[Parameter(Mandatory=$true)][string]$PropName)
  $p = $Obj.PSObject.Properties.Match($PropName) | Select-Object -First 1
  if ($null -eq $p) { return @{ has=$false; value=$null } }
  $raw = $p.Value
  if ($null -eq $raw) { return @{ has=$true; value=$null } }
  try { return @{ has=$true; value=[int]$raw } } catch { return @{ has=$true; value=$null } }
}

$repoRoot = Find-OrxRepoRoot -StartDir (Get-Location).Path
$finalizedPath = Join-Path $repoRoot "server\data\logs\finalized.jsonl"
$testsetPath = Resolve-OrxPath -RepoRoot $repoRoot -PathLike $TestsetPathLike

Ensure-Ok (Test-Path -LiteralPath $finalizedPath) "Missing finalized.jsonl: $finalizedPath"
Ensure-Ok (Test-Path -LiteralPath $testsetPath) "Missing testset.jsonl: $testsetPath"

$stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$guid8 = [Guid]::NewGuid().ToString("N").Substring(0,8)
$benchRunId = "bench_$stamp" + "_" + $guid8

Write-HostBlock @(
  "=== BENCH ENTRY v2_2 ==="
  "RepoRoot : $repoRoot"
  "Base     : $Base"
  "ProjectId: $ProjectId"
  "ThreadId(default): $ThreadId"
  "Testset  : $testsetPath"
  "$MarkerKey : $benchRunId"
)

$cases = Read-JsonlObjects -Path $testsetPath | Where-Object { $null -ne $_.caseId }
Ensure-Ok ($cases.Count -gt 0) "No cases with caseId in testset.jsonl"

foreach ($c in $cases) {
  $caseId = $c.caseId.ToString()
  $userText = Get-UserTextFromCase -CaseObj $c
  $th = Get-ThreadIdFromCase -CaseObj $c -DefaultThreadId $ThreadId

  $meta = [ordered]@{
    $MarkerKey = $benchRunId
    caseId     = $caseId
  }

  $body = [ordered]@{
    projectId    = $ProjectId
    threadId     = $th
    userText     = $userText
    user_text    = $userText
    caseId       = $caseId
    bench_run_id = $benchRunId
    meta         = $meta
  }

  $url = ($Base.TrimEnd("/") + "/api/chat")
  $res = Invoke-WebJson -Url $url -Method "POST" -BodyObj $body -TimeoutSec 90
  if ($null -ne $res.ok -and (-not [bool]$res.ok)) { throw ("api/chat returned ok=false for caseId=" + $caseId) }
}

$tail = Get-FileTailText -Path $finalizedPath -Chars $PostRunBenchPresenceTailChars
$needleBench = """$MarkerKey"":""$benchRunId"""
$benchPresent = ($tail -like "*$needleBench*")

Write-HostBlock @(
  "=== POST-RUN CHECK ==="
  ("finalized tail chars : " + $PostRunBenchPresenceTailChars)
  ("bench_run_id present : " + $benchPresent)
)

if (-not $benchPresent) { throw "Bench run id not found in finalized. bench_run_id=$benchRunId" }

$map = @{}
$countsMap = @{}

foreach ($c in $cases) {
  $caseId = $c.caseId.ToString()
  $hit = Find-FinalizedLineByMetaMarkerAndCaseId `
    -FinalizedPath $finalizedPath `
    -MarkerKey $MarkerKey `
    -BenchRunId $benchRunId `
    -CaseId $caseId `
    -TailCandidates $TailCandidates `
    -FallbackTailChars $PostRunBenchPresenceTailChars

  if (-not $hit.found) { $map[$caseId] = $null; $countsMap[$caseId] = $null; continue }
  $obj = Parse-JsonSafe -Line $hit.line
  if ($null -eq $obj) { $map[$caseId] = $null; $countsMap[$caseId] = $null; continue }
  $map[$caseId] = (Extract-ReqIdFromFinalizedObj -Obj $obj)
  $countsMap[$caseId] = (Extract-CountsFromFinalizedObj -Obj $obj)
}

$missingCase = @()
foreach ($c in $cases) {
  $caseId = $c.caseId.ToString()
  $v = $map[$caseId]
  if ($null -eq $v -or $v.ToString().Length -gt 0) { }
  if ($null -eq $v -or $v.ToString().Length -eq 0) { $missingCase += $caseId }
}

$confMismatches = @()
$confChecks = 0

foreach ($c in $cases) {
  $caseId = $c.caseId.ToString()
  $cnt = $countsMap[$caseId]
  $got = Get-CountsValue -CountsObj $cnt -Key "conflicts_appended" -Default 0
  $t = Try-GetIntProp -Obj $c -PropName "exp_conflicts_appended"
  if ($t.has -and $null -ne $t.value) {
    $confChecks++
    if ($got -ne $t.value) { $confMismatches += [pscustomobject]@{ caseId=$caseId; exp=$t.value; got=$got } }
  }
}

Write-HostBlock @(
  "=== RESULT ==="
  ("cases_total            : " + $cases.Count)
  ("mapping_missing        : " + $missingCase.Count)
  ("conflicts_expect_checks: " + $confChecks)
  ("conflicts_mismatches   : " + $confMismatches.Count)
)

if ($missingCase.Count -gt 0) { Write-HostBlock @("Missing mapping caseIds:", ($missingCase -join ", ")) }

if ($confMismatches.Count -gt 0) {
  $lines = @("Conflicts mismatches (caseId exp got):")
  foreach ($mm in $confMismatches) { $lines += (" - " + $mm.caseId + " exp=" + $mm.exp + " got=" + $mm.got) }
  Write-HostBlock $lines
}

if ($missingCase.Count -gt 0 -or $confMismatches.Count -gt 0) { throw "Bench failed. bench_run_id=$benchRunId" }

Write-HostBlock @("PASS. bench_run_id=" + $benchRunId)