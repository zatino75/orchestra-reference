param(
  [Parameter(Mandatory=$false)]
  [string]$ProjectId = "dev",

  [Parameter(Mandatory=$false)]
  [string]$BaseUrl = "http://localhost:8000",

  [Parameter(Mandatory=$false)]
  [int]$MaxCases = 3,

  [Parameter(Mandatory=$false)]
  [string]$SingleProvider = "openai",

  # pwsh.exe 외부 호출에서도 안전하게 1토큰으로 넘기기 위해 CSV 문자열로 받습니다.
  # 예) -OrchProviders "openai,openai"
  [Parameter(Mandatory=$true)]
  [ValidateNotNullOrEmpty()]
  [string]$OrchProviders
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert([bool]$cond, [string]$msg) {
  if(-not $cond){ throw ("ASSERT FAIL: {0}" -f $msg) }
}

function Get-FullPath([string]$relativePath) {
  Join-Path (Get-Location).Path $relativePath
}

function Normalize-OutDir([object]$v){
  if($null -eq $v){ return "" }
  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])){
    try { $v = @($v)[-1] } catch { }
  }
  return ([string]$v).Trim()
}

function Parse-OrchProviders([string]$s){
  $t = ([string]$s).Trim()
  if($t.Length -eq 0){ return [string[]]@() }
  $parts = $t -split '[,;|]' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 }
  return [string[]]@($parts)
}

# -------------------------
# Resolve script paths (FULL PATH)
# -------------------------
$benchPath  = Get-FullPath "tools\Bench-OrchestraV2.ps1"
$verifyPath = Get-FullPath "tools\Verify-BenchV2.ps1"

Assert (Test-Path -LiteralPath $benchPath)  ("Bench script not found: {0}" -f $benchPath)
Assert (Test-Path -LiteralPath $verifyPath) ("Verify script not found: {0}" -f $verifyPath)

# -------------------------
# Hard parse + validate OrchProviders
# -------------------------
$orchArr = [string[]]@(Parse-OrchProviders $OrchProviders)
Assert ($orchArr.Length -ge 1) ("OrchProviders is empty after parse: '{0}'. Example: -OrchProviders 'openai,openai'" -f $OrchProviders)

# -------------------------
# A) Run Bench (same session)
# -------------------------
$outDir = & $benchPath `
  -ProjectId $ProjectId `
  -BaseUrl $BaseUrl `
  -MaxCases $MaxCases `
  -SingleProvider $SingleProvider `
  -OrchProviders $orchArr

$outDir = Normalize-OutDir $outDir
Assert ($outDir.Length -gt 0) "Bench returned empty outDir"
Assert (Test-Path -LiteralPath $outDir) ("Bench outDir not found: {0}" -f $outDir)

Write-Host ""
Write-Host ("[Bench] outDir = {0}" -f $outDir)

# -------------------------
# B) Run Verify (clean scope in new pwsh)
# -------------------------
$verifyOut = & pwsh -NoProfile -ExecutionPolicy Bypass -File $verifyPath `
  -OutDir $outDir `
  -BaseUrl $BaseUrl `
  -ProjectId $ProjectId

Write-Host ""
Write-Host "[Verify] result:"
$verifyOut

# Return outDir as the final output
$outDir