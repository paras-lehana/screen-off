<#
.SYNOPSIS
Start Screen Off or change its saved settings without turning the screen off.
.EXAMPLE
.\Start-ScreenOff.ps1 -Aura 1 -Corsair 1 -CorsairDevices keyboard,mouse
.EXAMPLE
.\Start-ScreenOff.ps1 -Backend openrgb -OpenRgbPort 6742
.EXAMPLE
.\Start-ScreenOff.ps1 -Backend dynamic -CheckBackend
#>
param(
    [ValidateSet('aura','openrgb','dynamic','none')][string]$Backend,
    [ValidateRange(1,65535)][int]$OpenRgbPort,
    [ValidateSet(0,1)][int]$LockOnWake,
    [ValidateSet(0,1)][int]$Aura,
    [ValidateSet(0,1)][int]$Corsair,
    [string[]]$CorsairDevices,
    [ValidateSet(0,1)][int]$OpenRgb,
    [ValidateSet(0,1)][int]$DynamicLighting,
    [ValidateSet('profile','sdk')][string]$AuraMethod,
    [ValidateSet('breathing','rainbow','colorcycle','static','dark')][string]$AuraWakeEffect,
    [ValidateSet(0,1)][int]$AuraRestorePrevious,
    [ValidateRange(1,120)][int]$NoticeSeconds,
    [switch]$Settings,
    [switch]$Status,
    [switch]$CheckBackend
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Find-AutoHotkey.ps1')
$runtime = Find-AutoHotkey
$script = Join-Path $PSScriptRoot 'ScreenOffWindows.ahk'
if (-not (Test-Path -LiteralPath $runtime)) { throw "AutoHotkey runtime missing: $runtime" }
$logs = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
if ($CheckBackend) {
    # Explicit diagnostic mode: do not persist overrides, start the tray, or write LEDs.
    $ini = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'settings.ini') -Raw
    if (-not $Backend) {
        $match = [regex]::Match($ini,'(?m)^Backend=(\w+)\s*$')
        $Backend = if ($match.Success) { $match.Groups[1].Value } else { 'aura' }
    }
    if (-not $OpenRgbPort) {
        $match = [regex]::Match($ini,'(?m)^Port=(\d+)\s*$')
        $OpenRgbPort = if ($match.Success) { [int]$match.Groups[1].Value } else { 6742 }
    }
    if ($Backend -eq 'none') { Write-Output 'Display-only mode; no lighting dependency.'; return }
    if ($Backend -eq 'aura') {
        if (-not $AuraMethod) {
            $methodMatch = [regex]::Match($ini,'(?m)^Method=(profile|sdk)\s*$')
            $AuraMethod = if ($methodMatch.Success) { $methodMatch.Groups[1].Value } else { 'sdk' }
        }
        if ($AuraMethod -eq 'profile') {
            if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'AuraProfileWorker.ps1'))) { throw 'Aura profile helper missing.' }
            Write-Output 'Aura profile helper installed; Armoury Crate UI is checked on activation. No lighting writes.'
            return
        }
        $null = Get-Item 'Registry::HKEY_CLASSES_ROOT\aura.sdk.1\CLSID'
        Write-Output 'Aura COM registered; no lighting writes. Physical behavior unverified.'
        return
    }
    $helper = Join-Path $PSScriptRoot 'LightingHost\publish\ScreenOff.LightingHost.exe'
    if (-not (Test-Path -LiteralPath $helper)) { throw 'Run Build-LightingHost.ps1 first.' }
    & $helper --backend $Backend --probe 1 --port $OpenRgbPort
    if ($LASTEXITCODE -ne 0) { throw 'Backend unavailable; see diagnostic above. Saved settings unchanged.' }
    return
}
$options = @()
if ($Status) {
    $options = @('--status')
} else {
    if ($PSBoundParameters.ContainsKey('Backend')) { $options += '--backend=' + $Backend }
    if ($PSBoundParameters.ContainsKey('OpenRgbPort')) { $options += '--openrgb-port=' + $OpenRgbPort }
    if ($PSBoundParameters.ContainsKey('LockOnWake')) { $options += '--lock-on-wake=' + $LockOnWake }
    if ($PSBoundParameters.ContainsKey('Aura')) { $options += '--aura=' + $Aura }
    if ($PSBoundParameters.ContainsKey('Corsair')) { $options += '--corsair=' + $Corsair }
    if ($PSBoundParameters.ContainsKey('CorsairDevices')) { $options += '--corsair-devices=' + (($CorsairDevices | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ',') }
    if ($PSBoundParameters.ContainsKey('OpenRgb')) { $options += '--openrgb=' + $OpenRgb }
    if ($PSBoundParameters.ContainsKey('DynamicLighting')) { $options += '--dynamic=' + $DynamicLighting }
    if ($PSBoundParameters.ContainsKey('AuraMethod')) { $options += '--aura-method=' + $AuraMethod }
    if ($PSBoundParameters.ContainsKey('AuraWakeEffect')) { $options += '--aura-wake-effect=' + $AuraWakeEffect }
    if ($PSBoundParameters.ContainsKey('AuraRestorePrevious')) { $options += '--aura-restore-previous=' + $AuraRestorePrevious }
    if ($PSBoundParameters.ContainsKey('NoticeSeconds')) { $options += '--notice-seconds=' + $NoticeSeconds }
}
if ($options.Count -gt 0) {
    $prefix = Join-Path $logs ('configure-' + [Guid]::NewGuid().ToString('N'))
    $configScript = Join-Path $PSScriptRoot 'configure-utility.ahk'
    $process = Start-Process -FilePath $runtime -ArgumentList (@('/ErrorStdOut',('"' + $configScript + '"')) + $options) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput ($prefix + '.out') -RedirectStandardError ($prefix + '.err')
    Get-Content -LiteralPath ($prefix + '.out')
    $problem = Get-Content -LiteralPath ($prefix + '.err') -Raw
    if ($process.ExitCode -ne 0) { throw ("Configuration failed: " + $problem) }
}
if ($Status) { return }
# SingleInstance Ignore preserves an existing resident. Configuration above tells
# that resident to reload only when it is idle; it refuses changes during off mode.
Start-Process -FilePath $runtime -ArgumentList ('"' + $script + '"') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
if ($Settings) {
    # A separate controller sends the Settings menu action to an existing resident.
    Start-Sleep -Milliseconds 300
    Start-Process -FilePath $runtime -ArgumentList ('"' + (Join-Path $PSScriptRoot 'control-utility.ahk') + '" --settings') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden
}
