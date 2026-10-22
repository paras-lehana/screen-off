#Requires AutoHotkey v2.0

class PreparationCancelled extends Error {
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
