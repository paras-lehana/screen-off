#Requires AutoHotkey v2.0

FriendlyKey(binding) {
    prefix := ""
    for modifier in [["^", "Ctrl+"], ["!", "Alt+"], ["+", "Shift+"], ["#", "Win+"]]
        if InStr(binding, modifier[1])
            prefix .= modifier[2]
    return prefix RegExReplace(binding, "^[~*$<>^!+#]+")
}

UpdateTray(state := "Ready") {
    global uiState := state
    systems := ""
    for controller in lighting.controllers
        systems .= (systems = "" ? "" : " + ") StrReplace(controller.label, "Dynamic Lighting", "Dynamic")
    tip := "Screen Off " VERSION " | " state "`nOff: " FriendlyKey(offHotkey)
        . " | Wake: " wakeKey "`nLights: " (systems = "" ? "none" : systems)
        . "`nLock: " (wakeGate.enabled ? "yes" : "no")
    A_IconTip := SubStr(tip, 1, 127)
    try TraySetIcon(A_ScriptDir "\assets\" (active ? "screen-off-dark.ico" : "screen-off.ico"))
    Log("Tray: " StrReplace(A_IconTip, "`n", " | "))
}

SetupTray() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Turn screen and lights off", TurnOff)
    A_TrayMenu.Add("Settings...", ShowSettings)
    A_TrayMenu.Default := "Settings..."
    A_TrayMenu.Add()
    A_TrayMenu.Add("Open activity log", (*) => Run('notepad.exe "' A_ScriptDir '\screen-off.log"'))
    A_TrayMenu.Add("Open RGB logs", (*) => Run('explorer.exe "' A_ScriptDir '\logs"'))
    A_TrayMenu.Add("Restore and exit", EmergencyExit)
    UpdateTray()
}

ShowNotice(title, detail, durationMs := 4500, cancelCallback := 0) {
    global noticeGui, noticeTitle, noticeDetail
    HideNotice()
    noticeGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "Screen Off notice")
    noticeGui.BackColor := "F4F7FB"
    noticeGui.MarginX := 20
    noticeGui.MarginY := 16
    noticeGui.SetFont("s13 c10263A", "Segoe UI")
    noticeTitle := noticeGui.AddText("w350", title)
    noticeGui.SetFont("s10 c34495E")
    noticeDetail := noticeGui.AddText("w350" (IsObject(cancelCallback) ? " h96" : ""), detail)
    if IsObject(cancelCallback) {
        cancelButton := noticeGui.AddButton("w150 h30", "Cancel (Esc)")
        cancelButton.OnEvent("Click", cancelCallback)
    }
    MonitorGetWorkArea(, &left, &top, &right, &bottom)
    noticeGui.Show("NA Hide AutoSize")
    noticeGui.GetPos(,,&noticeWidth,&noticeHeight)
    noticeGui.Show("NA x" (right-noticeWidth-20) " y" (bottom-noticeHeight-20))
    if durationMs > 0
        SetTimer(HideNotice, -durationMs)
}

HideNotice(*) {
    global noticeGui, noticeTitle, noticeDetail
    SetTimer(HideNotice, 0)
    if IsSet(noticeGui) && IsObject(noticeGui) {
        noticeGui.Destroy()
        noticeGui := 0
    }
    noticeTitle := 0, noticeDetail := 0
}

ShowCurtains() {
    global curtains
    curtains := []
    Loop MonitorGetCount() {
        MonitorGet(A_Index, &left, &top, &right, &bottom)
        cover := Gui("+AlwaysOnTop -Caption +ToolWindow", "Screen Off black cover")
        cover.BackColor := "000000"
        cover.Show("NA x" left " y" top " w" (right-left) " h" (bottom-top))
        curtains.Push(cover)
    }
    ; Present the black frame before requesting standby.
    try DllCall("dwmapi\DwmFlush")
}

; Keep the activation notice readable above the black covers during preparation.
RaiseNotice() {
    global noticeGui
    if IsSet(noticeGui) && IsObject(noticeGui)
        try WinMoveTop("ahk_id " noticeGui.Hwnd)
}

HideCurtains() {
    global curtains
    if IsSet(curtains)
        for cover in curtains
            cover.Destroy()
    curtains := []
}

ShowSettings(*) {
    global settingsGui
    if active || busy || wakeGate.pending
        return
    if IsSet(settingsGui) && IsObject(settingsGui) {
        settingsGui.Show()
        return
    }
    panel := Gui("-MaximizeBox -MinimizeBox", "Screen Off - Settings")
    settingsGui := panel
    panel.BackColor := "F4F7FB"
    panel.MarginX := 24
    panel.MarginY := 14
    panel.SetFont("s18 c10263A", "Segoe UI")
    panel.AddText("w460", "Screen Off")
    panel.SetFont("s10 c34495E")
    panel.AddText("w460", "Keep working apps awake. Put the room to sleep.")
    tabs := panel.AddTab3("xm y+12 w460 h372", ["Controls","Lighting","Aura / notice"])
    tabs.GetPos(&tabX,&tabY)
    contentX := tabX+18, contentY := tabY+42
    tabs.UseTab(1)
    panel.AddText("x" contentX " y" contentY, "Turn off shortcut")
    offField := panel.AddHotkey("x" contentX " y+6 w420", offHotkey)
    panel.AddText("x" contentX " y+14", "Wake key (press and release)")
    wakeField := panel.AddEdit("x" contentX " y+6 w420", wakeKey)
    panel.AddText("x" contentX " y+4 w420 c526476", "One key name, for example Space or F10.")
    lockField := panel.AddCheckbox("x" contentX " y+20 Checked" (wakeGate.enabled ? 1 : 0), "Require Windows sign-in after recovery")
    panel.AddText("x" contentX " y+10 w420 h60", "Wake restores input, lighting and display first, then locks Windows once both are confirmed; otherwise locking is skipped. The off shortcut works on the unlocked desktop.")
    tabs.UseTab(2)
    current := lighting.cfg
    panel.AddText("x" contentX " y" contentY, "Turn off with the screens:")
    fields := {}
    fields.aura := panel.AddCheckbox("x" contentX " y+6 Checked" (current.aura ? 1 : 0), "ASUS Aura: motherboard, RAM, GPU, strips (Armoury Crate)")
    fields.corsair := panel.AddCheckbox("x" contentX " y+6 Checked" (current.corsair ? 1 : 0), "Corsair iCUE devices (needs iCUE with its SDK enabled):")
    fields.devices := Map()
    for index, deviceType in CORSAIR_DEVICE_TYPES {
        placement := Mod(index-1,3)=0 ? "x" (contentX+22) " y+2" : "x+8 yp"
        fields.devices[deviceType] := panel.AddCheckbox(placement " w128 Checked" (InStr("," current.corsairDevices ",", "," deviceType ",") ? 1 : 0),
            Map("keyboard","Keyboard","mouse","Mouse","mousemat","Mousepad","headset","Headset","headsetstand","Headset stand",
                "cooler","Cooler / AIO","fancontroller","Fan controller","ledcontroller","LED controller","memory","Corsair RAM",
                "gamecontroller","Game controller")[deviceType])
    }
    fields.openrgb := panel.AddCheckbox("x" contentX " y+8 Checked" (current.openrgb ? 1 : 0), "OpenRGB SDK server (on its own), port")
    fields.port := panel.AddEdit("x+8 yp-3 w70 Number", current.port)
    fields.dynamic := panel.AddCheckbox("x" contentX " y+6 Checked" (current.dynamic ? 1 : 0), "Windows Dynamic Lighting (on its own)")
    lightingHint := panel.AddText("x" contentX " y+8 w420 h62 c526476",
        "Aura and Corsair can run together; OpenRGB and Dynamic Lighting run alone. "
        . "An unreachable system is skipped and reported after wake. Checks never change colours.")
    inspect := panel.AddButton("x" contentX " y+6 w200 h30", "Check ticked systems")
    windowsSettings := panel.AddButton("x+20 w200 h30", "Windows lighting settings")
    windowsSettings.OnEvent("Click",(*) => Run("ms-settings:personalization-lighting"))
    tabs.UseTab(3)
    panel.AddText("x" contentX " y" contentY, "Activation notification (seconds; does not delay standby)")
    noticeField := panel.AddEdit("x" contentX " y+6 w100 Number",noticeDurationMs//1000)
    panel.AddText("x" contentX " y+14", "Aura method")
    methodField := panel.AddDropDownList("x" contentX " y+6 w420",["Armoury Crate Dark effect (includes synced RAM)","Aura SDK (MTA; RAM not reached here)"])
    methodField.Choose(current.auraMethod="profile" ? 1 : 2)
    panel.AddText("x" contentX " y+14", "Aura lighting effect on wake")
    effectField := panel.AddDropDownList("x" contentX " y+6 w420",["Breathing (Profile 1 lighting)","Rainbow","Color Cycle","Static","Dark (keep lights off)"])
    effectIds := ["breathing","rainbow","colorcycle","static","dark"]
    for index,id in effectIds
        if id=current.auraWake
            effectField.Choose(index)
    previousField := panel.AddCheckbox("x" contentX " y+14 Checked" (current.auraPrevious ? 1 : 0),"Prefer the previously selected effect when available")
    panel.AddText("x" contentX " y+12 w420 h62 c526476","The profile method uses Windows UI Automation and may open Armoury Crate. Configure synced devices there. Only lighting effects change; full Scenario Profiles are not applied.")
    tabs.UseTab()
    panel.AddText("xm y" (tabY+380) " w460", "Ctrl+Alt+Esc restores and exits. Starts at sign-in via the Startup folder shortcut.")
    errorField := panel.AddText("xm y+6 w460 h34 cA42230", "")
    save := panel.AddButton("xm y+4 w220 h34 Default", "Save settings")
    cancel := panel.AddButton("x+20 w220 h34", "Cancel")
    form := {off:offField, wake:wakeField, lock:lockField, notice:noticeField, method:methodField,
        effect:effectField, previous:previousField, lights:fields, error:errorField}
    save.OnEvent("Click", (*) => SaveSettings(panel, form))
    for name in ["aura","corsair","openrgb","dynamic"]
        fields.%name%.OnEvent("Click", (*) => LightingFieldsChanged(fields))
    inspect.OnEvent("Click", (*) => CheckLightingSystems(SettingsFromForm(form, true), lightingHint))
    LightingFieldsChanged(fields)
    cancel.OnEvent("Click", (*) => CloseSettings(panel))
    panel.OnEvent("Close", (*) => CloseSettings(panel))
    panel.OnEvent("Escape", (*) => CloseSettings(panel))
    panel.Show("AutoSize")
}

CloseSettings(panel) {
    global settingsGui := 0
    panel.Destroy()
}

; Builds a configuration from the Settings window. Lenient mode is for the check button.
SettingsFromForm(form, lenient := false) {
    effectIds := ["breathing","rainbow","colorcycle","static","dark"]
    lights := form.lights
    devices := ""
    for deviceType in CORSAIR_DEVICE_TYPES
        if lights.devices[deviceType].Value
            devices .= (devices = "" ? "" : ",") deviceType
    cfg := {off:form.off.Value, wake:Trim(form.wake.Value), lock:!!form.lock.Value,
        aura:!!lights.aura.Value, corsair:!!lights.corsair.Value, corsairDevices:devices,
        openrgb:!!lights.openrgb.Value, dynamic:!!lights.dynamic.Value, port:Trim(lights.port.Value),
        noticeMs:ScreenOffDefaults.NoticeMs, auraMethod:form.method.Value=1 ? "profile" : "sdk",
        auraWake:effectIds[form.effect.Value], auraPrevious:!!form.previous.Value}
    if RegExMatch(form.notice.Value,"^\d+$")
        cfg.noticeMs := Integer(form.notice.Value)*1000
    else if !lenient
        throw Error("Notification duration must be whole seconds.")
    return cfg
}

SaveSettings(panel, form) {
    try {
        cfg := SettingsFromForm(form)
        ScreenOffConfig.Validate(cfg)
        ; Save is configuration only; availability is checked before any blackout.
        ApplyConfiguration(cfg)
        ScreenOffConfig.Save(settings,cfg)
        CloseSettings(panel)
        ShowNotice("Settings saved", "Lights: " ScreenOffConfig.Describe(cfg) "`nWake: " wakeKey)
    } catch Error as err {
        form.error.Text := err.Message
    }
}

; Corsair device types only matter while Corsair is ticked.
LightingFieldsChanged(lights) {
    for deviceType, box in lights.devices
        box.Enabled := !!lights.corsair.Value
    lights.port.Enabled := !!lights.openrgb.Value
}

; Read-only availability check of every ticked system. Never sets LED colours.
; Probes run in the background; the window stays responsive and fills in results.
CheckLightingSystems(cfg, help) {
    if !(cfg.aura || cfg.corsair || cfg.openrgb || cfg.dynamic) {
        help.Text := "Display only: no lighting system is ticked."
        return
    }
    state := {help:help, lines:[], probes:[], deadline:A_TickCount+30000}
    if cfg.aura {
        try {
            if cfg.auraMethod="profile" {
                if !FileExist(A_ScriptDir "\AuraProfileWorker.ps1")
                    throw Error("profile helper is missing")
                state.lines.Push("Aura: profile helper present (Armoury Crate is checked on activation)")
            } else {
                RegRead("HKCR\aura.sdk.1\CLSID")
                state.lines.Push("Aura: SDK registered")
            }
        } catch Error as err
            state.lines.Push("Aura: " err.Message)
    }
    shell := '"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Mta -ExecutionPolicy Bypass -File "'
    if cfg.corsair
        StartProbe(state, "Corsair", shell A_ScriptDir '\CorsairWorker.ps1" -Probe -ParentId ' ProcessExist() ' -Devices "' cfg.corsairDevices '" -StatePrefix "{STATE}"')
    helper := A_ScriptDir "\LightingHost\publish\ScreenOff.LightingHost.exe"
    for kind, name in Map("openrgb","OpenRGB","dynamic","Dynamic Lighting")
        if cfg.%kind% {
            if FileExist(helper)
                StartProbe(state, name, '"' helper '" --backend ' kind ' --probe 1 --state "{STATE}" --port ' cfg.port)
            else
                state.lines.Push(name ": run Build-LightingHost.ps1 first")
        }
    state.tick := PollProbes.Bind(state)
    PollProbes(state)
    if state.probes.Length
        SetTimer(state.tick, 300)
}

; Starts one read-only helper; {STATE} becomes its state-file prefix.
StartProbe(state, name, command) {
    DirCreate(A_ScriptDir "\logs")
    prefix := A_ScriptDir "\logs\probe-" A_TickCount "-" state.probes.Length
    pid := 0
    try {
        Run(StrReplace(command, "{STATE}", prefix), A_ScriptDir, "Hide", &pid)
        state.probes.Push({name:name, pid:pid, prefix:prefix, done:false})
    } catch Error as err
        state.lines.Push(name ": " err.Message)
}

PollProbes(state) {
    finished := true
    text := ""
    for line in state.lines
        text .= (text = "" ? "" : "`n") line
    for probe in state.probes {
        if !probe.done && !ProcessExist(probe.pid) {
            status := FileExist(probe.prefix ".status") ? FileRead(probe.prefix ".status","UTF-8") : "no result"
            probe.result := StrReplace(StrReplace(status,"AVAILABLE|",""),"ERROR|","")
            probe.done := true
        }
        if !probe.done && A_TickCount > state.deadline {
            probe.result := "no answer within 30 s; see the RGB logs"
            probe.done := true
        }
        finished := finished && probe.done
        text .= (text = "" ? "" : "`n") probe.name ": " (probe.done ? probe.result : "checking...")
    }
    try state.help.Text := text
    if finished {
        if state.HasOwnProp("tick")
            SetTimer(state.tick, 0)
        Log("Read-only lighting check: " StrReplace(text, "`n", " | "))
    }
}
