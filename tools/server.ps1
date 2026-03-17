# 파워셀덮어쓰기
param(
  [Parameter(Position=0)]
  [ValidateSet("status","stop","start","reboot")]
  [string]$Action = "status"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Find-OrchestraRoot {
  param([string]$StartDir = (Get-Location).Path)

  $dir = (Resolve-Path $StartDir).Path
  while ($true) {
    $core = Join-Path $dir "core\app.py"
    $ui   = Join-Path $dir "ui\package.json"
    if ((Test-Path -LiteralPath $core) -and (Test-Path -LiteralPath $ui)) { return $dir }

    $parent = Split-Path -Parent $dir
    if ([string]::IsNullOrWhiteSpace($parent) -or ($parent -eq $dir)) {
      throw ("프로젝트 루트를 찾지 못했습니다. 시작 위치={0}" -f $StartDir)
    }
    $dir = $parent
  }
}

function Get-ListeningPids {
  param([Parameter(Mandatory=$true)][int]$Port)

  $conns = @()
  try { $conns = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop) }
  catch { $conns = @() }

  return @(
    $conns |
      Where-Object { $_.OwningProcess -and $_.OwningProcess -gt 0 } |
      Select-Object -ExpandProperty OwningProcess -Unique
  )
}

function Show-Port {
  param([Parameter(Mandatory=$true)][int]$Port)

  $pids = @(Get-ListeningPids -Port $Port)
  if ($pids.Count -eq 0) {
    Write-Host ("Port {0}: FREE" -f $Port)
    return
  }

  $names = @()
  foreach ($procId in @($pids)) {
    try {
      $p = Get-Process -Id $procId -ErrorAction Stop
      $names += ("{0}({1})" -f $p.ProcessName, $p.Id)
    } catch {
      $names += ("PID({0})" -f $procId)
    }
  }
  Write-Host ("Port {0}: IN-USE -> {1}" -f $Port, ($names -join ", "))
}

function Stop-PortOwner {
  param([Parameter(Mandatory=$true)][int]$Port)

  $pids = @(Get-ListeningPids -Port $Port)
  if ($pids.Count -eq 0) {
    Write-Host ("[OK] Port {0}: LISTEN 없음" -f $Port)
    return
  }

  foreach ($procId in @($pids)) {
    try {
      $p = Get-Process -Id $procId -ErrorAction Stop
      Write-Host ("[KILL] Port {0} PID {1} Name {2}" -f $Port, $procId, $p.ProcessName)
      Stop-Process -Id $procId -Force -ErrorAction Stop
    } catch {
      Write-Host ("[WARN] Port {0} PID {1} - {2}" -f $Port, $procId, $_.Exception.Message)
    }
  }

  Start-Sleep -Milliseconds 250
  $after = @(Get-ListeningPids -Port $Port)
  if ($after.Count -eq 0) { Write-Host ("[OK] Port {0}: 정리 완료" -f $Port) }
  else { Write-Host ("[WARN] Port {0}: 아직 LISTEN PID {1}" -f $Port, ($after -join ",")) }
}

function Start-Backend8000 {
  param([Parameter(Mandatory=$true)][string]$Root)

  Stop-PortOwner -Port 8000

  $py = Join-Path $Root ".venv\Scripts\python.exe"
  if (-not (Test-Path -LiteralPath $py)) { $py = "python" }

  $cmd = @("-m","uvicorn","core.app:app","--host","127.0.0.1","--port","8000")
  Write-Host ("[BACKEND] {0} {1}" -f $py, ($cmd -join " "))

  Start-Process -FilePath $py -ArgumentList $cmd -WorkingDirectory $Root -WindowStyle Normal | Out-Null
}

function Start-Frontend5173 {
  param([Parameter(Mandatory=$true)][string]$Root)

  $uiDir = Join-Path $Root "ui"
  if (-not (Test-Path -LiteralPath (Join-Path $uiDir "package.json"))) {
    throw ("ui\package.json not found: {0}" -f $uiDir)
  }

  Stop-PortOwner -Port 5173

  Write-Host ("[FRONTEND] dir={0}" -f $uiDir)
  # 포트 고정(5173만 사용)
  $arg = "/c npm run dev -- --host 127.0.0.1 --port 5173"
  Start-Process -FilePath "cmd.exe" -ArgumentList $arg -WorkingDirectory $uiDir -WindowStyle Normal | Out-Null
}

$root = Find-OrchestraRoot

switch ($Action) {
  "status" {
    Write-Host ("ROOT={0}" -f $root)
    Show-Port -Port 8000
    Show-Port -Port 5173
  }
  "stop" {
    Stop-PortOwner -Port 8000
    Stop-PortOwner -Port 5173
    Show-Port -Port 8000
    Show-Port -Port 5173
  }
  "start" {
    Start-Backend8000  -Root $root
    Start-Frontend5173 -Root $root
    Show-Port -Port 8000
    Show-Port -Port 5173
  }
  "reboot" {
    Stop-PortOwner -Port 8000
    Stop-PortOwner -Port 5173
    Start-Backend8000  -Root $root
    Start-Frontend5173 -Root $root
    Show-Port -Port 8000
    Show-Port -Port 5173
  }
}