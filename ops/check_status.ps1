Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Json([string]$Url) {
  try {
    return Invoke-RestMethod -Method Get -Uri $Url -TimeoutSec 10
  } catch {
    return @{ error = "$($_.Exception.Message)"; url = $Url }
  }
}

"=== /api/health ==="
Get-Json "http://127.0.0.1:8000/api/health" | ConvertTo-Json -Depth 20

"=== /api/status ==="
Get-Json "http://127.0.0.1:8000/api/status" | ConvertTo-Json -Depth 20