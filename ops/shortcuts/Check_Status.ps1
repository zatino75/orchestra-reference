Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location C:\Users\User\Desktop\orchestra

try {
  $r = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8000/api/status" -TimeoutSec 5
  $r | ConvertTo-Json -Depth 20
} catch {
  "STATUS FAIL: $($_.Exception.Message)"
  exit 1
}