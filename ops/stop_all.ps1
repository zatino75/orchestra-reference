Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location C:\Users\User\Desktop\orchestra
. .\ops\_net.ps1

Kill-Port 5173 | Out-Null
Kill-Port 8000 | Out-Null