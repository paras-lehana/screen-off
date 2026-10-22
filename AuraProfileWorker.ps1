param(
    [Parameter(Mandatory=$true)][int]$ParentId,
    [Parameter(Mandatory=$true)][string]$StatePrefix,
    [ValidateSet('breathing','rainbow','colorcycle','static','dark')][string]$WakeEffect = 'breathing',
    [ValidateSet(0,1)][int]$RestorePrevious = 0
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
$AURA_UI_TIMEOUT_MS = 12000
$AURA_UI_POLL_MS = 150
# Owner 21 Oct: close Armoury Crate after every off/on change, so it is never left on
# screen. $false restores the earlier behavior (re-minimize only if it was minimized).
$AURA_CLOSE_AFTER_ACTION = $true
# Pause between selecting an effect and closing the window, so the app hands it to the service.
$AURA_SETTLE_MS = 1500
$AURA_CLOSE_TIMEOUT_MS = 5000
$OWNER_POLL_MS = 250
$ErrorActionPreference = 'Stop'
$encoding = New-Object System.Text.UTF8Encoding($false)
$changed = $false
$restoring = $false
$window = $null
$failure = $null
$restoreId = $AURA_EFFECT_IDS[$WakeEffect]
$parentProcess = $null
$minimizeAfterAction = $false
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
function Open-Effects {
    $condition=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$AURA_WINDOW_NAME)
    $script:window=[System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children,$condition)
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
    }
    # A minimized UWP window exposes zero descendants. Restore it for UIA; afterwards
    # Finish-UiAction closes it (or re-minimizes it when closing is turned off).
    $windowPattern=$script:window.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern)
    if($windowPattern.Current.WindowVisualState -eq [System.Windows.Automation.WindowVisualState]::Minimized) {
        $script:minimizeAfterAction=$true
        $windowPattern.SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Normal)
    }
    Select-Element (Wait-Element $script:window $AURA_NAV_NAME)
    Select-Element (Wait-Element $script:window $AURA_TAB_NAME)
    $null=Wait-Element $script:window $AURA_DARK_ID -Id
}
function Finish-UiAction {
    try {
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
    Finish-UiAction
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
        } catch {
            $failure='Aura profile restoration failed: '+$_.Exception.Message
        }
    }
    Finish-UiAction
    if($null -ne $failure) { Set-Status ('ERROR|'+$failure) } else { Set-Status 'RESTORED|Aura lighting effect selected' }
}
if($null -ne $failure) { exit 1 }
