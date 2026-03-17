Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = "C:\Users\User\Desktop\orchestra"
$desktop = [Environment]::GetFolderPath("Desktop")
$pwsh = (Get-Command pwsh).Source

function New-Shortcut([string]$Name, [string]$Args, [string]$WorkDir) {
  $wsh = New-Object -ComObject WScript.Shell
  $lnkPath = Join-Path $desktop ($Name + ".lnk")
  $s = $wsh.CreateShortcut($lnkPath)
  $s.TargetPath = $pwsh
  $s.Arguments  = "-NoProfile -ExecutionPolicy Bypass -File `"$Args`""
  $s.WorkingDirectory = $WorkDir
  $s.IconLocation = "$env:SystemRoot\System32\shell32.dll, 167"
  $s.Save()
  "OK: created $lnkPath"
}

New-Shortcut "AI Orchestra - Start API (8000)" "$root\ops\start_api.ps1" "$root"
New-Shortcut "AI Orchestra - Restart API (8000)" "$root\ops\restart_api.ps1" "$root"
New-Shortcut "AI Orchestra - Start UI (5173)" "$root\ops\start_ui.ps1" "$root\ui"
New-Shortcut "AI Orchestra - Restart UI (5173)" "$root\ops\restart_ui.ps1" "$root"
New-Shortcut "AI Orchestra - Check Status" "$root\ops\check_status.ps1" "$root"
New-Shortcut "AI Orchestra - Stop All (ports)" "$root\ops\stop_all.ps1" "$root"

"Done."