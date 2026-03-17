$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-HostBlock { param([string[]]$Lines) Write-Host ""; $Lines | ForEach-Object { Write-Host $_ }; Write-Host "" }
function Ensure-Ok { param([bool]$Cond,[string]$Msg) if (-not $Cond) { throw $Msg } }

function Invoke-WebJson {
  param(
    [Parameter(Mandatory=$true)][string]$Url,
    [Parameter(Mandatory=$true)][ValidateSet("GET","POST")][string]$Method,
    [object]$BodyObj = $null,
    [int]$TimeoutSec = 30
  )
  if ($Method -eq "GET") {
    return Invoke-RestMethod -Method Get -Uri $Url -TimeoutSec $TimeoutSec
  }
  $json = ($BodyObj | ConvertTo-Json -Depth 40)
  return Invoke-RestMethod -Method Post -Uri $Url -ContentType "application/json" -Body $json -TimeoutSec $TimeoutSec
}

function Get-LenUtc {
  param([string]$FullPath)
  if (-not (Test-Path -LiteralPath $FullPath)) { return @{ exists=$false; len=-1; mtimeUtc="<missing>"; path=$FullPath } }
  $it = Get-Item -LiteralPath $FullPath
  return @{ exists=$true; len=[int64]$it.Length; mtimeUtc=$it.LastWriteTimeUtc.ToString("o"); path=$it.FullName }
}

function New-Claims {
  param([int]$N,[string]$Prefix="__bulk__")
  $arr = @()
  for ($i=0; $i -lt $N; $i++) {
    $arr += @{ entity=("$Prefix" + $i); value=@{ i=$i; s=("v" + $i) }; source="user" }
  }
  return ,$arr
}

function Write-FileUtf8 {
  param([string]$FullPath,[string]$Content)
  $dir = Split-Path -Parent $FullPath
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllText($FullPath, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Verify-OrchestraOps {
  param(
    [Parameter(Mandatory=$true)][string]$Base,
    [Parameter(Mandatory=$true)][string]$ProjectId,
    [Parameter(Mandatory=$true)][string]$ThreadId,
    [int]$BulkN = 200
  )

  $repoRoot = (Get-Location).Path
  $chatUrl = "$Base/api/chat"
  $promoteUrl = "$Base/api/promote"

  $logsDir = Join-Path $repoRoot "server\data\logs"
  Ensure-Ok (Test-Path -LiteralPath $logsDir) ("logsDir missing: " + $logsDir)

  $canon = Join-Path $logsDir "canonical_claims.jsonl"
  $prom  = Join-Path $logsDir "promote_log.jsonl"

  $runId = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
  $outDir = Join-Path $repoRoot ("server\data\__verify_ops__\" + $runId)
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null

  Write-HostBlock @(
    "=== Verify-OrchestraOps ===",
    ("- base:      " + $Base),
    ("- projectId: " + $ProjectId),
    ("- threadId:  " + $ThreadId),
    ("- logsDir:   " + $logsDir),
    ("- outDir:    " + $outDir)
  )

  # T4
  $resp4 = Invoke-WebJson -Url $chatUrl -Method "POST" -BodyObj @{
    mode="verify_chat"; projectId=$ProjectId; threadId=$ThreadId;
    bench_run_id=("probe_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"));
    caseId="caseA"; forceConflict=$true
  } -TimeoutSec 30

  Write-FileUtf8 -FullPath (Join-Path $outDir "t4_chat.json") -Content ($resp4 | ConvertTo-Json -Depth 60)

  Ensure-Ok ($resp4.ok -eq $true) "FAIL[T4]: /api/chat ok=false"
  Ensure-Ok (([string]$resp4.buildStamp) -like "*routefix_mount_slash_v5_2*") ("FAIL[T4]: buildStamp not v5_2: " + [string]$resp4.buildStamp)
  Ensure-Ok ($resp4.PSObject.Properties.Name -contains "debug_log_targets") "FAIL[T4]: resp.debug_log_targets missing"

  $serverLogsDir = [string]$resp4.debug_log_targets.logsDir
  Ensure-Ok (-not [string]::IsNullOrWhiteSpace($serverLogsDir)) "FAIL[T4]: resp.debug_log_targets.logsDir missing"
  Ensure-Ok ($serverLogsDir -eq $logsDir) ("FAIL[T4]: server logsDir mismatch: " + $serverLogsDir)

  Write-HostBlock @(
    "OK[T4]: restart-safe base check",
    ("- buildStamp: " + [string]$resp4.buildStamp),
    ("- logsDir:    " + $serverLogsDir)
  )

  # T5
  $cases = @(
    @{ name="empty_claims_array"; body=@{ projectId=$ProjectId; threadId=$ThreadId; reqId=("g1_" + [DateTime]::UtcNow.ToString("HHmmss")); claims=@() } },
    @{ name="missing_claims";     body=@{ projectId=$ProjectId; threadId=$ThreadId; reqId=("g2_" + [DateTime]::UtcNow.ToString("HHmmss")) } },
    @{ name="blank_entity";       body=@{ projectId=$ProjectId; threadId=$ThreadId; reqId=("g3_" + [DateTime]::UtcNow.ToString("HHmmss")); claims=@(@{ entity="   "; value="x"; source="user" }) } }
  )

  $t5Results = @()
  foreach ($c in $cases) {
    $status = -1
    $err = $null
    try {
      $null = Invoke-WebJson -Url $promoteUrl -Method "POST" -BodyObj $c.body -TimeoutSec 30
      $status = 200
    } catch {
      $err = $_.Exception.Message
      try {
        $resp = $_.Exception.Response
        if ($resp -and $resp.StatusCode) { $status = [int]$resp.StatusCode } else { $status = 400 }
      } catch { $status = 400 }
    }

    $t5Results += [pscustomobject]@{ name=$c.name; status=$status; error=($err ?? "") }

    Ensure-Ok ($status -eq 400) ("FAIL[T5]: " + $c.name + " should be rejected(400), but got " + $status)

    Write-HostBlock @(
      ("OK[T5]: " + $c.name),
      ("- status: " + $status),
      ("- error: " + ($err ?? "<none>"))
    )

    $ping = Invoke-WebJson -Url $chatUrl -Method "POST" -BodyObj @{
      mode="verify_chat"; projectId=$ProjectId; threadId=$ThreadId;
      bench_run_id=("ping_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"));
      caseId="caseA"; forceConflict=$true
    } -TimeoutSec 30
    Ensure-Ok ($ping.ok -eq $true) ("FAIL[T5]: case 후 서버 ping 실패: " + $c.name)
  }

  Write-FileUtf8 -FullPath (Join-Path $outDir "t5_results.json") -Content ($t5Results | ConvertTo-Json -Depth 10)
  Write-HostBlock @("OK: T5 all green")

  # T6
  $beforeCanon6 = Get-LenUtc -FullPath $canon
  $beforeProm6  = Get-LenUtc -FullPath $prom

  $bulk = New-Claims -N $BulkN -Prefix "__bulk__"
  $reqId6 = "bulk_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $resp6 = Invoke-WebJson -Url $promoteUrl -Method "POST" -BodyObj @{
    projectId=$ProjectId; threadId=$ThreadId; reqId=$reqId6; claims=$bulk
  } -TimeoutSec 60
  $sw.Stop()

  Write-FileUtf8 -FullPath (Join-Path $outDir "t6_promote.json") -Content ($resp6 | ConvertTo-Json -Depth 60)

  Ensure-Ok ($resp6.ok -eq $true) "FAIL[T6]: /api/promote ok=false"
  Ensure-Ok ([int]$resp6.result.canonical_writes -eq $BulkN) ("FAIL[T6]: canonical_writes != ${BulkN}: " + [string]$resp6.result.canonical_writes)
  Ensure-Ok ([int]$resp6.result.promote_log_writes -eq $BulkN) ("FAIL[T6]: promote_log_writes != ${BulkN}: " + [string]$resp6.result.promote_log_writes)

  $afterCanon6 = Get-LenUtc -FullPath $canon
  $afterProm6  = Get-LenUtc -FullPath $prom

  Ensure-Ok ($afterCanon6.len -gt $beforeCanon6.len) "FAIL[T6]: canonical file not increased"
  Ensure-Ok ($afterProm6.len  -gt $beforeProm6.len)  "FAIL[T6]: promote file not increased"

  Write-HostBlock @(
    ("OK[T6]: bulk=" + $BulkN),
    ("- elapsed_ms: " + $sw.ElapsedMilliseconds),
    ("- canonical: " + $beforeCanon6.len + " -> " + $afterCanon6.len),
    ("- promote:   " + $beforeProm6.len  + " -> " + $afterProm6.len)
  )

  Write-HostBlock @(
    "DONE: Ops regress (T4~T6) all green",
    ("outDir: " + $outDir)
  )

  return [pscustomobject]@{
    ok = $true
    outDir = $outDir
    buildStamp = [string]$resp4.buildStamp
    logsDir = $logsDir
    bulkN = $BulkN
    elapsed_ms_bulk = $sw.ElapsedMilliseconds
  }
}

if ($MyInvocation.InvocationName -ne '.') {
  $base = "http://127.0.0.1:8000"
  $projectId = "__bench__"
  $threadId = "default_thread"
  $null = Verify-OrchestraOps -Base $base -ProjectId $projectId -ThreadId $threadId -BulkN 200
}