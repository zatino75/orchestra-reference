Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = "C:\Users\User\Desktop\orchestra"
Set-Location -LiteralPath $ProjectRoot

Write-Host ("PWD=" + (Get-Location).Path) -ForegroundColor Cyan

$files = @(
  "ui/src/models/orchestraSchemas.ts",
  "ui/src/utils/localStorageRepo.ts",
  "ui/src/stores/assetStore.tsx",
  "ui/src/stores/workspaceStore.tsx",
  "ui/src/components/WorkspacePanel.tsx",
  "ui/src/components/ChatView.tsx",
  "ui/src/App.tsx"
)

Write-Host "`n[1] File existence check" -ForegroundColor Yellow
$missing = @()
foreach ($f in $files) {
  if (Test-Path -LiteralPath $f) {
    Write-Host ("OK  " + $f) -ForegroundColor Green
  } else {
    Write-Host ("MISS " + $f) -ForegroundColor Red
    $missing += $f
  }
}

if ($missing.Count -gt 0) {
  Write-Host "`nMissing files found. Fix them first." -ForegroundColor Red
  exit 1
}

Write-Host "`n[2] Quick grep: imports sanity" -ForegroundColor Yellow
try {
  $hits = Select-String -Path "ui/src/**/*.ts","ui/src/**/*.tsx" -Pattern "orchestraSchemas|localStorageRepo|assetStore|workspaceStore|WorkspacePanel" -ErrorAction Stop
  Write-Host ("Hit count: " + $hits.Count) -ForegroundColor Green
} catch {
  Write-Host "Select-String failed (this is not fatal)." -ForegroundColor DarkYellow
}

Write-Host "`n[3] Try TypeScript build (best effort)" -ForegroundColor Yellow
if (Test-Path -LiteralPath "ui/package.json") {
  Push-Location "ui"
  try {
    if (Test-Path -LiteralPath "node_modules") {
      Write-Host "node_modules: OK" -ForegroundColor Green
    } else {
      Write-Host "node_modules: missing. Run: npm install" -ForegroundColor DarkYellow
    }

    # 프로젝트마다 다를 수 있어, 가능한 명령을 순서대로 시도
    $ran = $false
    if (Test-Path -LiteralPath "tsconfig.json") {
      Write-Host "Running: npx tsc -p tsconfig.json --noEmit" -ForegroundColor Cyan
      npx tsc -p tsconfig.json --noEmit
      $ran = $true
    } else {
      Write-Host "No tsconfig.json under ui/. Skipping tsc." -ForegroundColor DarkYellow
    }

    if ($ran) {
      Write-Host "TypeScript check: PASS" -ForegroundColor Green
    }
  } catch {
    Write-Host "`nTypeScript check: FAIL" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 2
  } finally {
    Pop-Location
  }
} else {
  Write-Host "No ui/package.json found. Skipping UI checks." -ForegroundColor DarkYellow
}

Write-Host "`n[4] Run instructions" -ForegroundColor Yellow
Write-Host "1) In project root: cd ui" -ForegroundColor Cyan
Write-Host "2) npm install (if needed)" -ForegroundColor Cyan
Write-Host "3) npm run dev (or your usual dev command)" -ForegroundColor Cyan
Write-Host "4) Test flow: Send -> blocks -> Archive -> open Workspace -> Use as Input -> Send" -ForegroundColor Cyan

Write-Host "`nDONE" -ForegroundColor Green