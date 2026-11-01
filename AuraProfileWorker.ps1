param(
    [Parameter(Mandatory=$true)][int]$ParentId,
    [Parameter(Mandatory=$true)][string]$StatePrefix,
    [ValidateSet('breathing','rainbow','colorcycle','static','dark')][string]$WakeEffect = 'breathing',
    [ValidateSet(0,1)][int]$RestorePrevious = 0,
    [switch]$RestoreOnly
)
# Native Windows UI Automation, not private ASUS interfaces or screen coordinates.
# These names/IDs belong to the installed Armoury Crate UI. Change here if ASUS
# renames them. Only Aura Effects are selected; Scenario Profiles are never applied.
$AURA_APP_ID = 'B9ECED6F.ArmouryCrate_qmba6cd70vzyy!App'
$AURA_WINDOW_NAME = 'Armoury Crate'
$AURA_NAV_NAME = 'Lighting & Aura Sync'
$AURA_TAB_NAME = 'Aura Effects'
$AURA_DARK_ID = 'DarkBtn'
$AURA_EFFECT_IDS = @{ breathing='BreathBtn'; rainbow='RainbowBtn'; colorcycle='ColorCycleBtn'; static='StaticBtn'; dark='DarkBtn' }
$AURA_KNOWN_EFFECT_IDS = @('StaticBtn','BreathBtn','StrobingBtn','ColorCycleBtn','RainbowBtn','StarryNightBtn','NewMusicBtn','SmartBtn','ScreenExtensionBtn','ImmersionBtn','AILightingBtn','DarkBtn')
# A cold start after hours closed can take 20+ s (23 Oct: a 12 s limit left the lights dark).
$AURA_UI_TIMEOUT_MS = 40000
$AURA_UI_POLL_MS = 150
# Owner 21 Oct: close Armoury Crate after every off/on change, so it is never left on
# screen. $false restores the earlier behavior (re-minimize only if it was minimized).
$AURA_CLOSE_AFTER_ACTION = $true
# Pause between selecting an effect and closing the window, so the app hands it to the service.
$AURA_SETTLE_MS = 1500
# Keep the Armoury Crate window open after selecting Dark (hidden behind the screen covers) and
# close it as the last step of the restore. Closing it first made the wake-time relaunch slow.
$AURA_CLOSE_AFTER_DARK = $false
$AURA_CLOSE_TIMEOUT_MS = 5000
$OWNER_POLL_MS = 250
$ErrorActionPreference = 'Stop'
$encoding = New-Object System.Text.UTF8Encoding($false)
$changed = $false
$restoring = $false
$window = $null
$failure = $null
$restoreId = $AURA_EFFECT_IDS[$WakeEffect]
Add-Type -Namespace ScreenOff -Name Win32 -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);'
# The lighting step runs in the background while the screens come back, so the Armoury Crate
# window is parked far off-screen as soon as it exists and signalled with <prefix>.hidden.
function Write-Hidden { try { [IO.File]::WriteAllText($StatePrefix+'.hidden','1',$encoding) } catch { } }
function Hide-Window {
    try {
        $h=[IntPtr]$script:window.Current.NativeWindowHandle
        if($h -ne [IntPtr]::Zero) {
            # SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
            [void][ScreenOff.Win32]::SetWindowPos($h,[IntPtr]::Zero,-32000,-32000,0,0,0x15)
            Write-Log 'Armoury Crate window moved off-screen'
        }
    } catch { Write-Log ('Hide-window warning: '+$_.Exception.Message) }
    Write-Hidden
}
$parentProcess = $null
$minimizeAfterAction = $false
# Written when Dark is selected, removed when the effect is restored. If a restore fails (locked desktop,
# empty window...) the marker survives, and Screen Off puts the lights back the next time it can.
$PENDING_FILE = Join-Path (Split-Path $StatePrefix -Parent) 'aura-restore-pending.txt'
function Set-Pending { try { [IO.File]::WriteAllText($PENDING_FILE, ('restore=' + $restoreId + ' since=' + (Get-Date -Format o)), $encoding) } catch { } }
function Clear-Pending { try { Remove-Item -LiteralPath $PENDING_FILE -Force -ErrorAction SilentlyContinue } catch { } }
function Set-Status([string]$Value) { [IO.File]::WriteAllText($StatePrefix+'.status',$Value,$encoding) }
function Write-Log([string]$Value) {
    try { [IO.File]::AppendAllText($StatePrefix+'.log',(Get-Date -Format o)+' '+$Value+[Environment]::NewLine,$encoding) } catch { }
}
function Check-Cancelled {
    if (-not $script:restoring -and ((Test-Path -LiteralPath ($StatePrefix+'.stop')) -or $script:parentProcess.HasExited)) { throw 'Preparation cancelled before profile selection.' }
}
function Find-Element($Root,[string]$Value,[switch]$Id) {
    $property = if($Id) { [System.Windows.Automation.AutomationElement]::AutomationIdProperty } else { [System.Windows.Automation.AutomationElement]::NameProperty }
    $condition = New-Object System.Windows.Automation.PropertyCondition($property,$Value)
    return $Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$condition)
}
function Wait-Element($Root,[string]$Value,[switch]$Id) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do {
        Check-Cancelled
        $element=Find-Element $Root $Value -Id:$Id
        if($null -ne $element -and $element.Current.IsEnabled) { return $element }
        Start-Sleep -Milliseconds $AURA_UI_POLL_MS
    } while($watch.ElapsedMilliseconds -lt $AURA_UI_TIMEOUT_MS)
    throw ('Armoury Crate control unavailable: '+$Value)
}
function Select-Element($Element) {
    $selection=$Element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    $selection.Select()
    if(-not $selection.Current.IsSelected) { throw ('Armoury Crate did not select '+$Element.Current.Name) }
}
# After a lock or a long park the UWP window can stay open with its content dropped (1 Nov: only the title
# bar was exposed, so "Lighting & Aura Sync" never appeared). Detect that quickly and relaunch.
function Test-Content([int]$TimeoutMs) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    do {
        if($null -ne (Find-Element $script:window $AURA_NAV_NAME)) { return $true }
        Start-Sleep -Milliseconds $AURA_UI_POLL_MS
    } while($watch.ElapsedMilliseconds -lt $TimeoutMs)
    return $false
}
function Close-Window {
    try { $script:window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() } catch { Write-Log ('Close warning: '+$_.Exception.Message) }
    $condition=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$AURA_WINDOW_NAME)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($null -ne [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,$condition) -and $watch.ElapsedMilliseconds -lt 8000) { Start-Sleep -Milliseconds $AURA_UI_POLL_MS }
    # 1 Nov: the closed window's UI process stayed alive and the "relaunch" reused it, still empty (the
    # restore failed twice). End only that UI process (never the Armoury services) so a fresh one starts.
    if($null -ne [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,$condition)) {
        Get-Process -Name 'ArmouryCrate' -ErrorAction SilentlyContinue | ForEach-Object { Write-Log ('Ending stuck Armoury Crate UI process ' + $_.Id); try { $_.Kill() } catch { } }
        Start-Sleep -Milliseconds 1500
    }
    $script:window=$null
}
function Open-Effects {
    Write-Log ('Open-Effects start (restoring=' + $script:restoring + ')')
    $condition=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$AURA_WINDOW_NAME)
    $script:window=[System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,$condition)
    if($null -ne $script:window -and -not (Test-Content 4000)) {
        Write-Log 'Armoury Crate window is open but empty (UWP content dropped); closing it to relaunch'
        Close-Window
    }
    if($null -eq $script:window) {
        $script:minimizeAfterAction=$true
        # Starts the installed app if closed. It can appear briefly; no coordinate input.
        Start-Process -FilePath explorer.exe -ArgumentList ('shell:AppsFolder\'+$AURA_APP_ID) -WindowStyle Hidden
        $watch=[Diagnostics.Stopwatch]::StartNew()
        do {
            Check-Cancelled
            Start-Sleep -Milliseconds $AURA_UI_POLL_MS
            $script:window=[System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,$condition)
        } while($null -eq $script:window -and $watch.ElapsedMilliseconds -lt $AURA_UI_TIMEOUT_MS)
        if($null -eq $script:window) { throw 'Armoury Crate did not open.' }
        Write-Log ('Armoury Crate window appeared after ' + $watch.ElapsedMilliseconds + ' ms')
    } else { Write-Log 'Armoury Crate window already open' }
    # A minimized UWP window exposes zero descendants. Restore it for UIA; afterwards
    # Finish-UiAction closes it (or re-minimizes it when closing is turned off).
    $windowPattern=$script:window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
    if($windowPattern.Current.WindowVisualState -eq [System.Windows.Automation.WindowVisualState]::Minimized) {
        $script:minimizeAfterAction=$true
        $windowPattern.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Normal)
    }
    Hide-Window
    Select-Element (Wait-Element $script:window $AURA_NAV_NAME)
    Write-Log 'Lighting & Aura Sync selected'
    Select-Element (Wait-Element $script:window $AURA_TAB_NAME)
    Write-Log 'Aura Effects selected'
    $null=Wait-Element $script:window $AURA_DARK_ID -Id
}
function Finish-UiAction([switch]$KeepOpen) {
    try {
        if($KeepOpen) { Write-Log 'Armoury Crate window left open (hidden behind the covers) until restore'; return }
        if($null -eq $script:window) { return }
        $windowPattern=$script:window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
        if($AURA_CLOSE_AFTER_ACTION) {
            Start-Sleep -Milliseconds $AURA_SETTLE_MS
            $windowPattern.Close()
            $condition=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$AURA_WINDOW_NAME)
            $watch=[Diagnostics.Stopwatch]::StartNew()
            while($null -ne [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,$condition)) {
                if($watch.ElapsedMilliseconds -ge $AURA_CLOSE_TIMEOUT_MS) { Write-Log 'Window-close warning: Armoury Crate window still present'; break }
                Start-Sleep -Milliseconds $AURA_UI_POLL_MS
            }
            Write-Log ('Closed Armoury Crate window after '+$watch.ElapsedMilliseconds+' ms')
        } elseif($script:minimizeAfterAction) {
            $windowPattern.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Minimized)
        }
    } catch { Write-Log ('Window-state restore warning: '+$_.Exception.Message) }
    finally {
        $script:minimizeAfterAction=$false
        $script:window=$null
    }
}
try {
    $parentProcess=[Diagnostics.Process]::GetProcessById($ParentId)
    $null=$parentProcess.Handle
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    if($RestoreOnly) {
        $restoring=$true
        Open-Effects
        Select-Element (Wait-Element $window $restoreId -Id)
        Write-Log ('Restored lighting effect ' + $restoreId + ' (restore-only run)')
        Clear-Pending
        return
    }
    Open-Effects
    if($RestorePrevious) {
        foreach($candidate in $AURA_KNOWN_EFFECT_IDS) {
            $element=Find-Element $window $candidate -Id
            if($null -ne $element -and $element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected) {
                $restoreId=$candidate
                break
            }
        }
    }
    # Save the restoration plan before selecting Dark, even if selection throws.
    [IO.File]::WriteAllText($StatePrefix+'.restore-effect',$restoreId,$encoding)
    Check-Cancelled
    $changed=$true
    Select-Element (Wait-Element $window $AURA_DARK_ID -Id)
    Set-Pending
    Finish-UiAction -KeepOpen:(-not $AURA_CLOSE_AFTER_DARK)
    Write-Log ('Selected Dark (Off); restore target='+$restoreId+'; UI selection is not physical LED confirmation.')
    Set-Status 'APPLIED|Aura Sync Dark (Off) selected through Windows UI Automation'
    while(-not (Test-Path -LiteralPath ($StatePrefix+'.stop'))) {
        if($parentProcess.WaitForExit($OWNER_POLL_MS)) { break }
    }
} catch {
    $failure=$_.Exception.Message
    Write-Log ('ERROR '+$failure)
} finally {
    if($changed) {
        try {
            $restoring=$true
            Write-Log 'Restore requested'
            Open-Effects
            Select-Element (Wait-Element $window $restoreId -Id)
            Write-Log ('Restored lighting effect '+$restoreId)
            Clear-Pending
            $script:window = $script:window
        } catch {
            $failure='Aura profile restoration failed: '+$_.Exception.Message
        }
    }
    Finish-UiAction
    Write-Hidden
    if($null -ne $failure) { Set-Status ('ERROR|'+$failure) } else { Set-Status 'RESTORED|Aura lighting effect selected' }
}
if($null -ne $failure) { exit 1 }
