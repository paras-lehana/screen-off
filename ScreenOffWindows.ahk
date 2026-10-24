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
#Include WindowLayout.ahk
; Windows display standby and temporary Aura control; no monitor DDC commands.
VERSION := "1.14"
; Armoury Crate is closed after each lighting change, so wake restarts it (owner, 21 Oct).
WAKE_LIGHTING_TIMEOUT_MS := 75000
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
lightingBusy := false
standbyRequested := false
layoutSnapshot := []
layoutScreens := Map()
layoutValidUntil := 0
wakeEarly := false
wakeFinishStarted := 0
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
HotIf((*) => busy)
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
    global active, busy, sawOff, unexpectedWakes, preparationCancellation, screensBefore, lightingBusy, standbyRequested, layoutSnapshot, layoutScreens
    if active || busy || wakeGate.pending
        return
    busy := true
    preparationCancellation := ""
    if mode != "--check" {
        UpdateTray("Turning off")
        ShowNotice("Turning off screen and lights...", "Screens go dark now; lights and apps are handled next, out of sight."
            . "`n" wakeKey " wakes everything: lights first, then the screens. Esc cancels."
            . "`nYour apps keep running.", noticeDurationMs)
    }
    Log("Off requested" (mode = "--check" ? " (read-only activation check)." : "."))
    try {
        WaitForReleasedInputs(offHotkey, wakeKey)
        CheckPreparationCancellation(IsPreparationCancelled)
        if !DllCall("Kernel32\SetThreadExecutionState", "uint", 0x80000001, "uint")
            throw Error("Cannot keep Windows awake; cancelling.")
        if mode = "--check" {
            FileAppend("PASS release check, hotkeys, power/session subscriptions and keep-awake request; backend availability not checked; no lighting/display writes or DDC.`n", "*")
            ExitApp(0)
        }
        ; 1) Screens look off at once: black covers and input block. The display stays powered
        ;    while the lighting apps work, because Armoury Crate builds no UI during standby
        ;    (23 Oct: "control unavailable" and a display wake when it ran after standby).
        Critical("On")
        screensBefore := AttachedScreens()
        layoutSnapshot := WindowLayout.Capture()
        layoutScreens := screensBefore.Clone()
        active := true
        sawOff := false
        unexpectedWakes := 0
        keyboard.Start()
        BlockInput("MouseMove")
        ShowCurtains()
        RaiseNotice()
        UpdateTray("Off")
        Critical("Off")
        ; 2) Lighting systems and their apps, hidden behind the covers.
        lightingBusy := true
        try {
            WaitForLightingBeforeStandby(ObjBindMethod(lighting,"Darken"),
                ObjBindMethod(lighting,"CheckHealth"), IsPreparationCancelled)
        } catch PreparationCancelled {
            Log("Lighting preparation stopped by Esc or wake.")
            return ; that path restores lighting, then lifts the covers
        } catch Error as lightingError {
            ; The screens still go off; the skipped systems are reported after wake.
            Log("No lighting system could be controlled: " lightingError.Message)
        } finally {
            lightingBusy := false
        }
        if !active
            return
        ; 3) Then real display standby.
        standbyRequested := true
        SetDisplayPower(2)
        Log("Windows display-off requested for " MonitorGetCount() " display(s): " DescribeScreens(screensBefore)
            . "; " layoutSnapshot.Length " window positions saved.")
        SetTimer(CheckLighting, 5000)
        if wakeEarly
            RequestWake()
        if mode = "--test-cycle"
            SetTimer(FinishTest, -12000)
    } catch Error as err {
        try Restore()
        try HideCurtains() ; Restore() keeps the covers until lighting is released.
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

; Cancelled by a lock during preparation, or by a wake request once the screens are off.
IsPreparationCancelled() => PreparationShouldStop(preparationCancellation, lightingBusy, active)

; Esc is the only user cancel. Before the screens are off it just stops preparation; once they
; are off it restores lights, then screens, without locking. restoreScreens := false is for an
; external Windows lock, which never counts as the user's cancel.
CancelPreparation(reason := "Cancelled with Esc.", restoreScreens := true) {
    global preparationCancellation
    if !busy
        return
    preparationCancellation := reason
    lighting.Restore()
    if active && restoreScreens {
        Log("Esc pressed: restoring lights, then screens.")
        Restore()
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
    if active && standbyRequested {
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
    if active && standbyRequested
        SetDisplayPower(2)
}

WakeOnRelease(hook, vk, sc) {
    if active && vk = wakeVk
        RequestWake()
}

RequestWake() {
    global wakeEarly
    if !active || wakeGate.pending
        return
    if lightingBusy {
        ; Stop the lighting step first; the wake itself follows from that.
        wakeEarly := true
        Log("Wake requested while lighting was being turned off; stopping that step.")
        SetTimer(RequestWake, -150)
        return
    }
    wakeEarly := false
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
    global layoutValidUntil
    SetTimer(PollWake,0)
    layoutValidUntil := A_TickCount + 15*60000
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

; Puts windows back where they were before standby (only within 15 minutes of the wake).
RestoreLayout(reason) {
    if !layoutSnapshot.Length || A_TickCount >= layoutValidUntil
        return
    if MissingScreens(layoutScreens, AttachedScreens()).Length
        return
    moved := WindowLayout.Restore(layoutSnapshot)
    Log("Window layout (" reason "): " moved " of " layoutSnapshot.Length " windows moved back.")
}

; Windows reports display-on even when a monitor stays dark or disappears.
CheckScreensReturned() {
    global screensBefore
    now := AttachedScreens()
    missing := MissingScreens(screensBefore, now)
    screensBefore := Map()
    if !missing.Length {
        Log("Screens back after wake: " DescribeScreens(now) ".")
        RestoreLayout("screens back")
        SetTimer(() => RestoreLayout("settled"), -5000)
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
        CancelPreparation("Windows locked during preparation.", false)
        if active {
            Restore(false) ; External lock: release input without forcing wake.
        }
        wakeGate.Confirm()
    } else if event = 8 {
        Log("Windows confirmed session unlocked.")
        ; Windows can rearrange windows again when the desktop returns after sign-in.
        if layoutSnapshot.Length && A_TickCount < layoutValidUntil
            SetTimer(() => RestoreLayout("after sign-in"), -2000)
        UpdateTray()
    }
}

EmergencyKey(hook, vk, sc) {
    if vk != 0x1B
        return
    if GetKeyState("Ctrl", "P") && GetKeyState("Alt", "P")
        EmergencyExit()
    else if busy
        CancelPreparation()
}

EmergencyExit(*) {
    global exitAfterWake
    if active && wakeGate.enabled {
        exitAfterWake := true
        RequestWake()
        return
    }
    Restore(true, true)
    ExitApp()
}

; Wake order: release input, restore lighting and apps while the screens are still dark
; (covers up, display in standby), and only then bring the screens back.
Restore(restoreDisplay := true, synchronous := false, *) {
    global active, wakeFinishStarted, standbyRequested
    standbyRequested := false
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
        keyboard.Stop()
        BlockInput("MouseMoveOff")
        lighting.Restore()
        if !restoreDisplay
            HideCurtains() ; external lock: the lock screen is already showing
    } finally {
        try keyboard.Stop()
        try BlockInput("MouseMoveOff")
        Critical("Off")
    }
    if !restoreDisplay {
        DllCall("Kernel32\SetThreadExecutionState", "uint", 0x80000000, "uint")
        UpdateTray()
        Log("Off mode ended; display left to Windows (external lock); input restored; lighting release requested.")
        return
    }
    ; Power the display behind the black covers so Armoury Crate can restore its effect;
    ; the covers lift only after every lighting system has released.
    try SetDisplayPower(-1)
    DllCall("Kernel32\SetThreadExecutionState", "uint", 0x2, "uint")
    Log("Wake: input restored; display on behind covers; lighting release requested.")
    wakeFinishStarted := A_TickCount
    if synchronous {
        while !FinishWakeDisplay()
            Sleep(100)
    } else
        SetTimer(FinishWakeDisplay, 100)
}

; Returns true when finished. Waits for the lighting workers (and their apps) to release,
; at most 65 s, then lifts the covers (display-on is requested again in case it slept).
FinishWakeDisplay() {
    status := IsObject(lighting) ? lighting.RestoreStatus() : "restored"
    if status = "pending" && A_TickCount-wakeFinishStarted < 65000
        return false
    SetTimer(FinishWakeDisplay, 0)
    Critical("On")
    try HideCurtains()
    try SetDisplayPower(-1)
    DllCall("Kernel32\SetThreadExecutionState", "uint", 0x2, "uint")
    DllCall("Kernel32\SetThreadExecutionState", "uint", 0x80000000, "uint")
    Critical("Off")
    UpdateTray()
    Log("Lighting " (status = "restored" ? "restored" : "finished with " status) " after " (A_TickCount-wakeFinishStarted) " ms; covers lifted.")
    return true
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
    try Restore(true, true)
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
