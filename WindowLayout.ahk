#Requires AutoHotkey v2.0
; Saves and restores top-level window placements around display standby. DisplayPort
; monitors disconnect while asleep and Windows moves their windows to the remaining screen;
; this puts them back once the screens have returned. Only windows that moved are touched.
;
; A maximized window keeps its "restored" rectangle when Windows moves it to another monitor,
; so the placement alone cannot tell that it moved. The monitor each window is on is saved too.
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

    ; "left,top,right,bottom" of the monitor the window is mostly on ("" if unknown).
    static MonitorOf(hwnd) {
        monitor := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
        info := Buffer(40, 0)
        NumPut("uint", 40, info)
        if !monitor || !DllCall("GetMonitorInfoW", "ptr", monitor, "ptr", info)
            return ""
        return NumGet(info, 4, "int") "," NumGet(info, 8, "int") "," NumGet(info, 12, "int") "," NumGet(info, 16, "int")
    }

    static Capture() {
        saved := []
        previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        try {
            for hwnd in WinGetList() {
                if !this.Eligible(hwnd)
                    continue
                bytes := Buffer(this.PLACEMENT_SIZE, 0)
                NumPut("uint", this.PLACEMENT_SIZE, bytes)
                if DllCall("GetWindowPlacement", "ptr", hwnd, "ptr", bytes)
                    saved.Push({hwnd: hwnd, placement: bytes, monitor: this.MonitorOf(hwnd)})
            }
        } finally
            DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
        return saved
    }

    ; Moved if the show state, the restored rectangle or the monitor differs from the saved one.
    static Moved(saved, current, savedMonitor := "", currentMonitor := "") {
        if this.StateOf(NumGet(saved, 8, "uint")) != this.StateOf(NumGet(current, 8, "uint"))
            return true
        if savedMonitor != "" && currentMonitor != "" && savedMonitor != currentMonitor
            return true
        loop 4
            if NumGet(saved, 24 + 4*A_Index, "int") != NumGet(current, 24 + 4*A_Index, "int")
                return true
        return false
    }
    static StateOf(showCmd) => showCmd = 2 || showCmd = 6 || showCmd = 7 ? "min" : showCmd = 3 ? "max" : "normal"

    ; Shifts the restored rectangle so its centre lies on the saved monitor. A maximized window
    ; is maximized on the monitor that holds its restored rectangle.
    static PlaceOn(target, monitor) {
        parts := StrSplit(monitor, ",")
        if parts.Length != 4
            return
        left := NumGet(target, 28, "int"), top := NumGet(target, 32, "int")
        right := NumGet(target, 36, "int"), bottom := NumGet(target, 40, "int")
        centerX := (left + right) // 2, centerY := (top + bottom) // 2
        if centerX >= parts[1] && centerX < parts[3] && centerY >= parts[2] && centerY < parts[4]
            return
        width := right - left, height := bottom - top
        newLeft := parts[1] + (parts[3] - parts[1] - width) // 2
        newTop := parts[2] + (parts[4] - parts[2] - height) // 2
        NumPut("int", newLeft, target, 28), NumPut("int", newTop, target, 32)
        NumPut("int", newLeft + width, target, 36), NumPut("int", newTop + height, target, 40)
    }

    ; Puts moved windows back. Returns the number of windows moved.
    static Restore(saved) {
        moved := 0
        foreground := DllCall("GetForegroundWindow", "ptr")
        previous := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        try {
            for saveItem in saved {
                if !WinExist("ahk_id " saveItem.hwnd)
                    continue
                current := Buffer(this.PLACEMENT_SIZE, 0)
                NumPut("uint", this.PLACEMENT_SIZE, current)
                if !DllCall("GetWindowPlacement", "ptr", saveItem.hwnd, "ptr", current)
                    continue
                if !this.Moved(saveItem.placement, current, saveItem.monitor, this.MonitorOf(saveItem.hwnd))
                    continue
                state := this.StateOf(NumGet(saveItem.placement, 8, "uint"))
                goal := Buffer(this.PLACEMENT_SIZE)
                DllCall("RtlMoveMemory", "ptr", goal, "ptr", saveItem.placement, "uptr", this.PLACEMENT_SIZE)
                NumPut("uint", this.WPF_ASYNC, goal, 4)
                ; Without activation: 4 = SW_SHOWNOACTIVATE, 7 = SW_SHOWMINNOACTIVE, 3 = maximized.
                if state = "max" {
                    ; An already-maximized window ignores a second "maximize", so restore it onto
                    ; the saved monitor first, then maximize there.
                    this.PlaceOn(goal, saveItem.monitor)
                    NumPut("uint", 4, goal, 8)
                    DllCall("SetWindowPlacement", "ptr", saveItem.hwnd, "ptr", goal)
                    Sleep(40)
                    NumPut("uint", 3, goal, 8)
                } else
                    NumPut("uint", state = "min" ? 7 : 4, goal, 8)
                DllCall("SetWindowPlacement", "ptr", saveItem.hwnd, "ptr", goal)
                moved += 1
            }
        } finally
            DllCall("SetThreadDpiAwarenessContext", "ptr", previous, "ptr")
        if moved && foreground
            try WinActivate("ahk_id " foreground)
        return moved
    }
}
