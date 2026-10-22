param(
    [Parameter(Mandatory=$true)][int]$ParentId,
    [Parameter(Mandatory=$true)][string]$StatePrefix,
    [int]$AuraEnabled = 1,
    [int]$CorsairEnabled = 1
)
$ErrorActionPreference = 'Stop'
$sdk = $null
$owned = $false
$failure = $null
$cue = $null
$deviceCollection = $null
$frames = 0
$elapsed = [Diagnostics.Stopwatch]::StartNew()
$lastProgressMs = 0L
$encoding = New-Object System.Text.UTF8Encoding($false)
function Set-WorkerStatus([string]$Value) {
    [IO.File]::WriteAllText($StatePrefix + '.status', $Value, $encoding)
}
function Write-WorkerLog([string]$Value) {
    # Diagnostics must never prevent releasing lighting ownership in finally.
    try { [IO.File]::AppendAllText($StatePrefix + '.log', (Get-Date -Format o) + ' ' + $Value + [Environment]::NewLine, $encoding) } catch { }
}
try {
    # ASUS' C++ SDK tutorial requires COINIT_MULTITHREADED. STA could freeze
    # non-GPU effects until release in the observed19October tests.
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'MTA') { throw 'Aura SDK worker must be launched with powershell.exe -Mta.' }
    Write-WorkerLog 'Worker starting; lighting commands are software submissions, not physical confirmation.'
    # Holding the process handle prevents PID reuse from extending the blackout.
    $parentProcess = [Diagnostics.Process]::GetProcessById($ParentId)
    $null = $parentProcess.Handle
    if ($AuraEnabled) { $sdk = New-Object -ComObject 'aura.sdk.1' }
    if ((Test-Path -LiteralPath ($StatePrefix + '.stop')) -or $parentProcess.HasExited) { return }
    $names = @()
    if ($AuraEnabled) {
        $owned = $true
        $sdk.SwitchMode()
        Write-WorkerLog ('Aura control acquired at elapsedMs=' + $elapsed.ElapsedMilliseconds)
        # Retain the SDK collection for the whole session. Do not detach device
        # references from a temporary Enumerate result as the earlier worker did.
        $deviceCollection = $sdk.Enumerate(0)
        $supported = 0
        for ($d = 0; $d -lt $deviceCollection.Count; $d++) {
            $device = $deviceCollection.Item($d)
            if ($device.Type -eq 0x30000 -or $device.Lights.Count -eq 0) { continue }
            $supported++
            $names += $device.Name
        }
        if ($supported -eq 0) { throw 'Aura did not find any PC lighting devices.' }
        Write-WorkerLog ('Aura enumeration complete at elapsedMs=' + $elapsed.ElapsedMilliseconds + '; devices=' + $supported)
    }
    if ($CorsairEnabled) {
        try {
            Add-Type -Path (Join-Path $PSScriptRoot 'CorsairLighting.cs')
            $cue = New-Object CorsairLighting
            $keyboards = $cue.Discover((Join-Path $PSScriptRoot 'vendor\iCUESDK_4.0.84\iCUESDK\redist\x64\iCUESDK.x64_2019.dll'))
            $cue.Acquire($keyboards)
            Write-WorkerLog ($cue.Verify())
            $names += 'Corsair K100'
        } catch {
            Write-WorkerLog ('WARN Corsair: ' + $_.Exception.Message)
            if ($null -ne $cue) { $cue.Dispose(); $cue = $null }
            $names += 'K100 unavailable (see RGB log)'
        }
    }
    # Display transitions and competing effects can overwrite a single frame.
    # Refresh at 2 Hz on the worker, never on the input-hook thread.
    while (-not (Test-Path -LiteralPath ($StatePrefix + '.stop'))) {
        $frameStartMs = $elapsed.ElapsedMilliseconds
        $ledWrites = 0
        if ($AuraEnabled) {
            for ($d = 0; $d -lt $deviceCollection.Count; $d++) {
                $device = $deviceCollection.Item($d)
                if ($device.Type -eq 0x30000) { continue }
                $lights = $device.Lights
                for ($i = 0; $i -lt $lights.Count; $i++) {
                    $light = $lights.Item($i)
                    $light.Color = 0
                    # This checks the SDK buffer only; it cannot verify emitted light.
                    if ($light.Color -ne 0) { throw ('Aura did not retain black in its buffer: ' + $device.Name) }
                    $ledWrites++
                }
                $device.Apply()
            }
            if ($ledWrites -eq 0) { throw 'No Aura LED buffers were written; cancelling the RGB attempt.' }
        }
        if ($null -ne $cue) { $cue.Darken() }
        $frames++
        $frameMs = $elapsed.ElapsedMilliseconds - $frameStartMs
        if ($frames -eq 1) { Set-WorkerStatus ('APPLIED|' + ($names -join '; ')); Write-WorkerLog ('Black submitted, physical result unverified; LED buffers=' + $ledWrites + '; ' + ($names -join '; ')) }
        if ($frames -eq 1 -or $elapsed.ElapsedMilliseconds - $lastProgressMs -ge 10000 -or $frameMs -ge 1000) {
            Write-WorkerLog ('Black frame submissions: ' + $frames + '; LED buffers=' + $ledWrites + '; frameMs=' + $frameMs + '; elapsedMs=' + $elapsed.ElapsedMilliseconds + '; physical result unverified')
            $lastProgressMs = $elapsed.ElapsedMilliseconds
            if ($null -ne $cue) { Write-WorkerLog ($cue.Verify()) }
        }
        if ($parentProcess.WaitForExit(500)) { break }
    }
} catch {
    $failure = $_.Exception.Message
    Write-WorkerLog ('ERROR ' + $failure)
} finally {
    Write-WorkerLog ('Restoration starting; frames=' + $frames + '; elapsedMs=' + $elapsed.ElapsedMilliseconds)
    if ($null -ne $cue) {
        try { $cue.Dispose() } catch { Write-WorkerLog ('Corsair release error: ' + $_.Exception.Message) }
    }
    try {
        if ($owned) { $sdk.ReleaseControl(0) }
    } catch {
        $failure = 'Aura control release failed: ' + $_.Exception.Message
    }
    if ($null -ne $sdk) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($sdk) }
    if ($null -ne $failure) { Set-WorkerStatus ('ERROR|' + $failure) }
    else { Set-WorkerStatus 'RESTORED|Aura control released' }
    Write-WorkerLog ('Worker finished; frames=' + $frames + '; elapsedMs=' + $elapsed.ElapsedMilliseconds + '; failure=' + $failure)
}
if ($null -ne $failure) { exit 1 }
