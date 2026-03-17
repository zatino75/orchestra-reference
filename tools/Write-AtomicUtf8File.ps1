# 파워셀덮어쓰기
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-AtomicUtf8File {
  param(
    [Parameter(Mandatory=$true)][string]$LiteralPath,
    [Parameter(Mandatory=$true)][string]$Content
  )

  $fullPath = [System.IO.Path]::GetFullPath($LiteralPath)

  $dir = [System.IO.Path]::GetDirectoryName($fullPath)
  if ([string]::IsNullOrWhiteSpace($dir)) {
    throw "Cannot determine directory name for path: $fullPath"
  }
  [System.IO.Directory]::CreateDirectory($dir) | Out-Null

  $tmpName = [System.IO.Path]::GetFileName($fullPath) + ".tmp." + [System.Guid]::NewGuid().ToString("N")
  $tmpPath = [System.IO.Path]::Combine($dir, $tmpName)

  $bakName = [System.IO.Path]::GetFileName($fullPath) + ".bak." + [System.Guid]::NewGuid().ToString("N")
  $bakPath = [System.IO.Path]::Combine($dir, $bakName)

  try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmpPath, $Content, $utf8NoBom)

    if ([System.IO.File]::Exists($fullPath)) {
      # .NET File.Replace는 backup 경로가 null/empty면 예외가 날 수 있음
      [System.IO.File]::Replace($tmpPath, $fullPath, $bakPath, $true)

      # Replace가 성공하면 backup은 바로 삭제(원칙상 백업 파일 방치 금지)
      if ([System.IO.File]::Exists($bakPath)) {
        Remove-Item -LiteralPath $bakPath -Force -ErrorAction SilentlyContinue
      }
    } else {
      [System.IO.File]::Move($tmpPath, $fullPath)
    }
  } finally {
    if ([System.IO.File]::Exists($tmpPath)) {
      Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
    }
    if ([System.IO.File]::Exists($bakPath)) {
      Remove-Item -LiteralPath $bakPath -Force -ErrorAction SilentlyContinue
    }
  }
}
