param(
  [Parameter(Mandatory=$true)][string]$Path,
  [Parameter(Mandatory=$true)][string]$Text
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 이 스크립트가 있는 폴더(= tools)
$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# atomic writer 로드 (절대경로)
. (Join-Path $toolsDir "Write-AtomicUtf8.ps1")

# 프로젝트 루트는 tools의 상위 폴더
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $toolsDir ".."))

function Resolve-ProjectPath {
  param([Parameter(Mandatory=$true)][string]$p)

  if ([System.IO.Path]::IsPathRooted($p)) {
    return [System.IO.Path]::GetFullPath($p)
  }

  # 상대경로는 무조건 프로젝트 루트 기준(= CWD 무관)
  return [System.IO.Path]::GetFullPath((Join-Path $projectRoot $p))
}

$abs = Resolve-ProjectPath -p $Path

# 프로젝트 밖 저장 차단(경로 튐 방지 핵심)
if ($abs -notlike ($projectRoot + "*")) {
  throw "Refusing to write outside project root. root=$projectRoot target=$abs"
}

$result = Write-AtomicUtf8 -Path $abs -Text $Text
$result | ConvertTo-Json -Depth 5