#Requires AutoHotkey v2.0
; One worker process per lighting system. A controller never silently falls back to a
; different system; LightingSet runs the systems the owner switched on, side by side.
class LightingController {
    ; kind: aura | corsair | openrgb | dynamic
    __New(kind, cfg) {
        this.kind := kind
        this.cfg := cfg
        this.label := Map("aura","ASUS Aura","corsair","Corsair iCUE","openrgb","OpenRGB","dynamic","Dynamic Lighting")[kind]
        this.workerPid := 0
        this.prefix := ""
    }
    Darken(isCancelled := 0) {
        if IsObject(isCancelled)
            CheckPreparationCancellation(isCancelled)
        if this.workerPid && ProcessExist(this.workerPid)
            throw Error("The previous " this.label " worker is still restoring. Try again shortly.")
        if this.HasOwnProp("restoreRequested")
            this.DeleteProp("restoreRequested")
        DirCreate(A_ScriptDir "\logs")
        this.prefix := A_ScriptDir "\logs\rgb-" this.kind "-" ProcessExist() "-" A_TickCount
        shell := '"' A_WinDir '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -Mta -ExecutionPolicy Bypass -File "'
        common := ' -ParentId ' ProcessExist() ' -StatePrefix "' this.prefix '"'
        switch this.kind {
            case "aura":
                if this.cfg.auraMethod="profile"
                    command := shell A_ScriptDir '\AuraProfileWorker.ps1"' common
                        . ' -WakeEffect ' this.cfg.auraWake ' -RestorePrevious ' (this.cfg.auraPrevious ? 1 : 0)
                else
                    command := shell A_ScriptDir '\AuraWorker.ps1"' common ' -AuraEnabled 1 -CorsairEnabled 0'
            case "corsair":
                command := shell A_ScriptDir '\CorsairWorker.ps1"' common ' -Devices "' this.cfg.corsairDevices '"'
            default:
                helper := A_ScriptDir "\LightingHost\publish\ScreenOff.LightingHost.exe"
                if !FileExist(helper)
                    throw Error("Lighting helper is missing. Run Build-LightingHost.ps1 first.")
                command := '"' helper '" --backend ' this.kind ' --parent ' ProcessExist()
                    . ' --state "' this.prefix '" --port ' this.cfg.port
        }
        pid := 0
        Run(command, A_ScriptDir, "Hide", &pid)
        this.workerPid := pid
        deadline := A_TickCount+20000
        Loop {
            if IsObject(isCancelled) && isCancelled.Call() {
                this.Restore()
                CheckPreparationCancellation(isCancelled)
            }
            status := this.ReadStatus()
            if SubStr(status,1,8) = "APPLIED|" {
                Log(this.label " black submitted; physical result unverified: " SubStr(status,9))
                return
            }
            if SubStr(status,1,6) = "ERROR|" || !ProcessExist(pid) {
                this.Restore()
                throw Error(status != "" ? SubStr(status,7) : "worker exited")
            }
            if A_TickCount >= deadline {
                this.Restore()
                throw Error("preparation exceeded 20 seconds")
            }
            Sleep(50)
        }
    }
    ReadStatus() {
        status := ""
        try status := FileRead(this.prefix ".status", "UTF-8")
        return status
    }
    Restore() {
        if this.prefix != "" && !FileExist(this.prefix ".stop") {
            FileAppend("release", this.prefix ".stop", "UTF-8")
            this.restoreRequested := A_TickCount
        }
    }
    RestoreStatus() {
        if !this.workerPid
            return "restored"
        status := this.ReadStatus()
        ; Dynamic Lighting releases remaining WinRT ownership at process exit.
        if ProcessExist(this.workerPid) {
            ; A vendor call that never returns must not keep devices dark: ending the
            ; process makes the vendor service drop its control and restore lighting.
            if this.HasOwnProp("restoreRequested") && A_TickCount-this.restoreRequested > 12000 {
                ProcessClose(this.workerPid)
                return "ERROR|" this.label " worker did not release within 12 s and was ended; its service restores lighting."
            }
            return "pending"
        }
        if SubStr(status,1,9) = "RESTORED|"
            return "restored"
        return SubStr(status,1,6) = "ERROR|" ? status : "ERROR|" this.label " worker exited without restoration confirmation."
    }
    CheckHealth() {
        if !this.workerPid
            return ""
        status := this.ReadStatus()
        if SubStr(status,1,6) = "ERROR|" || !ProcessExist(this.workerPid)
            return this.label ": " (status != "" ? status : "worker stopped")
        return ""
    }
}

; The lighting systems switched on in settings. A system that cannot be controlled is
; skipped and reported after wake; screen-off is cancelled only when every system fails.
class LightingSet {
    __New(cfg) {
        this.cfg := cfg
        this.controllers := []
        for kind in ["aura","corsair","openrgb","dynamic"]
            if cfg.%kind%
                this.controllers.Push(LightingController(kind, cfg))
        this.active := []
        this.skipped := []
    }
    Describe() => ScreenOffConfig.Describe(this.cfg)
    ; A running worker blocks reconfiguration until it has released its devices.
    workerPid {
        get {
            for controller in this.controllers
                if controller.workerPid && ProcessExist(controller.workerPid)
                    return controller.workerPid
            return 0
        }
    }
    Darken(isCancelled := 0) {
        this.active := [], this.skipped := []
        for controller in this.controllers {
            try {
                controller.Darken(isCancelled)
                this.active.Push(controller)
            } catch PreparationCancelled as err {
                this.Restore()
                throw err
            } catch Error as err {
                this.skipped.Push(controller.label ": " err.Message)
                Log("Lighting skipped - " controller.label ": " err.Message)
            }
        }
        if this.controllers.Length && !this.active.Length
            throw Error("No lighting system could be controlled. " this.SkippedText())
    }
    SkippedText() {
        text := ""
        for item in this.skipped
            text .= (text = "" ? "" : "`n") item
        return text
    }
    Restore() {
        for controller in this.controllers
            controller.Restore()
    }
    RestoreStatus() {
        result := "restored"
        for controller in this.active {
            status := controller.RestoreStatus()
            if status = "pending"
                return "pending"
            if status != "restored"
                result := status
        }
        return result
    }
    CheckHealth() {
        for controller in this.active
            if problem := controller.CheckHealth()
                return problem
        return ""
    }
}
