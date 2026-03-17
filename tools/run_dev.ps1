Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = "C:\Users\User\Desktop\orchestra"
Set-Location -LiteralPath $ProjectRoot

function Start-Proc {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [Parameter(Mandatory=$true)][string]$CommandLine
  )
  $cmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"Set-Location -LiteralPath '$WorkDir'; $CommandLine`""
  Write-Host ("START " + $Name + ": " + $cmd) -ForegroundColor Cyan
  Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-Command",$cmd) | Out-Null
}

Write-Host ("PWD=" + (Get-Location).Path) -ForegroundColor Cyan

# ---- 서버 실행 ----
if (Test-Path -LiteralPath "server/package.json") {
  if (!(Test-Path -LiteralPath "server/node_modules")) {
    Write-Host "[server] node_modules missing -> (cd server; npm install)" -ForegroundColor DarkYellow
  }
  Start-Proc -Name "server" -WorkDir (Join-Path $ProjectRoot "server") -CommandLine "npm run dev"
} else {
  Write-Host "[server] server/package.json not found. Server might be elsewhere." -ForegroundColor Red
}

# ---- UI 실행 ----
if (Test-Path -LiteralPath "ui/package.json") {
  if (!(Test-Path -LiteralPath "ui/node_modules")) {
    Write-Host "[ui] node_modules missing -> (cd ui; npm install)" -ForegroundColor DarkYellow
  }
  # UI가 server로 치게 하려면 VITE_API_BASE 설정
  $envLine = '$env:VITE_API_BASE="http://localhost:8787"; '
  Start-Proc -Name "ui" -WorkDir (Join-Path $ProjectRoot "ui") -CommandLine ($envLine + "npm run dev")
} else {
  Write-Host "[ui] ui/package.json not found." -ForegroundColor Red
}

Write-Host "`n--- QUICK CHECKLIST ---" -ForegroundColor Yellow
Write-Host "1) Server: http://localhost:8787/health  -> ok" -ForegroundColor Cyan
Write-Host "2) UI: open dev url (vite output)" -ForegroundColor Cyan
Write-Host "3) UI Send: 아무 문장 보내기 -> blocks 생성" -ForegroundColor Cyan
Write-Host "4) Block에서 Archive 클릭 -> Workspace 열기 -> asset 생성 확인" -ForegroundColor Cyan
Write-Host "5) Workspace에서 '이 자산으로 작업' -> input chip 생성 확인" -ForegroundColor Cyan
Write-Host "6) Send -> 서버가 assets table/code 블록으로 반영하는지 확인" -ForegroundColor Cyan
Write-Host "----------------------" -ForegroundColor Yellow