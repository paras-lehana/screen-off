#Requires AutoHotkey v2.0
; Recovery precedes locking; callbacks allow checks without real device writes.
class WakeLockGate {
    __New(enabled, recover, requestLock, reportFailure, complete, restoreTimeoutMs := 6000) {
        this.enabled := enabled
        this.restoreTimeoutMs := restoreTimeoutMs
        this.recover := recover
        this.requestLock := requestLock
        this.reportFailure := reportFailure
        this.complete := complete
        this.pending := false
        this.phase := "idle"
        this.displayOn := false
    }
    Request(now := 0) {
        if this.pending
            return
        this.pending := true
        this.phase := "restoring"
        this.started := now
        this.displayOn := false
        try this.recover.Call()
        catch Error as err {
            this.Fail("Recovery reported: " err.Message ". Automatic lock skipped.")
            return
        }
        if !this.enabled
            this.Finish()
    }
    ObserveDisplay(state) {
        if this.pending && this.phase = "restoring"
            this.displayOn := state=1 ; Most recent state; a later off/dim cancels confirmation.
    }
    Poll(now, rgbStatus) {
        if !this.pending
            return
        if this.phase = "restoring" {
            if SubStr(rgbStatus,1,6) = "ERROR|" {
                this.Fail("Input released; automatic lock skipped because lighting restoration failed: " SubStr(rgbStatus,7))
                return
            }
            if this.displayOn && rgbStatus = "restored" {
                this.phase := "locking"
                this.started := now
                try {
                    if !this.requestLock.Call()
                        throw Error("Windows did not accept the lock request.")
                } catch Error as err {
                    this.Fail("Recovery completed; Windows remains unlocked: " err.Message)
                }
            } else if now-this.started >= this.restoreTimeoutMs {
                this.Fail("Input released and wake requested; automatic lock skipped: "
                    . (!this.displayOn ? "no fresh Windows display-on confirmation. " : "")
                    . (rgbStatus != "restored" ? "Lighting restoration is still pending." : ""))
            }
        } else if now-this.started >= 8000 {
            this.Fail("Recovery completed, but Windows lock confirmation did not arrive. Use Win+L to lock manually.")
        }
    }
    Confirm() {
        if this.pending
            this.Finish()
    }
    Finish() {
        this.pending := false
        this.phase := "idle"
        this.complete.Call()
    }
    Fail(message) {
        this.Finish()
        this.reportFailure.Call(message)
    }
}
