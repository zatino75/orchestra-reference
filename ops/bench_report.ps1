param(
  [Parameter(Mandatory=$true)][string]$OutDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
  param([Parameter(Mandatory=$true)][string]$Path)
  $raw = Get-Content -LiteralPath $Path -Raw
  return ($raw | ConvertFrom-Json -Depth 200)
}

function ArrCount {
  param($x)
  if ($null -eq $x) { return 0 }

  # IDictionary (hashtable 등)
  if ($x -is [System.Collections.IDictionary]) { return [int]$x.Count }

  # string은 단일로 취급
  if ($x -is [string]) { return 1 }

  # Array / IEnumerable
  try {
    $a = @($x)
    return [int]$a.Length
  } catch {
    return 1
  }
}

function ToArray {
  param($x)
  if ($null -eq $x) { return @() }
  if ($x -is [string]) { return @($x) }
  try { return @($x) } catch { return @($x) }
}

if (-not (Test-Path -LiteralPath $OutDir)) { throw "outdir_not_found: $OutDir" }

$rowsPath  = Join-Path $OutDir "summary_rows.json"
$scorePath = Join-Path $OutDir "scoreboard.json"

if (-not (Test-Path -LiteralPath $rowsPath))  { throw "missing: $rowsPath" }
if (-not (Test-Path -LiteralPath $scorePath)) { throw "missing: $scorePath" }

$rowsObj = Read-JsonFile -Path $rowsPath
$rows = ToArray $rowsObj

$total = ArrCount $rows
$single_ok = ArrCount (ToArray ($rows | Where-Object { $_.single_ok -eq $true }))
$orch_ok   = ArrCount (ToArray ($rows | Where-Object { $_.orchestra_ok -eq $true }))
$single_fail = $total - $single_ok
$orch_fail   = $total - $orch_ok

$avg_provider_count = 0.0
$avg_citations = 0.0
$avg_conflicts = 0.0
if ($total -gt 0) {
  $avg_provider_count = ($rows | Measure-Object -Property orchestra_provider_count -Average).Average
  $avg_citations      = ($rows | Measure-Object -Property orchestra_citations_count -Average).Average
  $avg_conflicts      = ($rows | Measure-Object -Property orchestra_conflicts -Average).Average
}

$score = Read-JsonFile -Path $scorePath
$sb = $null
$quality = $null
$delta = $null

try { $sb = $score.scoreboard } catch { $sb = $null }
if ($sb) {
  try { $quality = $sb.qualityScore } catch { $quality = $null }
  try { $delta = $sb.delta_vs_baseline } catch { $delta = $null }
}

$worst_single = ToArray ($rows | Where-Object { $_.single_ok -ne $true } | Select-Object -First 5)
$worst_orch   = ToArray ($rows | Where-Object { $_.orchestra_ok -ne $true } | Select-Object -First 5)
$top_conflicts = ToArray ($rows | Sort-Object orchestra_conflicts -Descending | Select-Object -First 10)

$report = [ordered]@{
  outDir = $OutDir
  total = $total
  success = [ordered]@{
    single_ok = $single_ok
    single_fail = $single_fail
    orchestra_ok = $orch_ok
    orchestra_fail = $orch_fail
  }
  orchestra_means = [ordered]@{
    avg_provider_count = [double]$avg_provider_count
    avg_citations_count = [double]$avg_citations
    avg_conflicts_count = [double]$avg_conflicts
  }
  scoreboard = $sb
  key_deltas = $delta
  samples = [ordered]@{
    worst_single = $worst_single
    worst_orchestra = $worst_orch
    top_conflicts = $top_conflicts
  }
}

$reportPathJson = Join-Path $OutDir "bench_report.json"
$reportPathTxt  = Join-Path $OutDir "bench_report.txt"

($report | ConvertTo-Json -Depth 80) | Set-Content -LiteralPath $reportPathJson -Encoding utf8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("BENCH REPORT")
$lines.Add("OutDir: $OutDir")
$lines.Add(("Total: {0}" -f $total))
$lines.Add("")
$lines.Add("SUCCESS")
$lines.Add(("  single_ok={0} single_fail={1}" -f $single_ok, $single_fail))
$lines.Add(("  orchestra_ok={0} orchestra_fail={1}" -f $orch_ok, $orch_fail))
$lines.Add("")
$lines.Add("ORCHESTRA MEANS (from rows)")
$lines.Add(("  avg_provider_count={0:N2}" -f $avg_provider_count))
$lines.Add(("  avg_citations_count={0:N2}" -f $avg_citations))
$lines.Add(("  avg_conflicts_count={0:N2}" -f $avg_conflicts))
$lines.Add("")
if ($quality -ne $null) {
  $lines.Add("SCOREBOARD")
  $lines.Add(("  qualityScore={0}" -f $quality))
}
if ($delta) {
  $lines.Add("")
  $lines.Add("DELTA VS BASELINE (if available)")
  foreach ($prop in $delta.PSObject.Properties) {
    $lines.Add(("  {0} = {1}" -f $prop.Name, $prop.Value))
  }
}
$lines.Add("")
$lines.Add("TOP CONFLICT PROMPTS (idx, conflicts)")
foreach ($x in $top_conflicts) {
  if ($null -eq $x) { continue }
  $lines.Add(("  idx={0} conflicts={1}" -f $x.idx, $x.orchestra_conflicts))
}

if ((ArrCount $worst_orch) -gt 0) {
  $lines.Add("")
  $lines.Add("ORCHESTRA FAILURES (first 5)")
  foreach ($x in $worst_orch) {
    if ($null -eq $x) { continue }
    $lines.Add(("  idx={0} err={1}" -f $x.idx, $x.orchestra_error))
  }
}

if ((ArrCount $worst_single) -gt 0) {
  $lines.Add("")
  $lines.Add("SINGLE FAILURES (first 5)")
  foreach ($x in $worst_single) {
    if ($null -eq $x) { continue }
    $lines.Add(("  idx={0} err={1}" -f $x.idx, $x.single_error))
  }
}

($lines -join "`n") | Set-Content -LiteralPath $reportPathTxt -Encoding utf8

"`n[report done]"
"JSON: $reportPathJson"
"TXT : $reportPathTxt"