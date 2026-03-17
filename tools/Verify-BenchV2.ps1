param(
  [Parameter(Mandatory=$true)][string]$OutDir,
  [Parameter(Mandatory=$false)][string]$BaseUrl = "http://localhost:8000",
  [Parameter(Mandatory=$false)][string]$ProjectId = "dev"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert([bool]$cond,[string]$msg){
  if(-not $cond){ throw ("ASSERT FAIL: {0}" -f $msg) }
}

function Ensure-Dir([string]$dirPath) {
  if (-not (Test-Path -LiteralPath $dirPath)) { New-Item -ItemType Directory -Path $dirPath -Force | Out-Null }
}

function Write-AtomicUtf8([string]$fullPath, [string]$content) {
  $dir = Split-Path -Parent $fullPath
  Ensure-Dir $dir
  $tmp = Join-Path -Path $dir -ChildPath (".tmp_{0}_{1}.txt" -f ([Guid]::NewGuid().ToString("N")), (Get-Date).ToString("yyyyMMdd_HHmmss.fff"))
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($tmp, $content, $utf8NoBom)
  if (Test-Path -LiteralPath $fullPath) { Remove-Item -LiteralPath $fullPath -Force }
  Move-Item -LiteralPath $tmp -Destination $fullPath -Force
}

function Is-NonEmptyString([object]$v){
  return ($v -is [string]) -and ($v.Trim().Length -gt 0)
}

function Get-Prop([object]$obj,[string]$name){
  if($null -eq $obj){ return $null }
  $p = $obj.PSObject.Properties[$name]
  if($null -eq $p){ return $null }
  $p.Value
}

function Read-Json([string]$path){
  Assert (Test-Path -LiteralPath $path) ("json not found: {0}" -f $path)
  (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Try-ParseJsonString([object]$v){
  if($v -isnot [string]){ return $v }
  $s = $v.Trim()
  if($s.StartsWith("{") -or $s.StartsWith("[")){
    try { return ($s | ConvertFrom-Json) } catch { return $v }
  }
  return $v
}

function Force-Array([object]$v){
  if($null -eq $v){ return [object[]]@() }

  $x = Try-ParseJsonString $v
  if($null -eq $x){ return [object[]]@() }

  if($x -is [System.Array]){ return [object[]]$x }

  if($x -is [System.Collections.IDictionary]){
    $list = New-Object System.Collections.Generic.List[object]
    foreach($k in $x.Keys){ $list.Add($x[$k]) }
    return [object[]]$list.ToArray()
  }

  if($x -is [System.Collections.IList]){
    $list = New-Object System.Collections.Generic.List[object]
    foreach($it in $x){ $list.Add($it) }
    return [object[]]$list.ToArray()
  }

  return [object[]]@($x)
}

function As-NumberOrNull([object]$v){
  if($null -eq $v){ return $null }
  if($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]){ return [double]$v }
  if($v -is [string]){
    $s = $v.Trim()
    if($s.Length -eq 0){ return $null }
    try { return [double]$s } catch { return $null }
  }
  return $null
}

function Get-DerivedValue([object]$resp,[string]$key){
  foreach($d in (Force-Array (Get-Prop $resp "derived"))){
    if((Get-Prop $d "key") -eq $key){ return (Get-Prop $d "value") }
  }
  $null
}

function Normalize-Attempts([object]$attemptsRaw){
  $x = Try-ParseJsonString $attemptsRaw
  if($null -eq $x){ return [object[]]@() }
  return (Force-Array $x)
}

function Validate-Attempt([object]$a,[string]$where){
  Assert ($null -ne $a) ("attempt is null at {0}" -f $where)

  $attemptNo = Get-Prop $a "attempt_no"
  if($null -eq $attemptNo){ $attemptNo = Get-Prop $a "attemptNo" }
  $attemptNo2 = As-NumberOrNull $attemptNo
  Assert ($null -ne $attemptNo2) ("attempt_no must be number at {0}" -f $where)

  $lat = As-NumberOrNull (Get-Prop $a "latency_ms")
  Assert ($null -ne $lat) ("latency_ms must be number at {0}" -f $where)

  $st = [string](Get-Prop $a "status")
  $out = [string](Get-Prop $a "outcome")
  Assert ($st.Trim().Length -gt 0) ("status missing at {0}" -f $where)
  Assert ($out.Trim().Length -gt 0) ("outcome missing at {0}" -f $where)
}

function Validate-AdapterAttemptsDerived([object]$resp,[string]$where,[string]$dumpPath){
  $aa = Get-DerivedValue $resp "adapter_attempts"
  Assert ($null -ne $aa) ("derived.adapter_attempts missing at {0}" -f $where)

  $runs = Force-Array $aa
  Assert ($runs.Length -ge 1) ("adapter_attempts must have >=1 entry at {0}" -f $where)

  for($i=0; $i -lt $runs.Length; $i++){
    $r = $runs[$i]
    $p = [string](Get-Prop $r "provider")
    $m = [string](Get-Prop $r "model")
    Assert ($p.Trim().Length -gt 0) ("adapter_attempts[{0}].provider missing at {1}" -f $i, $where)
    Assert ($m.Trim().Length -gt 0) ("adapter_attempts[{0}].model missing at {1}" -f $i, $where)

    $attempts = Normalize-Attempts (Get-Prop $r "attempts")
    if($attempts.Length -lt 1){
      $payload = [ordered]@{
        where = $where
        meta = Get-Prop $resp "meta"
        derived_adapter_attempts_raw = $aa
        normalized_runs = $runs
        bad_index = $i
      } | ConvertTo-Json -Depth 80
      Write-AtomicUtf8 $dumpPath $payload
      throw ("ASSERT FAIL: adapter_attempts[{0}].attempts must be non-empty array at {1}. Dumped: {2}" -f $i, $where, $dumpPath)
    }

    for($j=0; $j -lt $attempts.Length; $j++){
      Validate-Attempt $attempts[$j] ("{0}::adapter_attempts[{1}].attempts[{2}]" -f $where, $i, $j)
    }
  }

  $true
}

function Validate-SummaryV2([object]$s,[string]$where){
  $need = @(
    "outDir","total_cases","orchestra_wins","win_rate",
    "avg_orch_real_evidence_rate","avg_single_real_evidence_rate",
    "single_provider","orchestra_providers",
    "avg_single_conflict_rate","avg_orch_conflict_rate",
    "avg_single_attempts_error_rate","avg_orch_attempts_error_rate",
    "single_chosen_success_rate","orch_chosen_success_rate",
    "avg_single_chosen_latency_ms","avg_orch_chosen_latency_ms"
  )
  foreach($k in $need){
    Assert ($null -ne (Get-Prop $s $k)) ("summary.{0} missing at {1}" -f $k, $where)
  }
  Assert (Is-NonEmptyString (Get-Prop $s "outDir")) ("summary.outDir empty at {0}" -f $where)
  $tc = As-NumberOrNull (Get-Prop $s "total_cases")
  Assert (($null -ne $tc) -and ($tc -ge 1)) ("summary.total_cases must be >=1 at {0}" -f $where)

  $op = Force-Array (Get-Prop $s "orchestra_providers")
  Assert ($op.Length -ge 1) ("summary.orchestra_providers must be array with >=1 at {0}" -f $where)
  $true
}

function Validate-RowV2([object]$row,[string]$where){
  Assert ($null -ne $row) ("row null at {0}" -f $where)
  Assert (Is-NonEmptyString (Get-Prop $row "case_id")) ("case_id missing at {0}" -f $where)

  $single = Get-Prop $row "single"
  $orch = Get-Prop $row "orchestra"
  Assert ($null -ne $single) ("single missing at {0}" -f $where)
  Assert ($null -ne $orch) ("orchestra missing at {0}" -f $where)

  foreach($k in @("conflict_rate","attempts_error_rate","chosen_success","chosen_latency_ms")){
    Assert ($null -ne (Get-Prop $single $k)) ("single.{0} missing at {1}" -f $k, $where)
    Assert ($null -ne (Get-Prop $orch $k)) ("orchestra.{0} missing at {1}" -f $k, $where)
  }
  $true
}

# =========================
# Main
# =========================
Assert (Is-NonEmptyString $OutDir) "OutDir empty"
Assert (Test-Path -LiteralPath $OutDir) ("OutDir not found: {0}" -f $OutDir)
Assert (Is-NonEmptyString $BaseUrl) "BaseUrl empty"
Assert (Is-NonEmptyString $ProjectId) "ProjectId empty"

# A) Health
try {
  Invoke-RestMethod -Method Get -Uri ($BaseUrl.TrimEnd("/") + "/health") | Out-Null
} catch {
  throw ("Server health check failed: {0}" -f $_.Exception.Message)
}

# B) api/chat adapter_attempts shape
$threadId  = ("verify_" + ([Guid]::NewGuid().ToString("N")).Substring(0,8))
$bodyObj = [ordered]@{
  projectId = $ProjectId
  threadId  = $threadId
  mode      = "orchestra"
  providers = @("openai","openai")
  messages  = @([ordered]@{ role="user"; content="Return only:`na=1`nb=2" })
}
$body = ($bodyObj | ConvertTo-Json -Depth 30)
$resp = Invoke-RestMethod -Method Post -Uri ($BaseUrl.TrimEnd("/") + "/api/chat") -ContentType "application/json" -Body $body
Assert ($resp.ok -eq $true) "api/chat returned ok=false"

$dumpRoot = Join-Path (Get-Location).Path "artifacts\verify"
Ensure-Dir $dumpRoot
$dumpPath = Join-Path $dumpRoot ("adapter_attempts_fail_{0}.json" -f (Get-Date).ToString("yyyyMMdd_HHmmss.fff"))
Validate-AdapterAttemptsDerived $resp "api/chat" $dumpPath | Out-Null

# C) Bench outputs
$summaryPath = Join-Path $OutDir "summary.json"
$resultsPath = Join-Path $OutDir "results.json"
$summary = Read-Json $summaryPath
$results = Read-Json $resultsPath

Validate-SummaryV2 $summary "summary.json" | Out-Null

$rows = Force-Array $results
Assert ($rows.Length -ge 1) "results.json has no rows"
Validate-RowV2 $rows[0] "results[0]" | Out-Null

# D) report
$report = [ordered]@{
  ok = $true
  outDir = $OutDir
  checked = [ordered]@{
    health = $true
    api_adapter_attempts_shape = $true
    summary_v2 = $true
    row_v2 = $true
  }
  sample = [ordered]@{
    total_rows = $rows.Length
    first_case_id = (Get-Prop $rows[0] "case_id")
    win_rate = (Get-Prop $summary "win_rate")
    avg_orch_real_evidence_rate = (Get-Prop $summary "avg_orch_real_evidence_rate")
    avg_single_real_evidence_rate = (Get-Prop $summary "avg_single_real_evidence_rate")
  }
}

$verifyDir = Join-Path (Split-Path -Parent $OutDir) "verify"
Ensure-Dir $verifyDir
$reportPath = Join-Path $verifyDir ("verify_{0}.json" -f (Get-Date).ToString("yyyyMMdd_HHmmss.fff"))
Write-AtomicUtf8 $reportPath ($report | ConvertTo-Json -Depth 80)

[pscustomobject]@{
  ok = $true
  outDir = $OutDir
  report = $reportPath
  sample = $report.sample
}