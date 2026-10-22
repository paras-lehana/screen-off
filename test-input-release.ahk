#Requires AutoHotkey v2.0
#SingleInstance Off
#Include InputRelease.ahk
; Regression scenarios use supplied states; no keys are injected and no displays are changed.
try {
    ; Unrelated/reserved keys held must not prevent the shortcut from activating.
    WaitForReleasedInputs("^!F12", "Space", 100, (key) => GetKeyVK(key) = 0xE8 || key = "A")
    reads := 0
    WaitForReleasedInputs("^!F12", "Space", 200, ReleasedAfterPoll)
    ExpectTimeout("F12")
    ExpectTimeout("LControl")
    ExpectTimeout("Space")
    ExpectTimeout("LButton")
    WaitForReleasedInputs("#+F10", "Enter", 100, (key) => false)
    FileAppend("PASS 7 input-release scenarios (irrelevant keys, eventual release, held trigger/modifier/wake/mouse, custom keys).`n", "*")
    ExitApp(0)
} catch Error as err {
    FileAppend("FAIL: " err.Message "`n", "**")
    ExitApp(1)
}

ReleasedAfterPoll(key) {
    global reads
    return key = "F12" && ++reads = 1
}

ExpectTimeout(heldKey) {
    try {
        WaitForReleasedInputs("^!F12", "Space", 30, (key) => key = heldKey)
    } catch Error as err {
        if InStr(err.Message, "Release " heldKey " ")
            return
        throw err
    }
    throw Error("Did not reject held " heldKey)
}
