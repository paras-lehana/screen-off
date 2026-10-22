#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, StdOut
#Include InputRelease.ahk
#Include Configuration.ahk
; Changes configuration only; it never activates standby or a lighting worker.
DetectHiddenWindows(true)
path := A_ScriptDir "\settings.ini"
try {
    if A_Args.Length=1 && A_Args[1]="--status" {
        cliConfig := ScreenOffConfig.Load(path)
        FileAppend("Saved lighting=" ScreenOffConfig.Describe(cliConfig) "; Aura wake-effect=" cliConfig.auraWake
            . "; restore-previous=" cliConfig.auraPrevious "; notice-seconds=" cliConfig.noticeMs//1000
            . "; lock-on-wake=" cliConfig.lock "; OpenRGB port=" cliConfig.port "`n","*")
        ExitApp(0)
    }
    cliConfig := ScreenOffConfig.Override(ScreenOffConfig.Load(path),A_Args)
    resident := WinExist(A_ScriptDir "\ScreenOffWindows.ahk ahk_class AutoHotkey")
    if resident && SendMessage(0x8020,0,0,,"ahk_id " resident, , , ,2000)!=1
        throw Error("Screen Off is active or restoring; configuration was not changed.")
    previous := FileRead(path)
    try {
        ScreenOffConfig.Save(path,cliConfig)
        if resident && SendMessage(0x8020,1,0,,"ahk_id " resident, , , ,2000)!=1
            throw Error("The running utility could not apply settings. Previous configuration restored.")
    } catch Error as err {
        FileDelete(path)
        FileAppend(previous,path)
        throw err
    }
    FileAppend("Configured lighting=" ScreenOffConfig.Describe(cliConfig) "; lock-on-wake=" cliConfig.lock ". No lighting/display writes.`n","*")
} catch Error as configError {
    FileAppend(configError.Message "`n","**")
    ExitApp(1)
}
