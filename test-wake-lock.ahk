#Requires AutoHotkey v2.0
#Warn All, StdOut
#Include WakeLock.ahk
; No real lock, RGB, display or input calls.
class WakeTrace {
    events := ""
    accepted := true
    Recover() => this.events .= "recover,"
    Lock() {
        this.events .= "lock,"
        return this.accepted
    }
    Fail(message) => this.events .= "error,"
    Done() => this.events .= "done,"
    Gate(enabled := true, timeoutMs := 6000) => WakeLockGate(enabled, ObjBindMethod(this,"Recover"),
        ObjBindMethod(this,"Lock"), ObjBindMethod(this,"Fail"), ObjBindMethod(this,"Done"), timeoutMs)
}
Check(condition, label) {
    if !condition
        throw Error(label)
}
try {
    trace := WakeTrace(), gate := trace.Gate()
    gate.Request(100)
    Check(trace.events="recover,", "Recovery must precede any lock request")
    gate.Request(101)
    Check(trace.events="recover,", "Duplicate wake ignored")
    gate.Poll(200,"restored")
    Check(trace.events="recover,", "Old display state must not count as fresh confirmation")
    gate.ObserveDisplay(1), gate.Poll(300,"pending")
    Check(trace.events="recover,", "Wait for lighting worker release")
    gate.ObserveDisplay(0), gate.Poll(350,"restored")
    Check(trace.events="recover,", "A later display-off event invalidates earlier on confirmation")
    gate.ObserveDisplay(2), gate.Poll(375,"restored")
    Check(trace.events="recover,", "Dim is not display-on confirmation")
    gate.ObserveDisplay(1)
    gate.Poll(400,"restored")
    Check(trace.events="recover,lock,", "Lock only after both recovery signals")
    gate.Confirm(), gate.Confirm()
    Check(trace.events="recover,lock,done," && !gate.pending, "Confirm completes once")
    trace := WakeTrace(), gate := trace.Gate()
    gate.Request(100), gate.Poll(6100,"restored")
    Check(trace.events="recover,done,error," && !gate.pending, "No display event: skip lock, recovery stays released")
    trace := WakeTrace(), gate := trace.Gate()
    gate.Request(100), gate.ObserveDisplay(1), gate.Poll(6100,"pending")
    Check(trace.events="recover,done,error,", "Stalled RGB cannot trap input or cause a lock")
    trace := WakeTrace(), gate := trace.Gate()
    gate.Request(100), gate.ObserveDisplay(1), gate.Poll(200,"ERROR|release failed")
    Check(trace.events="recover,done,error,", "RGB error skips lock")
    trace := WakeTrace(), gate := trace.Gate()
    trace.accepted := false
    gate.Request(100), gate.ObserveDisplay(1), gate.Poll(200,"restored")
    Check(trace.events="recover,lock,done,error,", "Rejected lock never repeats recovery or blocks input")
    trace := WakeTrace(), gate := trace.Gate()
    gate.Request(100), gate.ObserveDisplay(1), gate.Poll(200,"restored"), gate.Poll(8200,"restored")
    Check(trace.events="recover,lock,done,error,", "Missing lock notification has bounded timeout")
    trace := WakeTrace(), gate := trace.Gate(false)
    gate.Request(100)
    Check(trace.events="recover,done,", "Lock opt-out restores directly")
    ; Armoury Crate cold start on wake: a longer lighting allowance still ends.
    trace := WakeTrace(), gate := trace.Gate(true, 15000)
    gate.Request(100), gate.ObserveDisplay(1), gate.Poll(6100,"pending")
    Check(trace.events="recover,", "Longer lighting allowance must not fail at 6 s")
    gate.Poll(15100,"pending")
    Check(trace.events="recover,done,error," && !gate.pending, "Longer lighting allowance still has a bound")
    FileAppend("PASS 16 recovery-before-lock checks; no hardware/session/input calls.`n", "*")
} catch Error as testError {
    FileAppend("FAIL " testError.Message "`n", "**")
    ExitApp(1)
}
