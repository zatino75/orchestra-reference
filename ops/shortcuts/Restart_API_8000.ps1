Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location C:\Users\User\Desktop\orchestra

$pid8000 = (netstat -ano | Select-String ":8000\s" | ForEach-Object { ($_ -split "\s+")[-1] } | Select-Object -First 1)
if ($pid8000) {
  "Killing :8000 PID => $pid8000"
  taskkill /PID $pid8000 /F | Out-Null
} else {
  "No process on :8000"
}

pwsh -NoProfile -ExecutionPolicy Bypass -File .\ops\start_server.ps1