#Requires AutoHotkey v2.0
#Warn All, StdOut
#Include WindowLayout.ahk
; Placement comparison with synthetic buffers, plus one read-only capture. Moves nothing.
Check(ok, label) {
    global checks
    if !ok
        throw Error(label)
    checks += 1
}
MakePlacement(showCmd, left, top, right, bottom) {
    bytes := Buffer(44, 0)
    NumPut("uint", 44, bytes), NumPut("uint", showCmd, bytes, 8)
    NumPut("int", left, bytes, 28), NumPut("int", top, bytes, 32)
    NumPut("int", right, bytes, 36), NumPut("int", bottom, bytes, 40)
    return bytes
}
checks := 0
try {
    onC27 := MakePlacement(1, 2600, 100, 3600, 900)
    Check(!WindowLayout.Moved(onC27, MakePlacement(1, 2600, 100, 3600, 900)), "Unchanged window is left alone")
    Check(WindowLayout.Moved(onC27, MakePlacement(1, 40, 100, 1040, 900)), "Window moved to the other screen is detected")
    Check(WindowLayout.Moved(MakePlacement(3, 2600, 100, 3600, 900), MakePlacement(1, 2600, 100, 3600, 900)), "Lost maximized state is detected")
    Check(!WindowLayout.Moved(MakePlacement(1, 0, 0, 10, 10), MakePlacement(5, 0, 0, 10, 10)), "SW_SHOW counts as normal")
    Check(WindowLayout.StateOf(2) = "min" && WindowLayout.StateOf(7) = "min" && WindowLayout.StateOf(3) = "max", "Show states classified")
    captured := WindowLayout.Capture()
    for entry in captured
        Check(NumGet(entry.placement, 0, "uint") = 44, "Captured placement has the right size")
    FileAppend("PASS " checks " window-layout checks; read-only capture of " captured.Length " windows now.`n", "*")
} catch Error as testError {
    FileAppend("FAIL " testError.Message " | " testError.What " line " testError.Line "`n", "**")
    ExitApp(1)
}
