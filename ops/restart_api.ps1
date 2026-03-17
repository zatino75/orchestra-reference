Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location C:\Users\User\Desktop\orchestra
. .\ops\_net.ps1

Kill-Port 8000 | Out-Null
pwsh -NoProfile -ExecutionPolicy Bypass -File .\ops\start_server.ps1