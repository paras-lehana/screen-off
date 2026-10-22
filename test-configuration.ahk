#Requires AutoHotkey v2.0
#Warn All, StdOut
#Include InputRelease.ahk
#Include Configuration.ahk
; Pure configuration checks. The only file written is a temporary legacy-ini sample.
Check(ok,label) {
    global checks
    if !ok
        throw Error(label)
    checks += 1
}
Rejects(c,args) {
    try ScreenOffConfig.Override(c,args)
    catch
        return true
    return false
}
Base() => {aura:true,corsair:false,openrgb:false,dynamic:false,corsairDevices:"keyboard",
    port:6742,lock:true,off:"^!F12",wake:"Space"}
checks := 0
try {
    ; Older single-backend selection still maps to exactly one lighting system.
    for backend in ["aura","openrgb","dynamic","none"] {
        c := ScreenOffConfig.Override(Base(),["--backend=" backend])
        Check(c.aura=(backend="aura") && c.openrgb=(backend="openrgb") && c.dynamic=(backend="dynamic"),"Legacy backend " backend)
    }
    c := ScreenOffConfig.Override(Base(),["--openrgb-port=6743","--lock-on-wake=0"])
    Check(c.port=6743 && !c.lock,"CLI typed overrides")
    for testArg in ["--backend=unknown","--openrgb-port=0","--openrgb-port=65536","--lock-on-wake=yes","--unknown=1","--corsair=2"]
        Check(Rejects(Base(),[testArg]),"Invalid CLI input must fail: " testArg)
    ; Independent switches: Aura and Corsair own different devices and may run together.
    c := ScreenOffConfig.Override(Base(),["--aura-method=profile","--corsair=1","--corsair-devices=keyboard,mouse"])
    Check(c.aura && c.corsair && c.corsairDevices="keyboard,mouse","Aura profile plus Corsair allowed")
    Check(ScreenOffConfig.Describe(c)="Aura (profile) + Corsair (keyboard,mouse)","Describe lists enabled systems")
    c := ScreenOffConfig.Override(Base(),["--aura=0"])
    Check(ScreenOffConfig.Describe(c)="none (display only)","Display-only description")
    ; OpenRGB and Dynamic Lighting reach the same LEDs as the vendor apps: run alone.
    for combo in [["--openrgb=1"],["--openrgb=1","--aura=0","--corsair=1"],["--dynamic=1"],["--dynamic=1","--aura=0","--corsair=1"],["--dynamic=1","--aura=0","--openrgb=1"]]
        Check(Rejects(Base(),combo),"Overlapping controllers must fail")
    Check(!Rejects(Base(),["--aura=0","--openrgb=1"]),"OpenRGB alone allowed")
    Check(!Rejects(Base(),["--aura=0","--dynamic=1"]),"Dynamic Lighting alone allowed")
    Check(Rejects(Base(),["--corsair=1","--corsair-devices=toaster"]),"Unknown Corsair device type must fail")
    Check(Rejects(Base(),["--corsair=1","--corsair-devices="]),"Corsair with no device types must fail")
    c := ScreenOffConfig.Override(Base(),["--aura-method=profile","--aura-wake-effect=breathing","--notice-seconds=30","--aura-restore-previous=1"])
    Check(c.auraMethod="profile" && c.auraWake="breathing" && c.noticeMs=30000 && c.auraPrevious,"Aura/notice CLI overrides")
    for testArg in ["--aura-method=unknown","--aura-wake-effect=unknown","--notice-seconds=0","--notice-seconds=121","--notice-seconds=3.5","--aura-restore-previous=yes"]
        Check(Rejects(Base(),[testArg]),"Invalid Aura/notice option must fail: " testArg)
    ; A 1.10 settings file keeps its meaning after the upgrade.
    sample := A_Temp "\screen-off-legacy-" A_TickCount ".ini"
    FileAppend("[RGB]`nBackend=aura`nCorsairEnabled=1`n[Aura]`nMethod=profile`n", sample)
    c := ScreenOffConfig.Load(sample)
    FileDelete(sample)
    Check(c.aura && c.corsair && !c.openrgb && c.corsairDevices=ScreenOffDefaults.CorsairDevices,"Legacy ini maps to Aura + Corsair")
    FileAppend("PASS " checks " configuration checks; no settings/hardware writes.`n","*")
} catch Error as testError {
    FileAppend("FAIL " testError.Message "`n","**")
    ExitApp(1)
}
