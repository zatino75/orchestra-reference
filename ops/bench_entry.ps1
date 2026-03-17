param(
  [string]$Base = "http://127.0.0.1:8000",
  [string]$ProjectId = "__bench__",
  [string]$ThreadId = "t01",
  [string]$TestsetPathLike = "server\data\tests\testset.jsonl",
  [string]$MarkerKey = "bench_run_id",
  [int[]]$PostRunTailCandidates = @(1600000, 3000000, 6000000, 12000000, 24000000),
  [string]$ReportRelDir = "server\data\logs"
)

$ErrorActionPreference = "Stop"
function Count-Any {
  param([object]$X)
  if ($null -eq $X) { return 0 }

  try {
    # has Count property (arrays, hashtables, collections, etc.)
    if ($X.PSObject -and ($X.PSObject.Properties.Name -contains "Count")) {
      return [int]$X.Count
    }
  } catch { }

  # fallback: treat as scalar or non-countable enumerable
  return [int]@($X).Count
}
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

function Try-GetIntProp {
  param([Parameter(Mandatory=$true)][object]$Obj,[Parameter(Mandatory=$true)][string]$PropName)
  $p = $Obj.PSObject.Properties.Match($PropName) | Select-Object -First 1
  if ($null -eq $p) { return @{ has=$false; value=$null } }
  $raw = $p.Value
  if ($null -eq $raw) { return @{ has=$true; value=$null } }
  try { return @{ has=$true; value=[int]$raw } } catch { return @{ has=$true; value=$null } }
}

function Get-CountsValue {
  param([object]$CountsObj,[string]$Key,[int]$Default=0)
  if ($null -eq $CountsObj) { return $Default }
  try { $v = $CountsObj.$Key; if ($null -eq $v) { return $Default }; return [int]$v } catch { return $Default }
}

function Parse-JsonSafe {
  param([string]$Line)
  try { return ($Line | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Extract-ReqIdFromObj {
  param([Parameter(Mandatory=$true)][object]$Obj)
  if ($null -ne $Obj.reqId -and ($Obj.reqId.ToString().Length -gt 0)) { return $Obj.reqId.ToString() }
  if ($null -ne $Obj.runId -and ($Obj.runId.ToString().Length -gt 0)) { return $Obj.runId.ToString() }
  if ($null -ne $Obj.req_id -and ($Obj.req_id.ToString().Length -gt 0)) { return $Obj.req_id.ToString() }
  return $null
}

function Extract-CountsFromObj {
  param([Parameter(Mandatory=$true)][object]$Obj)
  if ($null -ne $Obj.counts) { return $Obj.counts }
  return $null
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

function Collect-BenchLinesFromFinalizedTail {
  param(
    [Parameter(Mandatory=$true)][string]$FinalizedPath,
    [Parameter(Mandatory=$true)][string]$MarkerKey,
    [Parameter(Mandatory=$true)][string]$BenchRunId,
    [Parameter(Mandatory=$true)][string[]]$ExpectCaseIds,
    [Parameter(Mandatory=$true)][int[]]$TailCandidates
  )

  $needleBench = """$MarkerKey"":""$BenchRunId"""

  foreach ($n in $TailCandidates) {
    $tail = Get-FileTailText -Path $FinalizedPath -Chars $n
    $lines = $tail -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 -and $_ -like "*$needleBench*" }

    $found = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($ln in $lines) {
      $obj = Parse-JsonSafe -Line $ln
      if ($null -eq $obj -or $null -eq $obj.meta -or $null -eq $obj.meta.caseId) { continue }
      [void]$found.Add($obj.meta.caseId.ToString())
    }

    $missing = @()
    foreach ($cid in $ExpectCaseIds) { if (-not $found.Contains($cid)) { $missing += $cid } }

    if ($missing.Count -eq 0) {
      return @{ ok=$true; tailChars=$n; lines=$lines; missing=@() }
    }
  }

  $maxN = ($TailCandidates | Measure-Object -Maximum).Maximum
  $tail2 = Get-FileTailText -Path $FinalizedPath -Chars $maxN
  $lines2 = $tail2 -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 -and $_ -like "*$needleBench*" }

  $found2 = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($ln in $lines2) {
    $obj = Parse-JsonSafe -Line $ln
    if ($null -eq $obj -or $null -eq $obj.meta -or $null -eq $obj.meta.caseId) { continue }
    [void]$found2.Add($obj.meta.caseId.ToString())
  }

  $missing2 = @()
  foreach ($cid in $ExpectCaseIds) { if (-not $found2.Contains($cid)) { $missing2 += $cid } }

  return @{ ok=$false; tailChars=$maxN; lines=$lines2; missing=$missing2 }
}

function Ensure-Directory {
  param([Parameter(Mandatory=$true)][string]$DirPath)
  if (-not (Test-Path -LiteralPath $DirPath)) {
    New-Item -ItemType Directory -Path $DirPath | Out-Null
  }
}

function Write-AtomicUtf8Fallback {
  param([Parameter(Mandatory=$true)][string]$FullPath,[Parameter(Mandatory=$true)][string]$Content)
  $dir = Split-Path -Parent $FullPath
  Ensure-Directory -DirPath $dir
  $tmp = Join-Path $dir (".tmp_" + [Guid]::NewGuid().ToString("N") + "_" + (Split-Path -Leaf $FullPath))
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($tmp, $Content, $utf8NoBom)
  Move-Item -LiteralPath $tmp -Destination $FullPath -Force
}

function Try-Load-StandardWriter {
  param([Parameter(Mandatory=$true)][string]$RepoRoot)
  $loaded = $false
  $loaderPath = Join-Path $RepoRoot "ops\_net.ps1"
  if (Test-Path -LiteralPath $loaderPath) {
    . $loaderPath
    $loaded = $true
  }
  $cmd = Get-Command -Name "Write-AtomicUtf8" -ErrorAction SilentlyContinue
  return @{ loader_loaded=$loaded; has_writer=($null -ne $cmd); writer_cmd=$cmd }
}

function Invoke-WriteAtomicUtf8 {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot,
    [Parameter(Mandatory=$true)][string]$PathLike,
    [Parameter(Mandatory=$true)][string]$Content,
    [Parameter(Mandatory=$true)][hashtable]$WriterInfo
  )

  $abs = $PathLike
  if (-not [System.IO.Path]::IsPathRooted($abs)) { $abs = Join-Path $RepoRoot $PathLike }
  $dir = Split-Path -Parent $abs
  Ensure-Directory -DirPath $dir

  $fallbackUsed = $true
  $used = "fallback"
  $err = $null

  try {
    if ($WriterInfo.has_writer -and $null -ne $WriterInfo.writer_cmd) {
      $params = $WriterInfo.writer_cmd.Parameters

      if ($params.ContainsKey("PathLike")) {
        Write-AtomicUtf8 -PathLike $PathLike -Content $Content
        $fallbackUsed = $false
        $used = "Write-AtomicUtf8(PathLike)"
      }
      elseif ($params.ContainsKey("LiteralPath")) {
        if ($params.ContainsKey("NoBom")) {
          Write-AtomicUtf8 -LiteralPath $abs -Content $Content -NoBom
          $used = "Write-AtomicUtf8(LiteralPath,NoBom)"
        } else {
          Write-AtomicUtf8 -LiteralPath $abs -Content $Content
          $used = "Write-AtomicUtf8(LiteralPath)"
        }
        $fallbackUsed = $false
      }
      elseif ($params.ContainsKey("Path")) {
        if ($params.ContainsKey("NoBom")) {
          Write-AtomicUtf8 -Path $abs -Content $Content -NoBom
          $used = "Write-AtomicUtf8(Path,NoBom)"
        } else {
          Write-AtomicUtf8 -Path $abs -Content $Content
          $used = "Write-AtomicUtf8(Path)"
        }
        $fallbackUsed = $false
      }
      else {
        Write-AtomicUtf8Fallback -FullPath $abs -Content $Content
      }
    }
    else {
      Write-AtomicUtf8Fallback -FullPath $abs -Content $Content
    }
  } catch {
    $err = $_.Exception.Message
    try { Write-AtomicUtf8Fallback -FullPath $abs -Content $Content } catch { }
  }

  return @{ path=$abs; fallback_used=$fallbackUsed; used=$used; error=$err }
}

# ===== main =====

$repoRoot = Find-OrxRepoRoot -StartDir (Get-Location).Path
. (Join-Path $repoRoot "ops\_writer_loader.ps1")
$null = Ensure-OrxWriter -RepoRoot $repoRoot

$finalizedPath = Join-Path $repoRoot "server\data\logs\finalized.jsonl"
$testsetPath = Resolve-OrxPath -RepoRoot $repoRoot -PathLike $TestsetPathLike

Ensure-Ok (Test-Path -LiteralPath $finalizedPath) "Missing finalized.jsonl: $finalizedPath"
Ensure-Ok (Test-Path -LiteralPath $testsetPath) "Missing testset.jsonl: $testsetPath"

$stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$guid8 = [Guid]::NewGuid().ToString("N").Substring(0,8)
$benchRunId = "bench_$stamp" + "_" + $guid8

Write-HostBlock @(
  "=== BENCH ENTRY v2_5 ==="
  "RepoRoot : $repoRoot"
  "Base     : $Base"
  "ProjectId: $ProjectId"
  "ThreadId(default): $ThreadId"
  "Testset  : $testsetPath"
  "$MarkerKey : $benchRunId"
)

$cases = Read-JsonlObjects -Path $testsetPath | Where-Object { $null -ne $_.caseId }
Ensure-Ok ((Count-Any $cases) -gt 0) "No cases with caseId in testset.jsonl"

$runStartedAt = (Get-Date)

foreach ($c in $cases) {
  $caseId = $c.caseId.ToString()
  $userText = Get-UserTextFromCase -CaseObj $c
  $th = Get-ThreadIdFromCase -CaseObj $c -DefaultThreadId $ThreadId

  $meta = [ordered]@{ $MarkerKey = $benchRunId; caseId = $caseId }

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
  $res = Invoke-WebJson -Url $url -Method "POST" -BodyObj $body -TimeoutSec 120
  if ($null -ne $res.ok -and (-not [bool]$res.ok)) { throw ("api/chat returned ok=false for caseId=" + $caseId) }
}

$expectCaseIds = $cases | ForEach-Object { $_.caseId.ToString() }

$collect = Collect-BenchLinesFromFinalizedTail `
  -FinalizedPath $finalizedPath `
  -MarkerKey $MarkerKey `
  -BenchRunId $benchRunId `
  -ExpectCaseIds $expectCaseIds `
  -TailCandidates $PostRunTailCandidates

Write-HostBlock @(
  "=== POST-RUN COLLECT ==="
  ("tail chars used         : " + $collect.tailChars)
  ("bench lines collected   : " + $(if ($null -eq $collect.lines) { 0 } else { @($collect.lines).Count }))
  ("all caseIds collected   : " + $collect.ok)
  ("missing caseIds (if any): " + (($collect.missing -join ", ")))
)

$map = @{}
$countsMap = @{}

foreach ($ln in $collect.lines) {
  $obj = Parse-JsonSafe -Line $ln
  if ($null -eq $obj -or $null -eq $obj.meta -or $null -eq $obj.meta.caseId) { continue }
  $cid = $obj.meta.caseId.ToString()
  $map[$cid] = (Extract-ReqIdFromObj -Obj $obj)
  $countsMap[$cid] = (Extract-CountsFromObj -Obj $obj)
}

$missingCase = @()
foreach ($cid in $expectCaseIds) {
  $v = $map[$cid]
  if ($null -eq $v -or $v.ToString().Length -eq 0) { $missingCase += $cid }
}

$confMismatches = @()
$confChecks = 0

foreach ($c in $cases) {
  $cid = $c.caseId.ToString()
  $cnt = $countsMap[$cid]
  $got = Get-CountsValue -CountsObj $cnt -Key "conflicts_appended" -Default 0

  $t = Try-GetIntProp -Obj $c -PropName "exp_conflicts_appended"
  if ($t.has -and $null -ne $t.value) {
    $confChecks++
    if ($got -ne $t.value) {
      $confMismatches += [pscustomobject]@{ caseId=$cid; exp=$t.value; got=$got }
    }
  }
}

$pass = $true
if (-not $collect.ok) { $pass = $false }
if ((Count-Any $missingCase) -gt 0) { $pass = $false }
if ((Count-Any $confMismatches) -gt 0) { $pass = $false }

Write-HostBlock @(
  "=== RESULT ==="
  ("cases_total            : " + (Count-Any $cases))
  ("mapping_missing        : " + (Count-Any $missingCase))
  ("conflicts_expect_checks: " + $confChecks)
  ("conflicts_mismatches   : " + (Count-Any $confMismatches))
  ("PASS                  : " + $pass)
)

if ((Count-Any $missingCase) -gt 0) {
  Write-HostBlock @("Missing mapping caseIds:", ($missingCase -join ", "))
}

if ((Count-Any $confMismatches) -gt 0) {
  $lines = @("Conflicts mismatches (caseId exp got):")
  foreach ($mm in $confMismatches) { $lines += (" - " + $mm.caseId + " exp=" + $mm.exp + " got=" + $mm.got) }
  Write-HostBlock $lines
}

# ===== REPORT WRITE (ALWAYS) =====
$writerInfo = Try-Load-StandardWriter -RepoRoot $repoRoot

$reportRel = Join-Path $ReportRelDir ("bench_run_" + $benchRunId + ".json")
$reportObj = [ordered]@{
  bench_run_id = $benchRunId
  marker_key   = $MarkerKey
  projectId    = $ProjectId
  threadId     = $ThreadId
  base         = $Base
  createdAt    = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  runStartedAt = $runStartedAt.ToString("yyyy-MM-dd HH:mm:ss")
  runEndedAt   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  pass         = [bool]$pass
  writer       = [ordered]@{
    loader_loaded = [bool]$writerInfo.loader_loaded
    has_writer    = [bool]$writerInfo.has_writer
    used          = $null
    fallback_used = $null
    error_last    = $null
    report_path   = $null
  }
  postrun_collect = [ordered]@{
    ok        = [bool]$collect.ok
    tailChars = [int]$collect.tailChars
    lines     = [int]$(if ($null -eq $collect.lines) { 0 } else { @($collect.lines).Count })
    missing_caseIds = @($collect.missing)
  }
  summary = [ordered]@{
    cases_total              = (Count-Any $cases)
    mapping_missing          = (Count-Any $missingCase)
    conflicts_expect_checks  = $confChecks
    conflicts_mismatches     = (Count-Any $confMismatches)
  }
  mapping = @()
  conflicts_mismatches = @()
}

foreach ($cid in $expectCaseIds) {
  $reportObj.mapping += [ordered]@{
    caseId = $cid
    reqId  = $map[$cid]
    counts = $countsMap[$cid]
  }
}

foreach ($mm in $confMismatches) {
  $reportObj.conflicts_mismatches += [ordered]@{
    caseId = $mm.caseId
    exp    = $mm.exp
    got    = $mm.got
  }
}

$reportJson = ($reportObj | ConvertTo-Json -Depth 80)
$wr = Invoke-WriteAtomicUtf8 -RepoRoot $repoRoot -PathLike $reportRel -Content $reportJson -WriterInfo $writerInfo

$reportObj.writer.used = $wr.used
$reportObj.writer.fallback_used = [bool]$wr.fallback_used
$reportObj.writer.error_last = $wr.error
$reportObj.writer.report_path = $wr.path

$reportJson2 = ($reportObj | ConvertTo-Json -Depth 80)
$wr2 = Invoke-WriteAtomicUtf8 -RepoRoot $repoRoot -PathLike $reportRel -Content $reportJson2 -WriterInfo $writerInfo

Write-HostBlock @(
  "=== REPORT ==="
  ("Report: " + $wr2.path)
  ("Writer used: " + $wr2.used)
  ("Writer fallback_used: " + $wr2.fallback_used)
  ("Writer error_last: " + ($wr2.error ?? ""))
)

if (-not $pass) {
  throw "Bench failed. bench_run_id=$benchRunId"
}

Write-HostBlock @("PASS. bench_run_id=" + $benchRunId)