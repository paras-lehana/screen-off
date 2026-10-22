#Requires AutoHotkey v2.0
#Warn All, StdOut
#Include InputRelease.ahk
#Include StandbyPreparation.ahk
#Include Configuration.ahk
#Include Lighting.ahk
; LightingSet aggregation with fake controllers: no workers, LEDs, display or input.
Log(message) {
}
class FakeController {
    __New(label, darken := "ok", restore := "restored", health := "") {
        this.label := label, this.mode := darken, this.status := restore
        this.health := health, this.workerPid := 0, this.restored := false
    }
    Darken(isCancelled := 0) {
        if this.mode = "fail"
            throw Error("unreachable")
        if this.mode = "cancel"
            throw PreparationCancelled("cancelled")
    }
    Restore() => this.restored := true
    RestoreStatus() => this.status
    CheckHealth() => this.health
}
Check(ok, label) {
    global checks
    if !ok
        throw Error(label)
    checks += 1
}
SetOf(controllers*) {
    set := LightingSet({aura:false,corsair:false,openrgb:false,dynamic:false,corsairDevices:"keyboard",
        port:6742,auraMethod:"profile",auraWake:"breathing",auraPrevious:false})
    for controller in controllers
        set.controllers.Push(controller)
    return set
}
checks := 0
try {
    lights := SetOf()
    lights.Darken()
    Check(!lights.active.Length && lights.RestoreStatus()="restored" && lights.workerPid=0, "Display-only set is a no-op")
    lights := SetOf(FakeController("Aura"), FakeController("Corsair"))
    lights.Darken()
    Check(lights.active.Length=2 && !lights.skipped.Length, "Both systems darkened")
    lights := SetOf(FakeController("Aura"), FakeController("Corsair","fail","ERROR|x"))
    lights.Darken()
    Check(lights.active.Length=1 && InStr(lights.SkippedText(),"Corsair: unreachable"), "One failure is skipped and reported")
    Check(lights.RestoreStatus()="restored", "A skipped system does not block wake recovery")
    failed := false
    try SetOf(FakeController("Aura","fail"), FakeController("Corsair","fail")).Darken()
    catch Error as caught
        failed := InStr(caught.Message, "No lighting system")
    Check(failed, "All systems failing cancels screen-off")
    aura := FakeController("Aura"), corsair := FakeController("Corsair","cancel")
    cancelled := false
    try SetOf(aura, corsair).Darken()
    catch PreparationCancelled
        cancelled := true
    Check(cancelled && aura.restored && corsair.restored, "Cancellation restores every system and propagates")
    lights := SetOf(FakeController("Aura","ok","pending"), FakeController("Corsair","ok","ERROR|release"))
    lights.Darken()
    Check(lights.RestoreStatus()="pending", "Any pending worker keeps recovery waiting")
    lights.active[1].status := "restored"
    Check(lights.RestoreStatus()="ERROR|release", "A release error is reported")
    lights := SetOf(FakeController("Aura","ok","restored","Aura: worker stopped"), FakeController("Corsair"))
    lights.Darken()
    Check(lights.CheckHealth()="Aura: worker stopped", "Health reports the first active problem")
    FileAppend("PASS " checks " lighting-set checks; fake controllers only.`n", "*")
} catch Error as testError {
    FileAppend("FAIL " testError.Message "`n", "**")
    ExitApp(1)
}
