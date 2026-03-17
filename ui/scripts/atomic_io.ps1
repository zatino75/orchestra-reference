# atomic_io.ps1
# 정책:
# - Write-AtomicUtf8 / Write-AtomicUtf8-Auto 를 표준으로 사용
# - Auto는 (Get-Location) 기반 fullPath 계산 + -LiteralPath로 최종 write
# - repo root 바깥 쓰기 거부 (ui root 제한 폐기 → repo root 기준)
# - 호출 표준: -Content (필수)
# - 하위호환: -Text / -Value 별칭 지원
# 주의:
# - Export-ModuleMember는 "모듈(.psm1)로 로드된 경우"에만 실행 (dot-source에서는 실행 금지)

Set-StrictMode -Version Latest

function Get-RepoRoot {
    # atomic_io.ps1 위치: <repo>\ui\scripts\atomic_io.ps1
    # repo root = ui 폴더의 부모
    $here = $PSScriptRoot
    $uiRoot = Split-Path $here -Parent
    $repoRoot = Split-Path $uiRoot -Parent
    return [System.IO.Path]::GetFullPath($repoRoot)
}

function Test-IsUnderRoot {
    param(
        [Parameter(Mandatory=$true)][string]$FullPath,
        [Parameter(Mandatory=$true)][string]$RootPath
    )
    $p = [System.IO.Path]::GetFullPath($FullPath).TrimEnd('\')
    $r = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    if ($p.Length -lt $r.Length) { return $false }
    if ($p.Equals($r, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $p.StartsWith($r + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Write-AtomicUtf8 {
    [CmdletBinding(DefaultParameterSetName='ByContent')]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='ByContent')]
        [Parameter(Mandatory=$true, ParameterSetName='ByText')]
        [Parameter(Mandatory=$true, ParameterSetName='ByValue')]
        [Alias('Path')]
        [string]$LiteralPath,

        [Parameter(Mandatory=$true, ParameterSetName='ByContent')]
        [string]$Content,

        [Parameter(Mandatory=$true, ParameterSetName='ByText')]
        [Alias('Text')]
        [string]$Text_Compat,

        [Parameter(Mandatory=$true, ParameterSetName='ByValue')]
        [Alias('Value')]
        [string]$Value_Compat,

        [switch]$NoBom
    )

    $full = [System.IO.Path]::GetFullPath($LiteralPath)

    $payload =
        if ($PSCmdlet.ParameterSetName -eq 'ByContent') { $Content }
        elseif ($PSCmdlet.ParameterSetName -eq 'ByText') { $Text_Compat }
        else { $Value_Compat }

    $dir  = [System.IO.Path]::GetDirectoryName($full)
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $fileName = [System.IO.Path]::GetFileName($full)
    $tmpName  = ".$fileName.tmp.$([Guid]::NewGuid().ToString('N'))"
    $tmpPath  = Join-Path $dir $tmpName

    try {
        $enc = if ($NoBom) { New-Object System.Text.UTF8Encoding($false) } else { New-Object System.Text.UTF8Encoding($true) }
        [System.IO.File]::WriteAllText($tmpPath, $payload, $enc)
        Move-Item -LiteralPath $tmpPath -Destination $full -Force
    } finally {
        if (Test-Path -LiteralPath $tmpPath) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-AtomicUtf8-Auto {
    [CmdletBinding(DefaultParameterSetName='ByContent')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true, ParameterSetName='ByContent')]
        [string]$Content,

        [Parameter(Mandatory=$true, ParameterSetName='ByText')]
        [Alias('Text')]
        [string]$Text_Compat,

        [Parameter(Mandatory=$true, ParameterSetName='ByValue')]
        [Alias('Value')]
        [string]$Value_Compat,

        [switch]$NoBom
    )

    $base = (Get-Location).Path
    $full =
        if ([System.IO.Path]::IsPathRooted($Path)) { [System.IO.Path]::GetFullPath($Path) }
        else { [System.IO.Path]::GetFullPath((Join-Path $base $Path)) }

    $repoRoot = Get-RepoRoot

    if (-not (Test-IsUnderRoot -FullPath $full -RootPath $repoRoot)) {
        throw "Write-AtomicUtf8-Auto refused path outside repo root. path=$full root=$repoRoot"
    }

    if ($PSCmdlet.ParameterSetName -eq 'ByContent') {
        Write-AtomicUtf8 -LiteralPath $full -Content $Content -NoBom:$NoBom
    } elseif ($PSCmdlet.ParameterSetName -eq 'ByText') {
        Write-AtomicUtf8 -LiteralPath $full -Text $Text_Compat -NoBom:$NoBom
    } else {
        Write-AtomicUtf8 -LiteralPath $full -Value $Value_Compat -NoBom:$NoBom
    }
}

# 모듈로 로드된 경우에만 Export-ModuleMember 실행
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function Write-AtomicUtf8, Write-AtomicUtf8-Auto
}