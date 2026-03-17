$ErrorActionPreference = "Stop"

function Write-AtomicUtf8 {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Content
  )
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $tmp = Join-Path $dir ("." + [IO.Path]::GetFileName($Path) + ".tmp." + [Guid]::NewGuid().ToString("n"))
  [IO.File]::WriteAllText($tmp, $Content, (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $tmp -Destination $Path -Force
}

$path = Join-Path (Get-Location).Path "src/routes/apiChat.ts"
if (-not (Test-Path -LiteralPath $path)) { throw "NOT FOUND: $path" }

$it = Get-Item -LiteralPath $path
Write-Host ("[CHECK] " + $it.FullName)
Write-Host ("        LastWriteTime: " + $it.LastWriteTime.ToString("s"))

$raw = Get-Content -LiteralPath $path -Raw

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bak = $path + ".bak." + $stamp
Copy-Item -LiteralPath $path -Destination $bak -Force
Write-Host ("[BACKUP] " + $bak)

# Find any 'try {' that is not followed by a catch/finally before the next top-level brace close.
# We will fix ONLY the first broken 'try' we can confidently detect.

$lines = $raw -split "`r?`n"

# print context around failing line 700 (helps confirm)
$from = [Math]::Max(1, 680)
$to = [Math]::Min($lines.Count, 720)
Write-Host "[SNIP 680-720]"
for ($i=$from; $i -le $to; $i++) { "{0,4}: {1}" -f $i, $lines[$i-1] | Write-Host }

# Strategy: insert 'catch (e:any) { throw e; }' RIGHT AFTER the specific 'try { ... }' that ends near line 700.
# We'll locate the 'try {' whose closing brace '}' is on/near the failing line number.

# 1) Convert line number -> approximate char index
$lineNo = 700
if ($lines.Count -lt $lineNo) { throw "File has only $($lines.Count) lines; cannot target line 700." }
$prefix = ($lines[0..($lineNo-1)] -join "`r`n")
$approxIdx = $prefix.Length

# 2) Search backwards from approxIdx for nearest 'try {'
$beforeText = $raw.Substring(0, $approxIdx)
$tryIdx = $beforeText.LastIndexOf("try")
if ($tryIdx -lt 0) { throw "Could not find 'try' before line 700." }

# Move to the 'try {' match using regex for reliability
$tryMatches = [Regex]::Matches($beforeText, "(?m)^\s*try\s*\{")
if ($tryMatches.Count -eq 0) { throw "Could not find a line-start 'try {' before line 700." }
$try = $tryMatches[$tryMatches.Count - 1]
$startIdx = $try.Index

$braceOpen = $raw.IndexOf("{", $startIdx)
if ($braceOpen -lt 0) { throw "Could not locate '{' for targeted try." }

# 3) Brace match from braceOpen
$depth = 0
$inStr = $false
$strCh = ""
$esc = $false
$closeIdx = -1

for ($i=$braceOpen; $i -lt $raw.Length; $i++) {
  $ch = $raw[$i]
  if ($inStr) {
    if ($esc) { $esc = $false; continue }
    if ($ch -eq "\") { $esc = $true; continue }
    if ($ch -eq $strCh) { $inStr = $false; $strCh = ""; continue }
    continue
  } else {
    if ($ch -eq "'" -or $ch -eq '"' -or $ch -eq "`") { $inStr = $true; $strCh = $ch; continue }
    if ($ch -eq "{") { $depth++; continue }
    if ($ch -eq "}") {
      $depth--
      if ($depth -eq 0) { $closeIdx = $i; break }
      continue
    }
  }
}

if ($closeIdx -lt 0) { throw "Could not find matching '}' for targeted try (brace match failed)." }

# 4) Check following tokens
$tail = $raw.Substring($closeIdx + 1)
$tailTrim = [Regex]::Replace($tail, "^\s*(//[^\r\n]*\r?\n\s*)*", "")
if ($tailTrim -match "^(catch\s*\(|finally\b)") {
  Write-Host "[INFO] Target try already has catch/finally. No insertion."
  exit 0
}

$insert = " catch (e: any) { throw e; }"
$fixed = $raw.Substring(0, $closeIdx + 1) + $insert + $raw.Substring($closeIdx + 1)

Write-AtomicUtf8 -Path $path -Content $fixed
Write-Host "[DONE] Inserted missing catch after try-block near line 700."
