param(
  [string]$BaseUrl = "http://127.0.0.1:8000",
  [string]$ProjectId = "",
  [string]$ThreadPrefix = "bench",
  [string[]]$Providers = @("openai","claude","gemini","perplexity","deepseek")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-Id { [Guid]::NewGuid().ToString("N").Substring(0,12) }

if ([string]::IsNullOrWhiteSpace($ProjectId)) { $ProjectId = "proj_" + (New-Id) }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path (Get-Location).Path ("ops\bench_out_{0}_{1}" -f $ProjectId, $ts)
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

function Post-Chat {
  param(
    [Parameter(Mandatory=$true)][string]$Mode,
    [Parameter(Mandatory=$true)][string]$ThreadId,
    [Parameter(Mandatory=$true)][string]$Message
  )

  $body = @{
    projectId = $ProjectId
    threadId  = $ThreadId
    message   = $Message
    mode      = $Mode
    provider  = ($Providers | Select-Object -First 1)
    providers = $Providers
  } | ConvertTo-Json -Depth 20

  Invoke-RestMethod -Method Post -Uri ($BaseUrl.TrimEnd("/") + "/api/chat") -ContentType "application/json" -Body $body
}

function Get-Scoreboard {
  Invoke-RestMethod -Method Get -Uri ($BaseUrl.TrimEnd("/") + "/api/_debug/scoreboard?projectId=$ProjectId")
}

# 70 fixed prompts (ASCII-only)
$prompts = @(
"Summarize the project goal in 2 sentences.",
"Define Evidence/Claims/Decisions/Derived in one line each.",
"Extract key-value claim pairs from: 'Backend port is 8000 and frontend is 5173.'",
"Give 3 reasons why injection must run at least once per request.",
"Propose 3 minimal judge rules for conflict resolution (pairKey).",
"Explain conditions for Decision stability under repeated questions.",
"Suggest 2 auxiliary metrics besides failRate for hallucination reduction.",
"Give 2 exceptions where old decisions should persist despite recency weighting.",
"Give 2 examples that violate the 'minimal processing' rule for Evidence.",
"List 5 required fields to always store in Derived.",
"Explain single vs orchestra differences from a logging perspective.",
"Can judgeApplied be true when conflictsDetected is empty? answer and explain.",
"Explain meaning and side effects of PROMOTE_THRESHOLD=2.",
"Give 2 issues if DECAY_HALFLIFE_SEC is too short.",
"Give 2 cases where entity matching matters more than TF-IDF for scoring.",
"Explain a conflict: A) port 8000 B) port 9000",
"Pros/cons of pairKey as key::value vs hashed key.",
"With verification budget=5, suggest 1 way to reduce starvation.",
"How would you index project pool and threads together?",
"Define difference between qualityScoreRaw and qualityScore."
)

for ($i=21; $i -le 70; $i++) {
  $prompts += ("Test question #{0}: Extract claim pairs like key{0}=value{0} and explain possible conflicts." -f $i)
}

try {
  Invoke-RestMethod -Method Post -Uri ($BaseUrl.TrimEnd("/") + "/api/_debug/baseline/commit?projectId=$ProjectId") | Out-Null
} catch { }

$rows = @()
$idx = 0

foreach ($p in $prompts) {
  $idx++
  $threadSingle = "{0}_s" -f $ThreadPrefix
  $threadOrch   = "{0}_o" -f $ThreadPrefix

  $r1 = $null; $r2 = $null
  $e1 = $null; $e2 = $null

  try { $r1 = Post-Chat -Mode "single"    -ThreadId $threadSingle -Message $p } catch { $e1 = $_.Exception.Message }
  try { $r2 = Post-Chat -Mode "orchestra" -ThreadId $threadOrch   -Message $p } catch { $e2 = $_.Exception.Message }

  $rows += [pscustomobject]@{
    idx = $idx
    prompt = $p
    single_ok = [bool]$r1
    orchestra_ok = [bool]$r2
    single_error = $e1
    orchestra_error = $e2
    single_winner = $r1.winner
    orchestra_winner = $r2.winner
    orchestra_provider_count = @($r2.providers).Count
    orchestra_citations_count = @($r2.meta.orchestra.citations).Count
    orchestra_conflicts = @($r2.meta.orchestra.debug.injectionLog.conflictsDetected).Count
  }

  $fn1 = Join-Path $outDir ("single_{0:000}.json" -f $idx)
  $fn2 = Join-Path $outDir ("orchestra_{0:000}.json" -f $idx)
  if ($r1) { ($r1 | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $fn1 -Encoding utf8 }
  if ($r2) { ($r2 | ConvertTo-Json -Depth 40) | Set-Content -LiteralPath $fn2 -Encoding utf8 }
}

$score = $null
try { $score = Get-Scoreboard } catch { $score = @{ ok=$false; error=$_.Exception.Message } }

($rows  | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $outDir "summary_rows.json") -Encoding utf8
($score | ConvertTo-Json -Depth 30) | Set-Content -LiteralPath (Join-Path $outDir "scoreboard.json")  -Encoding utf8

"`n[bench done]"
"ProjectId: $ProjectId"
"OutDir: $outDir"