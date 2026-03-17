Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 어디서 실행하든 항상 core 디렉터리 기준으로 동작
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $here
try {
  Write-Host ("PWD(core): " + (Get-Location).Path)
  Write-Host ("PSVersion: " + $PSVersionTable.PSVersion.ToString())

  $py = (Get-Command python -ErrorAction SilentlyContinue)
  if (-not $py) { throw "python not found in PATH" }

  Write-Host ""
  Write-Host "RUN: python -m pip install -q requests jsonschema"
  python -m pip install -q requests jsonschema

  $t = Join-Path (Get-Location).Path "tools\verify_contract.py"
  if (-not (Test-Path -LiteralPath $t)) { throw ("FAIL: missing " + $t) }

  Write-Host ""
  Write-Host "RUN: python tools/verify_contract.py"
  python tools/verify_contract.py
}
finally {
  Pop-Location
}
