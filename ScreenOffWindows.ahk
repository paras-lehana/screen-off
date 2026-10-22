#Requires AutoHotkey v2.0
#Warn All, StdOut
#SingleInstance Ignore
#Include InputRelease.ahk
#Include StandbyPreparation.ahk
#Include Lighting.ahk
#Include Configuration.ahk
#Include DesktopUi.ahk
#Include WakeLock.ahk
#Include DisplayPresence.ahk
; Windows display standby and temporary Aura control; no monitor DDC commands.
VERSION := "1.11"
; Armoury Crate is closed after each lighting change, so wake restarts it (owner, 21 Oct).
WAKE_LIGHTING_TIMEOUT_MS := 15000
mode := A_Args.Length ? A_Args[1] : ""
settings := A_ScriptDir "\settings.ini"
offHotkey := IniRead(settings, "Keys", "OffHotkey", "^!F12")
wakeKey := IniRead(settings, "Keys", "WakeKey", "Space")
wakeVk := GetKeyVK(wakeKey)
active := false
busy := false
preparationCancellation := ""
sawOff := false
unexpectedWakes := 0
displayState := -1
powerRegistration := 0
sessionRegistration := false
exitAfterWake := false
screensBefore := Map()
wakeGate := WakeLockGate(IniRead(settings, "Security", "LockOnWake", "1") = "1",
    Restore, LockCurrentSession, LockFailed, WakeComplete, WAKE_LIGHTING_TIMEOUT_MS)
lighting := 0
keyboard := InputHook("L0 I101")
keyboard.KeyOpt("{All}", "+S +N")
keyboard.OnKeyUp := WakeOnRelease
keyboard.OnKeyDown := EmergencyKey
InstallKeybdHook()
OnExit(Cleanup)
OnError(HandleError)
config := ScreenOffConfig.Load(settings)
noticeDurationMs := config.noticeMs
lighting := LightingSet(config)
Log("Lighting configuration: " lighting.Describe())
OnMessage(0x8020, ReloadConfiguration)
OnMessage(0x8021, ShowSettings)
if !wakeVk
    throw Error("WakeKey must be one keyboard key, for example Space or F10.")
ReleaseKeys(offHotkey, wakeKey)
Hotkey(offHotkey, TurnOff)
Hotkey("^!Esc", EmergencyExit)
HotIf((*) => busy && !active)
Hotkey("Esc", (*) => CancelPreparation())
HotIf((*) => active)
for button in ["LButton", "RButton", "MButton", "XButton1", "XButton2",
    "WheelUp", "WheelDown", "WheelLeft", "WheelRight"] {
    Hotkey("*" button, IgnoreInput)
    if !InStr(button, "Wheel")
        Hotkey("*" button " Up", IgnoreInput)
}
HotIf()

; Observe Windows display power instead of interpreting DDC declarations as state.
powerGuid := Buffer(16, 0)
DllCall("Ole32\CLSIDFromString", "wstr", "{6FE69556-704A-47A0-8F24-C28D936FDA47}", "ptr", powerGuid)
OnMessage(0x218, DisplayPowerChanged)
powerRegistration := DllCall("User32\RegisterPowerSettingNotification", "ptr", A_ScriptHwnd,
    "ptr", powerGuid, "uint", 0, "ptr")
if !powerRegistration
    throw Error("Cannot subscribe to Windows display state changes.")
OnMessage(0x2B1, SessionChanged)
sessionRegistration := !!DllCall("Wtsapi32\WTSRegisterSessionNotification",
    "ptr", A_ScriptHwnd, "uint", 0)
if !sessionRegistration
    throw Error("Cannot subscribe to Windows session notifications; utility not started.")

if mode = "--check" {
    TurnOff()
    ExitApp(1)
}
if mode = "--test-rgb" {
    try {
        lighting.Darken()
        FileAppend("RGB off for 12 seconds; display unchanged.`n", "*")
        Sleep(12000)
    } finally {
        lighting.Restore()
    }
    FileAppend("Backend release requested; check worker logs for completion. Physical result needs observation.`n", "*")
    ExitApp(0)
}

SetupTray()
Persistent()
Log("Ready v" VERSION ". Windows standby; off=" offHotkey "; wake=" wakeKey ".")
if mode = "--settings"
    ShowSettings()
if mode = "--test-cycle" {
    ; A bounded commissioning check only; normal use has no automatic wake timer.
    TurnOff()
}

FinishTest() {
    Restore()
    FileAppend("PASS timed cycle completed; physical off/input behavior needs observation.`n", "*")
    ExitApp(0)
}

IgnoreInput(*) {
    return
}

; Send standard Windows standby/on to the desktop with a bounded wait.
SetDisplayPower(state) {
    desktop := DllCall("User32\GetShellWindow", "ptr")
    if !desktop
        throw Error("Windows desktop shell is unavailable.")
    result := 0
    if !DllCall("User32\SendMessageTimeoutW", "ptr", desktop, "uint", 0x112,
        "uptr", 0xF170, "ptr", state, "uint", 2, "uint", 1000, "uptr*", &result, "ptr")
        throw Error("Windows display power request timed out.")
}

TurnOff(*) {
    global active, busy, sawOff, unexpectedWakes, preparationCancellation, screensBefore
    if active || busy || wakeGate.pending
        return
    busy := true
    preparationCancellation := ""
    if mode != "--check" {
        UpdateTray("Preparing")
        ShowNotice("Turning off screen and lights...", "Release the shortcut. Preparing lighting first."
            . "`nStandby starts as soon as lighting is ready."
            . "`n" wakeKey " wakes afterward. Your apps keep running."
            . "`nEsc or Cancel stops preparation.", noticeDurationMs, (*) => CancelPreparation())
    }
    Log("Off requested" (mode = "--check" ? " (read-only activation check)." : "."))
    try {
        WaitForReleasedInputs(offHotkey, wakeKey)
        CheckPreparationCancellation(IsPreparationCancelled)
        ; Keep BOTH display and system awake only while lighting prepares.
        if !DllCall("Kernel32\SetThreadExecutionState", "uint", 0x80000003, "uint")
            throw Error("Cannot keep Windows/display awake; cancelling preparation.")
        if mode = "--check" {
            FileAppend("PASS release check, hotkeys, power/session subscriptions and keep-awake request; backend availability not checked; no lighting/display writes or DDC.`n", "*")
            ExitApp(0)
        }
        ; Black covers first, so Armoury Crate opening for the lighting change is hidden.
        ShowCurtains()
        RaiseNotice()
        WaitForLightingBeforeStandby(ObjBindMethod(lighting,"Darken"),
            ObjBindMethod(lighting,"CheckHealth"), IsPreparationCancelled)
        WaitForReleasedInputs(offHotkey, wakeKey)
        CheckPreparationCancellation(IsPreparationCancelled)
        if problem := lighting.CheckHealth()
            throw Error("Lighting stopped before standby: " problem)
        Critical("On")
        CheckPreparationCancellation(IsPreparationCancelled)
        ; Keep the notice's independent expiry timer. Curtains/standby obscure it;
        ; it never keeps the display on or delays input suppression.
        ; Drop only the display requirement. Apps/system remain awake while dark.
        if !DllCall("Kernel32\SetThreadExecutionState", "uint", 0x80000001, "uint")
            throw Error("Cannot retain the keep-awake request; cancelling standby.")
        screensBefore := AttachedScreens()
        active := true
        sawOff := false
        unexpectedWakes := 0
        keyboard.Start()
        BlockInput("MouseMove")
        UpdateTray("Off")
        SetDisplayPower(2)
        SetTimer(CheckLighting, 5000)
        Log("Windows display-off requested for " MonitorGetCount() " display(s): " DescribeScreens(screensBefore) ".")
        if mode = "--test-cycle"
            SetTimer(FinishTest, -12000)
    } catch Error as err {
        try Restore()
        try HideCurtains() ; Restore() skips covers while preparation is not yet active.
        try lighting.Restore()
        DllCall("Kernel32\SetThreadExecutionState", "uint", 0x80000000, "uint")
        Log("Off cancelled: " err.Message)
        if mode != "" {
            FileAppend("FAIL activation: " err.Message "`n", "**")
            ExitApp(1)
        }
        ShowNotice(err is PreparationCancelled ? "Screen-off cancelled" : "Screen-off could not start",
            err is PreparationCancelled ? preparationCancellation " Lighting restoration requested." : err.Message)
        UpdateTray(err is PreparationCancelled ? "Ready" : "Ready - last attempt failed")
    } finally {
        Critical("Off")
        busy := false
    }
}

IsPreparationCancelled() => preparationCancellation != ""

CancelPreparation(reason := "Cancelled by you.") {
    global preparationCancellation
    if busy && !active {
        preparationCancellation := reason
        lighting.Restore()
    }
}

; Hooks suppress ordinary input. An app/driver wake is switched off again until
; the wake key is used. External wakes can briefly flash; this is not a hardware lock.
DisplayPowerChanged(wParam, lParam, *) {
    global displayState, sawOff, unexpectedWakes
    if wParam != 0x8013 || !lParam
        return
    if DllCall("msvcrt\memcmp", "ptr", lParam, "ptr", powerGuid, "uptr", 16, "int")
        || NumGet(lParam, 16, "uint") < 4
        return
    displayState := NumGet(lParam, 20, "uint")
    Log("Windows display state=" displayState ".")
    wakeGate.ObserveDisplay(displayState)
    if active {
        if displayState = 0
            sawOff := true
        else {
            if sawOff
                unexpectedWakes += 1
            SetTimer(ReapplyOff, -1)
        }
    }
    return 1
}

CheckLighting() {
    if !active
        return
    problem := lighting.CheckHealth()
    if problem != "" {
        Log("RGB health: " problem "; display remains off until wake key.")
        UpdateTray("Off - RGB error")
        SetTimer(CheckLighting, 0)
    }
}

ReapplyOff() {
    if active
        SetDisplayPower(2)
}

WakeOnRelease(hook, vk, sc) {
    if active && vk = wakeVk
        RequestWake()
}

RequestWake() {
    if !active || wakeGate.pending
        return
    Log("Wake requested; lock-on-wake=" wakeGate.enabled ".")
    wakeGate.Request(A_TickCount)
    if wakeGate.pending {
        UpdateTray("Recovering")
        SetTimer(PollWake, 100)
    }
}

LockCurrentSession() {
    return !!DllCall("User32\LockWorkStation", "int")
}

PollWake() {
    wakeGate.Poll(A_TickCount,lighting.RestoreStatus())
}

WakeComplete() {
    SetTimer(PollWake,0)
    UpdateTray()
    ; Monitors re-enumerate a few seconds after the signal returns.
    if screensBefore.Count
        SetTimer(CheckScreensReturned, -8000)
    ; A lighting system that could not be controlled stayed lit; say so once awake.
    if lighting.skipped.Length
        SetTimer(() => ShowNotice("Some lights were not turned off", lighting.SkippedText()
            . "`nSee Settings > Lighting and the RGB logs.", 20000), -1500)
    if exitAfterWake
        SetTimer((*) => ExitApp(),-10)
}

; Windows reports display-on even when a monitor stays dark or disappears.
CheckScreensReturned() {
    global screensBefore
    now := AttachedScreens()
    missing := MissingScreens(screensBefore, now)
    screensBefore := Map()
    if !missing.Length {
        Log("Screens back after wake: " DescribeScreens(now) ".")
        return
    }
    list := ""
    for label in missing
        list .= (list = "" ? "" : ", ") label
    Log("Screens missing after wake: " list "; present: " DescribeScreens(now) ".")
    UpdateTray("Ready - " list " missing")
    ShowNotice(list " did not come back", RecoveryAdvice(missing), 30000)
}

LockFailed(message) {
    Log("Wake recovery: " message)
    UpdateTray("Check wake log")
    ShowNotice("Screen Off recovery",message)
}

SessionChanged(event, sessionId, *) {
    if event = 7 {
        Log("Windows confirmed session locked.")
        CancelPreparation("Windows locked during preparation.")
        if active {
            Restore(false) ; External lock: release input without forcing wake.
        }
        wakeGate.Confirm()
    } else if event = 8 {
        Log("Windows confirmed session unlocked.")
        UpdateTray()
    }
}

EmergencyKey(hook, vk, sc) {
    if vk = 0x1B && GetKeyState("Ctrl", "P") && GetKeyState("Alt", "P")
        EmergencyExit()
}

EmergencyExit(*) {
    global exitAfterWake
    if active && wakeGate.enabled {
        exitAfterWake := true
        RequestWake()
        return
    }
    Restore()
    ExitApp()
}

Restore(restoreDisplay := true, *) {
    global active
    HideNotice() ; Never show a stale "turning off" message after wake/cancel.
    if !active {
        if IsObject(lighting)
            lighting.Restore()
        return
    }
    Critical("On")
    active := false
    SetTimer(ReapplyOff, 0)
    SetTimer(CheckLighting, 0)
    try {
        ; Release input and covers before requesting power or waiting on a worker.
        keyboard.Stop()
        BlockInput("MouseMoveOff")
        HideCurtains()
        lighting.Restore()
        if restoreDisplay {
            SetDisplayPower(-1)
            DllCall("Kernel32\SetThreadExecutionState", "uint", 0x2, "uint")
        }
    } finally {
        try keyboard.Stop()
        try BlockInput("MouseMoveOff")
        try HideCurtains()
        DllCall("Kernel32\SetThreadExecutionState", "uint", 0x80000000, "uint")
        Critical("Off")
        ; Input is released before the service call, even if Aura takes time.
        lighting.Restore()
        UpdateTray()
    }
    Log("Off mode ended; display-on-request=" restoreDisplay "; input restored; lighting release requested. Lock has not been requested by recovery yet.")
}

ApplyConfiguration(cfg) {
    global offHotkey,wakeKey,wakeVk,lighting,noticeDurationMs
    ScreenOffConfig.Validate(cfg)
    if active || busy || wakeGate.pending || (lighting.workerPid && ProcessExist(lighting.workerPid))
        throw Error("Wait until screen-off recovery and lighting restoration finish before changing settings.")
    Hotkey(cfg.off,TurnOff)
    if cfg.off!=offHotkey
        Hotkey(offHotkey,"Off")
    offHotkey := cfg.off, wakeKey := cfg.wake, wakeVk := GetKeyVK(cfg.wake)
    noticeDurationMs := cfg.noticeMs
    lighting := LightingSet(cfg)
    wakeGate.enabled := cfg.lock
    UpdateTray()
}

ReloadConfiguration(command,*) {
    if active || busy || wakeGate.pending || (lighting.workerPid && ProcessExist(lighting.workerPid))
        return 2
    if command=0
        return 1
    try {
        ApplyConfiguration(ScreenOffConfig.Load(settings))
        Log("Configuration reloaded from command line; " lighting.Describe())
        return 1
    } catch Error as err {
        Log("Configuration rejected: " err.Message)
        return 3
    }
}

Cleanup(*) {
    try Restore()
    DllCall("Kernel32\SetThreadExecutionState", "uint", 0x80000000, "uint")
    if powerRegistration
        DllCall("User32\UnregisterPowerSettingNotification", "ptr", powerRegistration)
    if sessionRegistration
        DllCall("Wtsapi32\WTSUnRegisterSessionNotification", "ptr", A_ScriptHwnd)
}

HandleError(err, *) {
    try Restore()
    Log("Error: " err.Message)
    if mode != ""
        FileAppend(err.Message "`n", "**")
    else
        TrayTip(err.Message, "Screen Off stopped")
    ExitApp(1)
}

Log(message) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n",
        A_ScriptDir "\screen-off.log", "UTF-8")
}
