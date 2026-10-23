#Requires AutoHotkey v2.0
#Warn All, StdOut
#Include StandbyPreparation.ahk
; Fake lighting/cancellation only. No display, RGB, input or GUI calls.
class PreparationTrace {
    events := ""
    cancelled := false
    cancelDuringStart := false
    startupFails := false
    unhealthy := false
    Darken(cancelled) {
        this.events .= "start,"
        if this.startupFails
            throw Error("SDK failed")
        if this.cancelDuringStart
            this.cancelled := true
    }
    Health() {
        this.events .= "health,"
        return this.unhealthy ? "worker exited" : ""
    }
    IsCancelled() => this.cancelled
    Run() => WaitForLightingBeforeStandby(ObjBindMethod(this,"Darken"),
        ObjBindMethod(this,"Health"), ObjBindMethod(this,"IsCancelled"))
}
Check(condition,label) {
    if !condition
        throw Error(label)
}
Fails(trace,expectedType,label) {
    failure := 0
    try trace.Run()
    catch Error as err
        failure := err
    Check(IsObject(failure) && failure is expectedType,label)
}
try {
    trace := PreparationTrace(), started := A_TickCount
    trace.Run()
    Check(trace.events="start,health,","Lighting preparation precedes health check")
    Check(A_TickCount-started<1000,"Notification lifetime must not become an activation delay")
    trace := PreparationTrace(), trace.cancelled := true
    Fails(trace,PreparationCancelled,"Pre-cancel must abort")
    Check(trace.events="","Pre-cancel must not touch lighting")
    trace := PreparationTrace(), trace.cancelDuringStart := true
    Fails(trace,PreparationCancelled,"Cancel during startup prevents standby")
    Check(trace.events="start,","Cancelled startup must not progress")
    trace := PreparationTrace(), trace.unhealthy := true
    Fails(trace,Error,"Worker error prevents standby")
    trace := PreparationTrace(), trace.startupFails := true
    Fails(trace,Error,"Startup error prevents standby")
    Check(trace.events="start,","Failed startup must not progress")
    ; Regression: busy but not yet active (normal start of an off request) is not a cancel.
    Check(!PreparationShouldStop("", false, false),"Start of an off request must not count as cancelled")
    Check(!PreparationShouldStop("", true, true),"Lighting step with screens off continues")
    Check(PreparationShouldStop("", true, false),"Wake during the lighting step stops it")
    Check(PreparationShouldStop("Windows locked", false, false),"A lock cancels preparation")
    FileAppend("PASS 13 preparation checks; readiness only, no notification delay or hardware calls.`n","*")
} catch Error as testError {
    FileAppend("FAIL " testError.Message "`n","**")
    ExitApp(1)
}
