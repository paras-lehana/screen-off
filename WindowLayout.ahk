#Requires AutoHotkey v2.0
; Saves and restores top-level window placements around display standby. DisplayPort
; monitors disconnect while asleep and Windows moves their windows to the remaining screen;
; this puts them back once the screens have returned. Only windows that moved are touched.
class WindowLayout {
    static PLACEMENT_SIZE := 44   ; WINDOWPLACEMENT
    static WPF_ASYNC := 4         ; never block on a hung application

    ; Windows the user can see and arrange: visible, captioned, not tool/cloaked/shell windows.
    static Eligible(hwnd) {
        try {
            style := WinGetStyle(hwnd), ex := WinGetExStyle(hwnd)
            if !(style & 0x10000000) || (style & 0x00C00000) != 0x00C00000 || (ex & 0x80)
                return false
            if WinGetPID(hwnd) = ProcessExist() || WinGetTitle(hwnd) = ""
                return false
            if RegExMatch(WinGetClass(hwnd), "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$")
                return false
            cloaked := 0
            DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14, "int*", &cloaked, "uint", 4)
            return !cloaked
        } catch
            return false
    }

    static Capture() {
        saved := []
        previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        try {
            for hwnd in WinGetList() {
                if !this.Eligible(hwnd)
                    continue
                placement := Buffer(this.PLACEMENT_SIZE, 0)
                NumPut("uint", this.PLACEMENT_SIZE, placement)
                if DllCall("GetWindowPlacement", "ptr", hwnd, "ptr", placement)
                    saved.Push({hwnd: hwnd, placement: placement})
            }
        } finally
            DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
        return saved
    }

    ; Same show state class (normal/minimized/maximized) and same normal rectangle.
    static Moved(saved, current) {
        if this.StateOf(NumGet(saved, 8, "uint")) != this.StateOf(NumGet(current, 8, "uint"))
            return true
        loop 4
            if NumGet(saved, 24 + 4*A_Index, "int") != NumGet(current, 24 + 4*A_Index, "int")
                return true
        return false
    }
    static StateOf(showCmd) => showCmd = 2 || showCmd = 6 || showCmd = 7 ? "min" : showCmd = 3 ? "max" : "normal"

    ; Puts moved windows back. Returns the number of windows moved.
    static Restore(saved) {
        moved := 0
        foreground := DllCall("GetForegroundWindow", "ptr")
        previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        try {
            for item in saved {
                if !WinExist("ahk_id " item.hwnd)
                    continue
                current := Buffer(this.PLACEMENT_SIZE, 0)
                NumPut("uint", this.PLACEMENT_SIZE, current)
                if !DllCall("GetWindowPlacement", "ptr", item.hwnd, "ptr", current) || !this.Moved(item.placement, current)
                    continue
                state := this.StateOf(NumGet(item.placement, 8, "uint"))
                target := Buffer(this.PLACEMENT_SIZE)
                DllCall("RtlMoveMemory", "ptr", target, "ptr", item.placement, "uptr", this.PLACEMENT_SIZE)
                NumPut("uint", this.WPF_ASYNC, target, 4)
                ; Normal placement first (lands on the original monitor), without activation;
                ; a maximized window is then maximized there.
                NumPut("uint", state = "min" ? 7 : 4, target, 8)
                DllCall("SetWindowPlacement", "ptr", item.hwnd, "ptr", target)
                if state = "max"
                    DllCall("ShowWindowAsync", "ptr", item.hwnd, "int", 3)
                moved += 1
            }
        } finally
            DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
        if moved && foreground
            try WinActivate("ahk_id " foreground)
        return moved
    }
}
