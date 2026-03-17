param(
  [string]$BaseUrl = "http://127.0.0.1:8000",
  [string]$ThreadPrefix = "bench",
  [string[]]$Providers = @("openai","claude","gemini","perplexity","deepseek")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
  param([Parameter(Mandatory=$true)][string]$Path)
  $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
  return ($raw | ConvertFrom-Json -ErrorAction Stop)
}

function ArrCount {
  param($x)
  if ($null -eq $x) { return 0 }
  if ($x -is [System.Collections.IDictionary]) { return [int]$x.Count }
  if ($x -is [string]) { return 1 }
  try { return [int](@($x).Length) } catch { return 1 }
}

function Find-RepoRoot {
  param([Parameter(Mandatory=$true)][string]$StartDir)
  $cur = (Resolve-Path -LiteralPath $StartDir).Path
  while ($true) {
    if (Test-Path -LiteralPath (Join-Path $cur "ops")) {
      if (Test-Path -LiteralPath (Join-Path $cur "ops\bench_70_split.ps1")) {
        return $cur
      }
    }
    $parent = Split-Path -Parent $cur
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cur) { break }
    $cur = $parent
  }
  throw ("repo_root_not_found_from: {0}" -f $StartDir)
}

# repo root: script 위치 기준으로 위로 탐색 (CWD가 ui여도 안전)
$repoRoot = Find-RepoRoot -StartDir $PSScriptRoot

$split = Join-Path $repoRoot "ops\bench_70_split.ps1"
$judge = Join-Path $repoRoot "ops\judge_quality.ps1"

if (-not (Test-Path -LiteralPath $split)) { throw "missing: $split" }
if (-not (Test-Path -LiteralPath $judge)) { throw "missing: $judge" }

# IMPORTANT:
# CI는 conflict 하드게이트가 목적이지만,
# normal(소프트 게이트) 산출물도 남기기 위해 BenchProfile=both로 실행한다.
# verdict는 여전히 conflict(compare_report.json)로만 판단한다.

$args = @(
  "-ExecutionPolicy","Bypass",
  "-File",$split,
  "-BaseUrl",$BaseUrl,
  "-ThreadPrefix",$ThreadPrefix,
  "-BenchProfile","both"
)

$lines = & pwsh @args 2>&1
$lines | ForEach-Object { $_.ToString() } | Out-Host

$compareJson = $null
foreach ($ln in $lines) {
  $s = $ln.ToString()
  if ($s -match 'Compare JSON:\s*(.+)$') {
    $compareJson = $Matches[1].Trim()
    break
  }
}
if ([string]::IsNullOrWhiteSpace($compareJson)) {
  throw "compare_json_not_found_in_split_output"
}
if (-not (Test-Path -LiteralPath $compareJson)) {
  throw "compare_json_path_missing: $compareJson"
}

& pwsh -ExecutionPolicy Bypass -File $judge -CompareJson $compareJson | Out-Host

$cmp = Read-JsonFile -Path $compareJson
$judgeJson = Join-Path $cmp.outDir "judge_quality.json"
if (-not (Test-Path -LiteralPath $judgeJson)) { throw "missing: $judgeJson" }

$j = Read-JsonFile -Path $judgeJson
$verdict = [string]$j.decision.verdict

# normal soft-gate (NEVER affects exit code)
$normalCompareJson = Join-Path $cmp.outDir "compare_report_normal.json"
$normalJudgeJson   = Join-Path $cmp.outDir "judge_quality_normal.json"
$normalJudgeTxt    = Join-Path $cmp.outDir "judge_quality_normal.txt"

$normalLine = $null
if (Test-Path -LiteralPath $normalJudgeJson) {
  try {
    $jn = Read-JsonFile -Path $normalJudgeJson
    $softOk = [bool]$jn.soft.ok
    $warns = @()
    try { $warns = @($jn.soft.warnings) } catch { $warns = @() }

    if (-not $softOk) {
      # FIX: treat measurement failure as FAIL (still non-blocking)
      $normalLine = ("NormalSoftGate: FAIL ({0})" -f (($warns | ForEach-Object { $_ }) -join ", "))
    } else {
      $normalLine = "NormalSoftGate: OK"
    }
  } catch {
    $normalLine = "NormalSoftGate: FAIL (normal_judge_parse_error)"
  }
} elseif (Test-Path -LiteralPath $normalCompareJson) {
  $normalLine = "NormalSoftGate: FAIL (normal_compare_exists_but_normal_judge_missing)"
} else {
  $normalLine = "NormalSoftGate: FAIL (normal_profile_missing)"
}

"[ci summary]"
"RepoRoot   : $repoRoot"
"CompareJson: $compareJson"
"JudgeJson  : $judgeJson"
"JudgeTxt   : " + (Join-Path $cmp.outDir "judge_quality.txt")
if (Test-Path -LiteralPath $normalCompareJson) {
  "NormalCompareJson: $normalCompareJson"
}
if (Test-Path -LiteralPath $normalJudgeJson) {
  "NormalJudgeJson  : $normalJudgeJson"
}
if (Test-Path -LiteralPath $normalJudgeTxt) {
  "NormalJudgeTxt   : $normalJudgeTxt"
}
$normalLine
"Verdict    : $verdict"

if ($verdict -eq "PASS") { exit 0 }
exit 1