#Requires AutoHotkey v2.0
#Warn All, StdOut
target := "Screen Off - Settings ahk_exe AutoHotkey64.exe"
try {
    if !WinExist(target)
        throw Error("Open the utility settings before this UI test.")
    ControlSetText("NotARealKey", "Edit1", target)
    ControlClick("Save settings", target)
    Sleep(150)
    if !InStr(WinGetText(target), "Choose a shortcut and a valid single wake key.")
        throw Error("Invalid wake key was not rejected inline.")
    ControlSetText("Space", "Edit1", target)
    ; Edit3 is the notice lifetime, distinct from the wake key and server port.
    ControlSetText("0", "Edit3", target)
    ControlClick("Save settings", target)
    Sleep(150)
    if !InStr(WinGetText(target), "Notification duration must be 1 to 120 whole seconds.")
        throw Error("Invalid notification duration was not rejected inline.")
    ControlSetText("30", "Edit3", target)
    ControlClick("Save settings", target)
    if !WinWaitClose(target, , 2)
        throw Error("Settings did not close after saving.")
    if IniRead(A_ScriptDir "\settings.ini", "Keys", "WakeKey") != "Space"
        throw Error("Wake setting was not persisted.")
    if IniRead(A_ScriptDir "\settings.ini", "UI", "NoticeSeconds") != "30"
        throw Error("Notification duration was not persisted.")
    if !WinExist("Screen Off notice ahk_exe AutoHotkey64.exe")
        throw Error("Settings-saved toast was not displayed.")
    FileAppend("PASS invalid key/duration feedback, valid Save, persisted key/duration, and visible toast.`n", "*")
} catch Error as err {
    FileAppend("FAIL " err.Message "`n", "**")
    ExitApp(1)
}
