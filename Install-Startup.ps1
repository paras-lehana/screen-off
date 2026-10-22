# Adds (or with -Remove, deletes) a per-user Startup shortcut that starts Screen Off at sign-in.
# No admin rights, services or scheduled tasks; nothing runs before you sign in.
param([switch]$Remove)
$ErrorActionPreference = 'Stop'
$link = Join-Path ([Environment]::GetFolderPath('Startup')) 'Screen Off.lnk'
if ($Remove) {
    if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link; "Removed $link" } else { 'No Startup shortcut to remove.' }
    return
}
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($link)
$shortcut.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'Start-ScreenOff.ps1') + '"'
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.WindowStyle = 7
$shortcut.Description = 'Screen Off: turn screens and RGB off with a hotkey'
$shortcut.Save()
"Created $link"
