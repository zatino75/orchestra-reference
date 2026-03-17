Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-AbsPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { throw "Resolve-AbsPath: Path is empty" }

  # 상대경로는 현재 위치(.Path) 기준으로 절대경로화
  $base = (Get-Location).Path
  $p = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $base $Path }

  $full = [System.IO.Path]::GetFullPath($p)

  $dir = [System.IO.Path]::GetDirectoryName($full)
  if ([string]::IsNullOrWhiteSpace($dir)) { throw "Resolve-AbsPath: DirectoryName is empty (full=$full)" }
  if (-not (Test-Path $dir)) { throw "Resolve-AbsPath: Directory not found: $dir" }

  return $full
}

function Get-Sha256Hex([string]$Path) {
  $sha = Get-FileHash -Algorithm SHA256 -LiteralPath $Path
  return ($sha.Hash ?? "").ToLowerInvariant()
}

function Write-AtomicUtf8 {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Content
  )

  $ErrorActionPreference = "Stop"

  if ([string]::IsNullOrWhiteSpace($Path)) { throw "Write-AtomicUtf8: Path is empty" }

  $full = Resolve-AbsPath $Path
  $dir  = [System.IO.Path]::GetDirectoryName($full)
  $name = [System.IO.Path]::GetFileName($full)

  if ([string]::IsNullOrWhiteSpace($dir))  { throw "Write-AtomicUtf8: DirectoryName is empty (full=$full)" }
  if ([string]::IsNullOrWhiteSpace($name)) { throw "Write-AtomicUtf8: FileName is empty (full=$full)" }

  # 임시파일/백업파일은 반드시 같은 폴더(동일 볼륨 원자성 보장)
  $tmp = Join-Path $dir (".__tmp__" + $name + "." + [Guid]::NewGuid().ToString("N") + ".tmp")
  $bak = Join-Path $dir (".__bak__" + $name + "." + (Get-Date -Format "yyyyMMdd_HHmmss") + ".bak")

  # UTF-8 (BOM 없음)
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

  # 1) tmp에 기록
  [System.IO.File]::WriteAllText($tmp, $Content, $utf8NoBom)
  if (-not (Test-Path -LiteralPath $tmp)) { throw "Write-AtomicUtf8: temp file not created: $tmp" }

  # 2) 검증(길이 + 해시)
  $newLen = (Get-Item -LiteralPath $tmp).Length
  if ($newLen -le 0 -and ($Content.Length -gt 0)) {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    throw "Write-AtomicUtf8: temp file length invalid: $newLen"
  }

  $tmpHash = Get-Sha256Hex $tmp
  if ([string]::IsNullOrWhiteSpace($tmpHash)) {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    throw "Write-AtomicUtf8: temp hash empty: $tmp"
  }

  $oldHash = $null
  if (Test-Path -LiteralPath $full) { $oldHash = Get-Sha256Hex $full }

  # 3) 원자 교체 (backupPath는 절대 null 금지)
  if (Test-Path -LiteralPath $full) {
    [System.IO.File]::Replace($tmp, $full, $bak, $true) | Out-Null
    Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue
  } else {
    Move-Item -LiteralPath $tmp -Destination $full -Force
  }

  # 4) 최종 검증
  if (-not (Test-Path -LiteralPath $full)) { throw "Write-AtomicUtf8: target not found after write: $full" }

  $newHash = Get-Sha256Hex $full
  if ([string]::IsNullOrWhiteSpace($newHash)) { throw "Write-AtomicUtf8: new hash empty (full=$full)" }
  if ($newHash -ne $tmpHash) { throw "Write-AtomicUtf8: verify failed (hash mismatch) full=$full" }

  if ($oldHash -ne $null -and $oldHash -eq $newHash) {
    Write-Host "[Write-AtomicUtf8] NOTE: content hash unchanged: $full"
  } else {
    Write-Host "[Write-AtomicUtf8] OK: $full ($newLen bytes)"
  }

  return $full
}