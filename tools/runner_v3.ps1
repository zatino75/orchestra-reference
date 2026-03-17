Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$msg) { throw $msg }
function Pass([string]$msg) { Write-Host ("PASS: " + $msg) }

function Read-JsonlAll([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { return @() }
  $out = @()
  foreach ($ln in (Get-Content -LiteralPath $p -ErrorAction Stop)) {
    if (-not $ln) { continue }
    try { $out += ($ln | ConvertFrom-Json -ErrorAction Stop) } catch {}
  }
  return $out
}

function Read-JsonlTail([string]$p, [int]$n = 1) {
  if (-not (Test-Path -LiteralPath $p)) { return @() }
  $out = @()
  foreach ($ln in (Get-Content -LiteralPath $p -Tail $n -ErrorAction Stop)) {
    if (-not $ln) { continue }
    try { $out += ($ln | ConvertFrom-Json -ErrorAction Stop) } catch {}
  }
  return $out
}

function Http-GetJson([string]$url) {
  try {
    return Invoke-RestMethod -Method Get -Uri $url
  } catch {
    $ex = $_.Exception
    $status = -1
    $body = ""
    try {
      if ($ex.Response -and ($ex.Response -is [System.Net.HttpWebResponse])) {
        $resp = [System.Net.HttpWebResponse]$ex.Response
        $status = [int]$resp.StatusCode
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $sr.ReadToEnd()
        $sr.Close()
      }
    } catch {}
    if ($status -ne -1) {
      Write-Host ("HTTP_STATUS = " + $status)
      if ($body) { Write-Host "HTTP_BODY ="; Write-Host $body } else { Write-Host "HTTP_BODY = (empty)" }
    } else {
      Write-Host ("HTTP_ERROR = " + $ex.Message)
    }
    throw
  }
}

function Http-PostJson([string]$url, [string]$projectId, [string]$threadId, [string]$message) {
  $obj = [ordered]@{
    project_id = $projectId
    thread_id  = $threadId
    message    = $message
  }
  $json  = $obj | ConvertTo-Json -Depth 10
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  try {
    return Invoke-RestMethod -Method Post -Uri $url -ContentType "application/json; charset=utf-8" -Body $bytes
  } catch {
    $ex = $_.Exception
    $status = -1
    $body = ""
    try {
      if ($ex.Response -and ($ex.Response -is [System.Net.HttpWebResponse])) {
        $resp = [System.Net.HttpWebResponse]$ex.Response
        $status = [int]$resp.StatusCode
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $sr.ReadToEnd()
        $sr.Close()
      }
    } catch {}
    if ($status -ne -1) {
      Write-Host ("HTTP_STATUS = " + $status)
      if ($body) { Write-Host "HTTP_BODY ="; Write-Host $body } else { Write-Host "HTTP_BODY = (empty)" }
    } else {
      Write-Host ("HTTP_ERROR = " + $ex.Message)
    }
    throw
  }
}

function Paths([string]$root, [string]$projectId) {
  $base = Join-Path $root (".orx_store/projects/{0}" -f $projectId)
  return @{
    base     = $base
    evidence = (Join-Path $base "evidence.jsonl")
    claims   = (Join-Path $base "claims.jsonl")
    decisions= (Join-Path $base "decisions.jsonl")
    inject   = (Join-Path $base "inject_log.jsonl")
    promote  = (Join-Path $base "promote_log.jsonl")
    derived  = (Join-Path $base "derived.jsonl")
  }
}

$root = Get-Location
$BaseUrl   = "http://127.0.0.1:8000"
$StatusUrl = $BaseUrl + "/api/status"
$ChatUrl   = $BaseUrl + "/api/chat"

# preflight
$st = Http-GetJson $StatusUrl
if (-not $st.ok) { Fail "preflight: status ok=false" }
Pass "preflight ok"

# TEST1
$P="P_TEST1"; $T="T_MAIN"
$r1 = Http-PostJson $ChatUrl $P $T "TEST1: evidence 저장 검증"
if (-not $r1.ok) { Fail "TEST1: chat ok=false" }
$pp = Paths $root $P
if (-not (Test-Path -LiteralPath $pp.evidence)) { Fail "TEST1: evidence.jsonl not found" }
$e = (Read-JsonlTail $pp.evidence 1 | Select-Object -First 1)
if (-not $e) { Fail "TEST1: evidence tail parse failed" }
if ($e.sourceType -ne "user") { Fail "TEST1: sourceType not user" }
Pass "TEST1 ok"

# TEST2
$P="P_TEST2"; $T="T_MAIN"; $m="TEST2_FEATURE는 작동한다"
[void](Http-PostJson $ChatUrl $P $T $m)
Start-Sleep -Milliseconds 120
[void](Http-PostJson $ChatUrl $P $T $m)
Start-Sleep -Milliseconds 120
[void](Http-PostJson $ChatUrl $P $T $m)
$pp = Paths $root $P
$claims = Read-JsonlAll $pp.claims
$cands = $claims | Where-Object { [string]$_.text -eq $m }
if (-not $cands -or $cands.Count -lt 1) { Fail "TEST2: matching claim not found" }
$best = $cands | Sort-Object {[double]($_.updatedAt)} -Descending | Select-Object -First 1
$conf = [double]($best.confidence)
if ($conf -lt 0.60) { Fail ("TEST2: confidence too low: " + $conf) }
Pass ("TEST2 ok (confidence=" + $conf.ToString("0.00") + ")")

# TEST3
$P="P_TEST3"; $T="T_MAIN"
[void](Http-PostJson $ChatUrl $P $T "T3_FEATURE는 작동한다")
Start-Sleep -Milliseconds 200
$r3b = Http-PostJson $ChatUrl $P $T "T3_FEATURE는 작동하지 않는다"
if ([int]$r3b.conflicts -lt 1) { Fail ("TEST3: conflicts too low: " + $r3b.conflicts) }
if ([int]$r3b.decisions  -lt 1) { Fail ("TEST3: decisions too low: " + $r3b.decisions) }
$pp = Paths $root $P
if (-not (Test-Path -LiteralPath $pp.decisions)) { Fail "TEST3: decisions.jsonl not found" }
Pass "TEST3 ok"

# TEST4
$P="P_TEST4"; $T="T_MAIN"
[void](Http-PostJson $ChatUrl $P $T "TEST4: inject_log 검증")
$pp = Paths $root $P
$inj = (Read-JsonlTail $pp.inject 1 | Select-Object -First 1)
if (-not $inj) { Fail "TEST4: inject_log tail parse failed" }
$rejOk = $false
foreach ($x in ($inj.rejected | ForEach-Object { $_ })) { if ($x -and $x.reason) { $rejOk = $true; break } }
if (-not $rejOk) { Fail "TEST4: rejected.reason missing" }
Pass "TEST4 ok"

# TEST5
$P="P_TEST5"; $T="T_MAIN"
[void](Http-PostJson $ChatUrl $P $T "T5_DECAY_TARGET는 유지된다")
Write-Host "TEST5: waiting 65s for decay trigger..."
Start-Sleep -Seconds 65
[void](Http-PostJson $ChatUrl $P $T "T5_DECAY_TRIGGER")
$pp = Paths $root $P
$pl = Read-JsonlAll $pp.promote
$hasDecay = $false
foreach ($x in $pl) { if ($x -and $x.type -eq "decay") { $hasDecay = $true; break } }
if (-not $hasDecay) { Fail "TEST5: promote_log missing decay" }
Pass "TEST5 ok"

# TEST6
$P="P_TEST6"; $T="T_MAIN"
$r6 = Http-PostJson $ChatUrl $P $T "TEST6: assistant_response derived 저장 검증 (runner v3 final)"
if ($null -eq $r6.PSObject.Properties["assistant_output"]) { Fail "TEST6: missing assistant_output" }
if ($null -eq $r6.PSObject.Properties["assistant_derived_id"]) { Fail "TEST6: missing assistant_derived_id" }
$aid = [string]$r6.assistant_derived_id
$pp = Paths $root $P
$hitType = Select-String -LiteralPath $pp.derived -Pattern '"outputType": "assistant_response"' -SimpleMatch -Quiet
if (-not $hitType) { Fail "TEST6: derived missing assistant_response" }
$hitId = Select-String -LiteralPath $pp.derived -Pattern ('"id": "' + $aid + '"') -SimpleMatch -Quiet
if (-not $hitId) { Fail ("TEST6: derived missing id: " + $aid) }
Pass "TEST6 ok"

Write-Host 'ALL PASS (RUNNER v3: TEST1~TEST6)'