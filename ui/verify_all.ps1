Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $MyInvocation.MyCommand.Path  # ...\orchestra\ui

Push-Location $here
try {
  Write-Host "RUN: verify_ui_render.ps1"
  pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here "verify_ui_render.ps1")

  Write-Host ""
  Write-Host "RUN: verify_ui_contract.ps1"
  pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here "verify_ui_contract.ps1")

  Write-Host ""
  Write-Host "DONE: verify_all.ps1"
}
finally {
  Pop-Location
}