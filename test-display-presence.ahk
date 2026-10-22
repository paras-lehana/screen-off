#Requires AutoHotkey v2.0
#SingleInstance Off
#Include DisplayPresence.ahk
; Supplied screen sets plus one read-only enumeration; no display power or DDC traffic.
try {
    both := Map("Odyssey G7", "SAM7058", "C27JG5x", "SAM0FDC")
    Expect(MissingScreens(both, both).Length = 0, "same screens reported missing")
    gone := MissingScreens(both, Map("C27JG5x", "SAM0FDC"))
    Expect(gone.Length = 1 && gone[1] = "Odyssey G7", "lost Odyssey not reported")
    Expect(InStr(RecoveryAdvice(gone), "Odyssey-NvWake.ps1"), "Odyssey advice missing recovery tool")
    ; DP and HDMI identities are the same physical Odyssey.
    Expect(MissingScreens(both, Map("Odyssey G7", "SAM705A", "C27JG5x", "SAM0FDC")).Length = 0, "HDMI Odyssey counted as missing")
    Expect(ScreenLabel("DEL4065") = "DEL4065", "unknown monitor label changed")
    Expect(!InStr(RecoveryAdvice(["C27JG5x"]), "Odyssey"), "Odyssey advice shown for another screen")
    Expect(MissingScreens(Map(), both).Length = 0, "empty snapshot reported missing screens")
    current := AttachedScreens()
    FileAppend("PASS 7 screen-presence cases; read-only enumeration now: " DescribeScreens(current) ".`n", "*")
    ExitApp(0)
} catch Error as err {
    FileAppend("FAIL: " err.Message "`n", "**")
    ExitApp(1)
}

Expect(condition, message) {
    if !condition
        throw Error(message)
}
