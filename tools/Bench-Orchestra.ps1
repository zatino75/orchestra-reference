# tools\Bench-Orchestra.ps1
param(
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [Parameter(Mandatory=$true)][string]$BaseUrl,
  [Parameter(Mandatory=$false)][string]$SingleThreadId = "bench_single",
  [Parameter(Mandatory=$false)][string]$OrchThreadId   = "bench_orch",
  [Parameter(Mandatory=$false)][string]$OutRoot = "artifacts\bench",
  [Parameter(Mandatory=$false)][string]$TestSetPath = "tools\bench\testset.json",
  [Parameter(Mandatory=$false)][int]$MaxCases = 0,
  [Parameter(Mandatory=$false)][switch]$EnablePromote,

  # === Providers (B-step: 5-model target) ===
  [Parameter(Mandatory=$false)][string]$SingleProvider = "openai",
  [Parameter(Mandatory=$false)][string[]]$OrchProviders = @("openai","claude")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FullPath([string]$relativePath) { Join-Path (Get-Location).Path $relativePath }

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

function To-JsonStable([object]$obj) { $obj | ConvertTo-Json -Depth 90 -Compress }

function New-UniqueOutDir([string]$root) {
  $full = Get-FullPath $root
  Ensure-Dir $full
  $ts = (Get-Date).ToString("yyyyMMdd_HHmmss.fff")
  $rand = ([Guid]::NewGuid().ToString("N")).Substring(0,8)
  $dir = Join-Path $full ("bench_{0}_{1}" -f $ts,$rand)
  Ensure-Dir $dir
  $dir
}

function Get-Prop([object]$obj,[string]$name){
  if($null -eq $obj){ return $null }
  $p = $obj.PSObject.Properties[$name]
  if($null -eq $p){ return $null }
  $p.Value
}

function Get-Array([object]$obj,[string]$name){
  $v = Get-Prop $obj $name
  if($null -eq $v){ return @() }
  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){ return @($v) }
  return @($v)
}

function To-StringArray([object]$v){
  if($null -eq $v){ return @() }
  if($v -is [string]){
    $s = $v.Trim()
    if($s.Length -eq 0){ return @() }
    if($s.Contains(",")){
      $parts = $s.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 }
      return @($parts)
    }
    return @($s)
  }
  if($v -is [System.Collections.IEnumerable]){
    $arr = @($v) | ForEach-Object { [string]($_) } | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 }
    if($arr.Count -eq 1 -and $arr[0].Contains(",")){
      $parts2 = $arr[0].Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 }
      return @($parts2)
    }
    return @($arr)
  }
  $one = [string]$v
  $one = $one.Trim()
  if($one.Length -eq 0){ return @() }
  if($one.Contains(",")){
    $parts3 = $one.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 }
    return @($parts3)
  }
  return @($one)
}

function Get-DerivedValue([object]$resp,[string]$key){
  foreach($d in (Get-Array $resp "derived")){
    if((Get-Prop $d "key") -eq $key){ return (Get-Prop $d "value") }
  }
  $null
}

function Get-PromoteResultSafe([object]$resp){
  Get-DerivedValue $resp "promote_result"
}

function Collect-EvidenceIds([object]$resp){
  $ids = New-Object System.Collections.Generic.List[string]
  foreach($c in (Get-Array $resp "claims")){
    $eid = Get-Prop $c "evidence_id"
    if($eid -is [string] -and $eid.Length -gt 0){ $ids.Add($eid) }
  }
  foreach($d in (Get-Array $resp "decisions")){
    $eid2 = Get-Prop $d "evidence_id"
    if($eid2 -is [string] -and $eid2.Length -gt 0){ $ids.Add($eid2) }
  }
  @($ids)
}

function Classify-Evidence([string[]]$evidenceIds){
  $prov = [ordered]@{ run=0; runs=0; consensus=0; xthread=0; other=0; total=0 }
  foreach($eid in $evidenceIds){
    $prov.total++
    if($eid.StartsWith("run:")){ $prov.run++; continue }
    if($eid.StartsWith("runs:")){ $prov.runs++; continue }
    if($eid.StartsWith("consensus:")){ $prov.consensus++; continue }
    if($eid.StartsWith("xthread:")){ $prov.xthread++; continue }
    $prov.other++
  }
  $realSum = $prov.consensus + $prov.xthread
  $realRate = 0.0
  if($prov.total -gt 0){ $realRate = [double]$realSum / [double]$prov.total }

  [ordered]@{
    provenance = $prov
    real = [ordered]@{
      sum = $realSum
      rate = $realRate
      definition = "real = consensus: + xthread:"
    }
  }
}

function Invoke-Chat([string]$baseUrl,[string]$projectId,[string]$threadId,[string]$mode,[string]$prompt,[hashtable]$extra,[string[]]$providers,[bool]$promote){
  $uri = ($baseUrl.TrimEnd("/") + "/api/chat")
  $body = [ordered]@{
    projectId = $projectId
    threadId  = $threadId
    mode      = $mode
    providers = $providers
    messages  = @([ordered]@{ role="user"; content=$prompt })
  }
  if($promote){ $body["promote"] = $true }
  if($null -ne $extra){ foreach($k in $extra.Keys){ $body[$k] = $extra[$k] } }
  $json = To-JsonStable $body
  Invoke-RestMethod -Method Post -Uri $uri -ContentType "application/json" -Body $json
}

# ===== Normalize providers FIRST (fix Count failures) =====
$SingleProvider = [string]$SingleProvider
$SingleProvider = $SingleProvider.Trim()
$OrchProvidersNorm = To-StringArray $OrchProviders

if ($ProjectId.Trim().Length -eq 0) { throw "ProjectId is empty." }
if ($BaseUrl.Trim().Length -eq 0) { throw "BaseUrl is empty." }
if ($SingleProvider.Length -eq 0) { throw "SingleProvider is empty." }
if ($null -eq $OrchProvidersNorm -or @($OrchProvidersNorm).Count -lt 1) { throw "OrchProviders must have at least 1 entry." }

$tsFull = Get-FullPath $TestSetPath
if (-not (Test-Path -LiteralPath $tsFull)) { throw ("TestSetPath not found: {0}" -f $TestSetPath) }

$test = (Get-Content -LiteralPath $tsFull -Raw | ConvertFrom-Json)
$cases = @()
foreach($c in (Get-Array $test "cases")){
  $p = Get-Prop $c "prompt"
  if($p -is [string] -and $p.Length -gt 0){ $cases += $c }
}
if(@($cases).Count -eq 0){ throw "No cases found in testset." }
if($MaxCases -gt 0 -and @($cases).Count -gt $MaxCases){ $cases = $cases[0..($MaxCases-1)] }

$outDir = New-UniqueOutDir $OutRoot
$results = New-Object System.Collections.Generic.List[object]

$idx=0
foreach($c in $cases){
  $idx++
  $caseId = Get-Prop $c "id"
  if(-not ($caseId -is [string]) -or $caseId.Trim().Length -eq 0){ $caseId = ("case_{0:000}" -f $idx) }
  $prompt = Get-Prop $c "prompt"

  $extra=@{}
  $extraFromCase = Get-Prop $c "extra"
  if($null -ne $extraFromCase){
    foreach($p in $extraFromCase.PSObject.Properties){ $extra[$p.Name] = $p.Value }
  }

  $singleResp = Invoke-Chat -baseUrl $BaseUrl -projectId $ProjectId -threadId $SingleThreadId -mode "single" -prompt $prompt -extra $extra -providers @($SingleProvider) -promote ([bool]$EnablePromote)
  $orchResp   = Invoke-Chat -baseUrl $BaseUrl -projectId $ProjectId -threadId $OrchThreadId   -mode "orchestra" -prompt $prompt -extra $extra -providers @($OrchProvidersNorm) -promote ([bool]$EnablePromote)

  $singleE = Collect-EvidenceIds $singleResp
  $orchE   = Collect-EvidenceIds $orchResp

  $singleCls = Classify-Evidence $singleE
  $orchCls   = Classify-Evidence $orchE

  $orchRealSum   = [int]($orchCls["real"]["sum"])
  $singleRealSum = [int]($singleCls["real"]["sum"])
  $deltaRealSum  = $orchRealSum - $singleRealSum

  $orchRealRate   = [double]($orchCls["real"]["rate"])
  $singleRealRate = [double]($singleCls["real"]["rate"])

  $verdict="TIE_OR_SINGLE_WINS"
  if($deltaRealSum -gt 0 -or $orchRealRate -gt $singleRealRate){ $verdict="ORCHESTRA_WINS" }

  $row = [ordered]@{
    case_id = $caseId
    prompt = $prompt
    single = [ordered]@{
      provider = $SingleProvider
      evidence = $singleCls
      evidence_ids_total = [int]$singleCls["provenance"]["total"]
      promote_result = (Get-PromoteResultSafe $singleResp)
      buildStamp = (Get-Prop $singleResp "buildStamp")
      debug_counts = (Get-Prop (Get-Prop (Get-Prop $singleResp "debug") "counts") "extracted_claims")
    }
    orchestra = [ordered]@{
      providers = @($OrchProvidersNorm)
      evidence = $orchCls
      evidence_ids_total = [int]$orchCls["provenance"]["total"]
      promote_result = (Get-PromoteResultSafe $orchResp)
      buildStamp = (Get-Prop $orchResp "buildStamp")
      debug_counts = (Get-Prop (Get-Prop (Get-Prop $orchResp "debug") "counts") "extracted_claims")
    }
    decision = [ordered]@{
      verdict = $verdict
      delta_real_evidence_sum = $deltaRealSum
      orch_real_evidence_rate = $orchRealRate
      single_real_evidence_rate = $singleRealRate
      rule = "ORCHESTRA_WINS iff delta_real_evidence_sum>0 OR orch_real_evidence_rate>single"
      real_definition = "consensus:+xthread:"
    }
  }

  $results.Add([pscustomobject]$row)

  $caseDir = Join-Path $outDir $caseId
  Ensure-Dir $caseDir
  Write-AtomicUtf8 (Join-Path $caseDir "single.response.json") (To-JsonStable $singleResp)
  Write-AtomicUtf8 (Join-Path $caseDir "orch.response.json")   (To-JsonStable $orchResp)
  Write-AtomicUtf8 (Join-Path $caseDir "bench.row.json")       (To-JsonStable $row)
}

$total = $results.Count
$wins = 0
$sumDelta = 0
$sumOrchRate = 0.0
$sumSingleRate = 0.0

foreach($r in $results){
  $dec = $r.decision
  $verdict = $dec["verdict"]
  if($verdict -eq "ORCHESTRA_WINS"){ $wins++ }

  $sumDelta += [int]$dec["delta_real_evidence_sum"]
  $sumOrchRate += [double]$dec["orch_real_evidence_rate"]
  $sumSingleRate += [double]$dec["single_real_evidence_rate"]
}

$avgOrch = 0.0
$avgSingle = 0.0
$winRate = 0.0
if($total -gt 0){
  $avgOrch = $sumOrchRate / [double]$total
  $avgSingle = $sumSingleRate / [double]$total
  $winRate = [double]$wins / [double]$total
}

$summary = [ordered]@{
  outDir = $outDir
  total_cases = $total
  orchestra_wins = $wins
  win_rate = $winRate
  delta_real_evidence_sum_total = $sumDelta
  avg_orch_real_evidence_rate = $avgOrch
  avg_single_real_evidence_rate = $avgSingle
  real_definition = "consensus:+xthread:"
  verdict_rule = "ORCHESTRA_WINS iff delta_real_evidence_sum>0 OR orch_real_evidence_rate>single"
  single_provider = $SingleProvider
  orchestra_providers = @($OrchProvidersNorm)
}

Write-AtomicUtf8 (Join-Path $outDir "summary.json") (To-JsonStable $summary)
Write-AtomicUtf8 (Join-Path $outDir "results.json") (To-JsonStable $results)

Write-Output $outDir