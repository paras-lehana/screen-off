#Requires AutoHotkey v2.0

class PreparationCancelled extends Error {
}

; Stop the preparation when a lock cancelled it, or when a wake arrived while the lighting
; step was running (the screens are already off then). Before that step, busy-and-inactive
; is the normal state and must NOT count as cancelled (1.12 regression: every attempt aborted).
PreparationShouldStop(cancellationText, lightingBusy, active) {
    return cancellationText != "" || (lightingBusy && !active)
}

CheckPreparationCancellation(isCancelled) {
    if isCancelled.Call()
        throw PreparationCancelled("Screen-off preparation was cancelled.")
}

; Only lighting readiness gates standby. Notification lifetime is an independent
; GUI timer; there is deliberately no countdown, Sleep or deadline here.
WaitForLightingBeforeStandby(startLighting, checkHealth, isCancelled) {
    CheckPreparationCancellation(isCancelled)
    startLighting.Call(isCancelled)
    CheckPreparationCancellation(isCancelled)
    problem := checkHealth.Call()
    if problem != ""
        throw Error("Lighting stopped during preparation: " problem)
}
