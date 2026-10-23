# Corsair lighting worker for Screen Off. Uses the official iCUE SDK (pinned 4.0.84):
# exclusive lighting control, a black frame every 2 s, then release so iCUE restores
# the user's own profile. Lighting only: no key interception or device configuration.
param(
    [Parameter(Mandatory=$true)][int]$ParentId,
    [Parameter(Mandatory=$true)][string]$StatePrefix,
    [string]$Devices = 'keyboard,mouse,mousemat,headset,headsetstand',
    [switch]$Probe
)
$ErrorActionPreference = 'Stop'
# CorsairDeviceType bits from iCUESDK.h. Motherboard/GPU/touchbar are never requested:
# iCUE can mirror other vendors' boards, and those belong to their own controller.
$TYPE_BITS = @{ keyboard=0x1; mouse=0x2; mousemat=0x4; headset=0x8; headsetstand=0x10
    fancontroller=0x20; ledcontroller=0x40; memory=0x80; cooler=0x100; gamecontroller=0x1000 }
# iCUE 4.x speaks SDK protocol 4.0.12 and rejects the 4.0.84 client ("handshake failed");
# iCUE 5.x needs the newer one. Pick the SDK by the installed iCUE's major version.
function Get-SdkDll {
    $icue = Get-Process -Name iCUE -ErrorAction SilentlyContinue | Select-Object -First 1
    $major = 5
    if ($icue -and $icue.Path) { $major = (Get-Item -LiteralPath $icue.Path).VersionInfo.FileMajorPart }
    $version = if ($major -le 4) { '4.0.48' } else { '4.0.84' }
    Join-Path $PSScriptRoot "vendor\iCUESDK_$version\iCUESDK\redist\x64\iCUESDK.x64_2019.dll"
}
$SDK_DLL = $null
# Exclusive control keeps iCUE from overwriting black, so refresh rarely: Corsair reports
# CorsairSetLedColors can stop returning after hours of rapid calls (cue-sdk issue 32).
$FRAME_MS = 2000
$encoding = New-Object System.Text.UTF8Encoding($false)
function Set-Status([string]$Value) { [IO.File]::WriteAllText($StatePrefix + '.status', $Value, $encoding) }
function Write-Log([string]$Value) {
    try { [IO.File]::AppendAllText($StatePrefix + '.log', (Get-Date -Format o) + ' ' + $Value + [Environment]::NewLine, $encoding) } catch { }
}

$cue = $null; $failure = $null; $acquired = $false; $frames = 0
try {
    $mask = 0
    foreach ($name in ($Devices -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })) {
        if (-not $TYPE_BITS.ContainsKey($name)) { throw "Unknown Corsair device type '$name'." }
        $mask = $mask -bor $TYPE_BITS[$name]
    }
    if ($mask -eq 0) { throw 'No Corsair device types selected.' }
    if (-not (Get-Process -Name iCUE -ErrorAction SilentlyContinue)) { throw 'iCUE is not running. Start iCUE (the SDK talks to it).' }
    $SDK_DLL = Get-SdkDll
    if (-not (Test-Path -LiteralPath $SDK_DLL)) { throw "iCUE SDK DLL missing: $SDK_DLL. Run Get-CorsairSdk.ps1." }
    # iCUE stops its SDK server while the session is locked or remote (its log: "Session active changed: false").
    Add-Type -AssemblyName System.Windows.Forms
    if ([System.Windows.Forms.SystemInformation]::TerminalServerSession) { throw 'This is a Remote Desktop session; iCUE pauses its SDK until you sign in at the PC itself.' }
    $parent = [Diagnostics.Process]::GetProcessById($ParentId)
    $null = $parent.Handle
    Add-Type -Path (Join-Path $PSScriptRoot 'CorsairLighting.cs')
    $cue = New-Object CorsairLighting
    $found = $cue.Discover($SDK_DLL, $mask)
    $names = ($found | ForEach-Object { '{0} ({1} LEDs)' -f $_.Model, $_.LedCount }) -join '; '
    if ($Probe) { Set-Status ('AVAILABLE|' + $names + '. No colours changed.'); return }
    Write-Log ('Devices: ' + $names)
    $cue.Acquire($found)
    $acquired = $true
    Write-Log ($cue.Verify())
    Set-Status ('APPLIED|' + $names)
    # Effects and iCUE's own refresh can overwrite one frame; keep resubmitting black.
    while (-not (Test-Path -LiteralPath ($StatePrefix + '.stop'))) {
        $cue.Darken()
        $frames++
        if ($frames % 30 -eq 1) { Write-Log ('frames=' + $frames + '; ' + $cue.Verify()) }
        if ($parent.WaitForExit($FRAME_MS)) { break }
    }
} catch {
    $failure = $_.Exception.Message
    Write-Log ('ERROR ' + $failure)
} finally {
    if ($null -ne $cue) {
        try { $cue.Dispose() } catch { $failure = 'Corsair release failed: ' + $_.Exception.Message }
    }
    if ($Probe) {
        if ($null -ne $failure) { Set-Status ('ERROR|' + $failure) }
    } elseif ($null -ne $failure) { Set-Status ('ERROR|' + $failure) }
    else { Set-Status ('RESTORED|Corsair control released after ' + $frames + ' frames') }
    Write-Log ('Worker finished; acquired=' + $acquired + '; frames=' + $frames + '; failure=' + $failure)
}
if ($null -ne $failure) { exit 1 }
