param(
  [string]$Base = "http://127.0.0.1:8000",
  [string]$ProjectId = "p_smoke",
  [switch]$RouterScorecard
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$Msg) { throw $Msg }

function HttpJson([string]$Url) {
  try {
    $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 15
    return ($r.Content | ConvertFrom-Json)
  } catch {
    Fail ("HTTP/JSON 실패: " + $Url + " :: " + $_.Exception.Message)
  }
}

function Get-StatusOk($st) {
  # top-level ok
  try {
    if ($null -ne $st.PSObject.Properties["ok"]) { return [bool]$st.ok }
  } catch { }
  # meta.ok
  try {
    if ($null -ne $st.PSObject.Properties["meta"] -and $st.meta -ne $null) {
      if ($null -ne $st.meta.PSObject.Properties["ok"]) { return [bool]$st.meta.ok }
    }
  } catch { }
  return $false
}

Write-Host "== check_health =="
Write-Host ("Base: {0}" -f $Base)

$st = HttpJson ("$Base/api/status")

if (-not ((Get-StatusOk $st) -eq $true)) {
  Fail "/api/status ok=false (top-level ok 또는 meta.ok 둘 다 false/없음)"
}

# 간단 요약 출력(있으면)
try {
  if ($null -ne $st.PSObject.Properties["meta"] -and $st.meta -ne $null) {
    $m = $st.meta
    if ($null -ne $m.PSObject.Properties["service"]) { Write-Host ("service: {0}" -f $m.service) }
    if ($null -ne $m.PSObject.Properties["uptime_s"]) { Write-Host ("uptime_s: {0}" -f $m.uptime_s) }
    if ($null -ne $m.PSObject.Properties["router"] -and $m.router -ne $null) {
      if ($null -ne $m.router.PSObject.Properties["mode"]) { Write-Host ("router.mode: {0}" -f $m.router.mode) }
      if ($null -ne $m.router.PSObject.Properties["chat_path"]) { Write-Host ("router.chat_path: {0}" -f $m.router.chat_path) }
    }
  }
} catch { }

if ($RouterScorecard) {
  Write-Host "== RouterScorecard (probe) =="
  $u = "$Base/api/metrics"
  try {
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 10
    Write-Host ("OK: {0} ({1})" -f $u, $r.StatusCode)
  } catch {
    Write-Host ("MISS: {0}" -f $u)
  }
}

Write-Host "PASS"