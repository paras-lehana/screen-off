# Locates an AutoHotkey v2 runtime: $env:SCREENOFF_AHK, a sibling AutoHotkey* folder,
# the standard installer locations, then PATH. Dot-source and call Find-AutoHotkey.
function Find-AutoHotkey {
    $candidates = @()
    if ($env:SCREENOFF_AHK) { $candidates += $env:SCREENOFF_AHK }
    $parent = Split-Path $PSScriptRoot -Parent
    $candidates += Get-ChildItem -Path $parent -Directory -Filter 'AutoHotkey*' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'AutoHotkey64.exe' }
    foreach ($root in $env:ProgramFiles, $env:LOCALAPPDATA + '\Programs') {
        if ($root) { $candidates += Join-Path $root 'AutoHotkey\v2\AutoHotkey64.exe' }
    }
    $onPath = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue
    if ($onPath) { $candidates += $onPath.Source }
    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) { return $path }
    }
    throw 'AutoHotkey v2 not found. Install it from https://www.autohotkey.com/ or set SCREENOFF_AHK to AutoHotkey64.exe.'
}
