param(
  [string]$Endpoint = "http://127.0.0.1:8000/api/chat",
  [string]$Provider = "claude",
  [string]$Prompt = "meta verify: pong",
  [int]$TimeoutSec = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$body = @{
  provider = $Provider
  model    = ""
  messages = @(@{ role="user"; content=$Prompt })
}

$json = $body | ConvertTo-Json -Depth 30 -Compress
$r = Invoke-RestMethod -Method Post -Uri $Endpoint -ContentType "application/json" -Body $json -TimeoutSec $TimeoutSec

Write-Host ""
Write-Host "=== TOP LEVEL KEYS ==="
$r.PSObject.Properties.Name | Sort-Object | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "=== META TOP KEYS ==="
$r.meta.PSObject.Properties.Name | Sort-Object | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "=== ORCHESTRA SUMMARY ==="
$orch = $null
try { $orch = $r.meta.orchestra } catch { $orch = $null }

if ($null -eq $orch) {
  Write-Host "meta.orchestra: (missing)"
} else {
  $mode = $null; $lat = $null; $cerr = $null; $cmsg = $null
  try { $mode = $orch.mode } catch {}
  try { $lat  = $orch.latency_ms } catch {}
  try { $cerr = $orch.conductor.error } catch {}
  try { $cmsg = $orch.conductor.error_msg } catch {}

  Write-Host ("mode: {0}" -f $mode)
  Write-Host ("latency_ms: {0}" -f $lat)
  Write-Host ("conductor.error: {0}" -f $cerr)
  Write-Host ("conductor.error_msg: {0}" -f $cmsg)
}

Write-Host ""
Write-Host "=== META.ORCHESTRA JSON (short) ==="
$j = ($orch | ConvertTo-Json -Depth 30 -Compress)
if ($j.Length -gt 1600) { $j = $j.Substring(0,1600) + " ...[truncated]" }
Write-Host $j