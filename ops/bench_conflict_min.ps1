param(
  [string]$BaseUrl = "http://127.0.0.1:8000"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-AtomicUtf8 {
  param([Parameter(Mandatory=$true)][string]$LiteralPath,[Parameter(Mandatory=$true)][string]$Content)
  $fullPath = $LiteralPath
  if (-not [System.IO.Path]::IsPathRooted($fullPath)) { $fullPath = Join-Path (Get-Location).Path $fullPath }
  $dir = Split-Path -Parent $fullPath
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $tmp = Join-Path $dir ("._tmp_{0}_{1}.txt" -f ([System.IO.Path]::GetFileName($fullPath)), ([Guid]::NewGuid().ToString("N").Substring(0,10)))
  [System.IO.File]::WriteAllText($tmp, $Content, (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $tmp -Destination $fullPath -Force
}

function Write-Json([string]$Path, $Obj) {
  $json = ($Obj | ConvertTo-Json -Depth 80)
  Write-AtomicUtf8 -LiteralPath $Path -Content $json
}

function New-Id { [Guid]::NewGuid().ToString("N").Substring(0,12) }

function Invoke-JsonPost([string]$Url, [hashtable]$BodyObj) {
  $json = ($BodyObj | ConvertTo-Json -Depth 20 -Compress)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  Invoke-RestMethod -Method Post -Uri $Url -ContentType "application/json; charset=utf-8" -Body $bytes
}

function Post-Chat([string]$ProjectId,[string]$ThreadId,[string]$Message) {
  $body = @{
    projectId = $ProjectId
    threadId  = $ThreadId
    message   = $Message
    mode      = "orchestra"
    provider  = "openai"
    providers = @("openai")
  }
  Invoke-JsonPost -Url ($BaseUrl.TrimEnd("/") + "/api/chat") -BodyObj $body
}

function Get-Scoreboard([string]$ProjectId) {
  Invoke-RestMethod -Method Get -Uri ($BaseUrl.TrimEnd("/") + "/api/_debug/scoreboard?projectId=$ProjectId")
}

function Get-LastInjection([string]$ProjectId,[string]$ThreadId) {
  Invoke-RestMethod -Method Get -Uri ($BaseUrl.TrimEnd("/") + "/api/_debug/last_injection?projectId=$ProjectId&threadId=$ThreadId")
}

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path (Get-Location).Path ("bench_conflict_out_{0}" -f $ts)
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$projId = "proj_orch_conf_" + (New-Id)
$tA = "conf_a"
$tB = "conf_b"
$tC = "conf_c"

# IMPORTANT: force model output into machine-parsable single-line claims
$msgA1 = "OUTPUT EXACTLY ONE LINE, NOTHING ELSE:`nCLAIM port_backend=8000"
$msgA2 = "OUTPUT EXACTLY ONE LINE, NOTHING ELSE:`nCLAIM port_backend=8000"
$msgB1 = "OUTPUT EXACTLY ONE LINE, NOTHING ELSE:`nCLAIM port_backend=9000"
$msgB2 = "OUTPUT EXACTLY ONE LINE, NOTHING ELSE:`nCLAIM port_backend=9000"

# Trigger should explicitly mention conflict detection + judge
$msgC = @"
You MUST do conflict detection across project knowledge.
If you see multiple values for the same key, you MUST apply Judge and decide one final value.
OUTPUT EXACTLY TWO LINES, NOTHING ELSE:
FINAL port_backend=<8000_or_9000>
CONFLICT_KEYS=port_backend
"@

Post-Chat -ProjectId $projId -ThreadId $tA -Message $msgA1 | Out-Null
Post-Chat -ProjectId $projId -ThreadId $tA -Message $msgA2 | Out-Null
Post-Chat -ProjectId $projId -ThreadId $tB -Message $msgB1 | Out-Null
Post-Chat -ProjectId $projId -ThreadId $tB -Message $msgB2 | Out-Null

$r = Post-Chat -ProjectId $projId -ThreadId $tC -Message $msgC

Start-Sleep -Seconds 2

$sb = Get-Scoreboard -ProjectId $projId
$li = Get-LastInjection -ProjectId $projId -ThreadId $tC

Write-Json -Path (Join-Path $outDir "response_a1.json") -Obj (Get-LastInjection -ProjectId $projId -ThreadId $tA)
Write-Json -Path (Join-Path $outDir "response_b1.json") -Obj (Get-LastInjection -ProjectId $projId -ThreadId $tB)
Write-Json -Path (Join-Path $outDir "response_trigger.json") -Obj $r
Write-Json -Path (Join-Path $outDir "scoreboard.json") -Obj $sb
Write-Json -Path (Join-Path $outDir "last_injection.json") -Obj $li

Write-Host "OUTDIR:" $outDir
Write-Host "PROJECT:" $projId
Write-Host "THREAD_TRIGGER:" $tC