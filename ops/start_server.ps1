param(
  [string]$Host = "127.0.0.1",
  [int]$Port = 8000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  $here = Split-Path -Parent $MyInvocation.MyCommand.Path
  if (-not $here) { return (Get-Location).Path }
  return (Resolve-Path -LiteralPath (Join-Path $here "..")).Path
}

$repoRoot = Get-RepoRoot
Set-Location -LiteralPath $repoRoot

$cmd = @(
  "python","-m","uvicorn",
  "core.app:app",
  "--host",$Host,
  "--port",$Port,
  "--reload"
)

"START_SERVER: $($cmd -join ' ')"
& $cmd[0] $cmd[1..($cmd.Count-1)]