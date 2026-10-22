#Requires AutoHotkey v2.0
; Which physical screens were attached before off mode, and which did not return.
; Reporting only: no monitor commands. Windows standby (signal off/on) is the only
; power path; DDC power-off is banned because the Odyssey cannot be woken over DP.
SCREEN_LABELS := Map("SAM7058", "Odyssey G7", "SAM705A", "Odyssey G7", "SAM0FDC", "C27JG5x")
ODYSSEY_RECOVERY := "Odyssey: check the monitor input matches its cable (DP IN 1/2). If it stays dark,"
    . " follow recovery\README.md in the Screen Off folder (HDMI + Odyssey-NvWake.ps1)."

; Label -> hardware ID for every active monitor on the desktop.
AttachedScreens() {
    screens := Map()
    Loop MonitorGetCount() {
        adapter := MonitorGetName(A_Index)
        device := Buffer(840, 0) ; DISPLAY_DEVICEW
        index := 0
        loop {
            NumPut("uint", 840, device)
            if !DllCall("User32\EnumDisplayDevicesW", "str", adapter, "uint", index++, "ptr", device, "uint", 1)
                break
            if !(NumGet(device, 324, "uint") & 1) ; DISPLAY_DEVICE_ACTIVE
                continue
            if RegExMatch(StrGet(device.Ptr + 328, 128), "#([A-Z]{3}[0-9A-F]{4})#", &id)
                screens[ScreenLabel(id[1])] := id[1]
        }
    }
    return screens
}

ScreenLabel(id) => SCREEN_LABELS.Has(id) ? SCREEN_LABELS[id] : id

; Pure comparison used by the utility and offline tests.
MissingScreens(before, after) {
    missing := []
    for label in before
        if !after.Has(label)
            missing.Push(label)
    return missing
}

DescribeScreens(screens) {
    text := ""
    for label, id in screens
        text .= (text = "" ? "" : ", ") label " (" id ")"
    return text = "" ? "none" : text
}

RecoveryAdvice(missing) {
    for label in missing
        if label = "Odyssey G7"
            return ODYSSEY_RECOVERY
    return "Check the monitor's input selection and cable."
}
