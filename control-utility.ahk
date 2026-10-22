#Requires AutoHotkey v2.0
#Warn All, StdOut
DetectHiddenWindows(true)
target := A_ScriptDir "\ScreenOffWindows.ahk ahk_class AutoHotkey"
if A_Args.Length && (A_Args[1] = "--exit" || A_Args[1] = "--exit-if-idle") {
    if hwnd := WinExist(target) {
        if A_Args[1] = "--exit-if-idle" && SendMessage(0x8020,0,0,,"ahk_id " hwnd,,,,2000) != 1 {
            FileAppend("Screen Off is busy; it was left running.`n", "**")
            ExitApp(2)
        }
        PostMessage(0x111, 65307, 0, , "ahk_id " hwnd)
    }
} else if A_Args.Length && A_Args[1] = "--settings" {
    if hwnd := WinExist(target)
        PostMessage(0x8021,0,0,,"ahk_id " hwnd)
} else if A_Args.Length && A_Args[1] = "--press-off" {
    binding := IniRead(A_ScriptDir "\settings.ini", "Keys", "OffHotkey", "^!F12")
    modifiers := RegExReplace(binding, "[^\^!+#]")
    key := RegExReplace(binding, "^[~*$<>^!+#]+")
    SendEvent(modifiers "{" key "}")
}
