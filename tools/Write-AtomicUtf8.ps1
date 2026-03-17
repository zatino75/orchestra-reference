Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-AbsPath {
  param([Parameter(Mandatory=$true)][string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { throw "Path is empty." }

  $p = $Path
  if (-not [System.IO.Path]::IsPathRooted($p)) {
    $callerRoot = $script:PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($callerRoot)) {
      throw "Refusing relative path without PSScriptRoot. Pass an absolute path: '$Path'"
    }
    $p = [System.IO.Path]::Combine($callerRoot, $p)
  }
  return [System.IO.Path]::GetFullPath($p)
}

function Get-Utf8NoBom { [System.Text.UTF8Encoding]::new($false) }

function Get-SHA256Hex {
  param([Parameter(Mandatory=$true)][byte[]]$Bytes)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
    return -join ($hash | ForEach-Object { $_.ToString("x2") })
  } finally { $sha.Dispose() }
}

function Write-AtomicUtf8 {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Text
  )

  $abs = Get-AbsPath -Path $Path
  $dir = [System.IO.Path]::GetDirectoryName($abs)
  if ([string]::IsNullOrWhiteSpace($dir)) { throw "Could not determine directory for '$abs'." }
  if (-not (Test-Path -LiteralPath $dir)) { throw "Target directory does not exist: $dir" }

  $enc = Get-Utf8NoBom
  $bytes = $enc.GetBytes($Text)
  $expectedHash = Get-SHA256Hex -Bytes $bytes
  $expectedLen = $bytes.Length

  $name = [System.IO.Path]::GetFileName($abs)
  $tmp = Join-Path $dir (".__tmp__{0}.{1}.tmp" -f $name, ([Guid]::NewGuid().ToString("N")))
  $bak = Join-Path $dir (".__bak__{0}.{1}.bak" -f $name, ([Guid]::NewGuid().ToString("N")))

  try {
    $fs = [System.IO.FileStream]::new(
      $tmp,
      [System.IO.FileMode]::CreateNew,
      [System.IO.FileAccess]::Write,
      [System.IO.FileShare]::None,
      65536,
      [System.IO.FileOptions]::WriteThrough
    )
    try {
      $fs.Write($bytes, 0, $bytes.Length)
      $fs.Flush($true)
    } finally { $fs.Dispose() }

    $tmpBytes = [System.IO.File]::ReadAllBytes($tmp)
    if ($tmpBytes.Length -ne $expectedLen) { throw "Temp length mismatch. expected=$expectedLen actual=$($tmpBytes.Length) tmp=$tmp" }
    $tmpHash = Get-SHA256Hex -Bytes $tmpBytes
    if ($tmpHash -ne $expectedHash) { throw "Temp hash mismatch. expected=$expectedHash actual=$tmpHash tmp=$tmp" }

    if (Test-Path -LiteralPath $abs) {
      [System.IO.File]::Replace($tmp, $abs, $bak, $true)
      if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue }
    } else {
      [System.IO.File]::Move($tmp, $abs)
    }

    $finalBytes = [System.IO.File]::ReadAllBytes($abs)
    if ($finalBytes.Length -ne $expectedLen) { throw "Final length mismatch. expected=$expectedLen actual=$($finalBytes.Length) path=$abs" }
    $finalHash = Get-SHA256Hex -Bytes $finalBytes
    if ($finalHash -ne $expectedHash) { throw "Final hash mismatch. expected=$expectedHash actual=$finalHash path=$abs" }

    return @{ ok=$true; path=$abs; bytes=$expectedLen; sha256=$expectedHash }
  }
  finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
  }
}