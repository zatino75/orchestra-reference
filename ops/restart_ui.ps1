Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Location C:\Users\User\Desktop\orchestra
. .\ops\_net.ps1

Kill-Port 5173 | Out-Null

Set-Location .\ui
npm run dev