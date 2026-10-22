#Requires AutoHotkey v2.0
; Wait only on meaningful activation inputs, never all reserved/driver virtual keys.
ReleaseKeys(offBinding, wakeKey) {
    trigger := RegExReplace(RegExReplace(offBinding, "^[~*$<>^!+#]+"), "i)\s+up$")
    if !GetKeyVK(trigger)
        throw Error("OffHotkey must be modifiers plus one keyboard key, such as ^!F12.")
    return [trigger, wakeKey, "LControl", "RControl", "LAlt", "RAlt", "LShift",
        "RShift", "LWin", "RWin", "LButton", "RButton", "MButton", "XButton1", "XButton2"]
}

; Use Windows' current state rather than a resident hook's possibly stale snapshot.
IsInputDownNow(key) {
    return !!(DllCall("User32\GetAsyncKeyState", "int", GetKeyVK(key), "short") & 0x8000)
}

WaitForReleasedInputs(offBinding, wakeKey, timeoutMs := 5000, stateReader := 0) {
    if !IsObject(stateReader)
        stateReader := IsInputDownNow
    deadline := A_TickCount + timeoutMs
    keys := ReleaseKeys(offBinding, wakeKey)
    Loop {
        held := ""
        for key in keys {
            if stateReader.Call(key) {
                held := key
                break
            }
        }
        if held = ""
            return
        if A_TickCount >= deadline
            throw Error("Release " held " and try the screen-off shortcut again.")
        Sleep(25)
    }
}
