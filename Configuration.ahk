#Requires AutoHotkey v2.0
; Editable defaults for notification lifetime and Aura behavior. The notification
; timer never delays activation. Existing installations keep SDK until configured.
class ScreenOffDefaults {
    static NoticeMs := 30000
    static AuraMethod := "sdk"
    static AuraWakeEffect := "breathing"
    static AuraRestorePrevious := false
    ; Corsair device types controlled when Corsair is on. Motherboard/GPU/RAM entries that
    ; iCUE mirrors from other vendors are excluded so Aura stays their only owner.
    static CorsairDevices := "keyboard,mouse,mousemat,headset,headsetstand"
}
CORSAIR_DEVICE_TYPES := ["keyboard","mouse","mousemat","headset","headsetstand","cooler","fancontroller","ledcontroller","memory","gamecontroller"]

; Shared validation/persistence for the resident UI and command-line configurator.
; Each lighting system is switched on or off independently ("what to control").
class ScreenOffConfig {
    static Load(path) {
        ; Version 1.10 and earlier stored one primary backend plus a K100 flag. A fresh
        ; install has neither and starts display-only until systems are ticked.
        legacy := StrLower(IniRead(path,"RGB","Backend",
            IniRead(path,"RGB","Enabled","0")="1" ? "aura" : "none"))
        legacyCorsair := IniRead(path,"RGB","CorsairEnabled","0")
        cfg := {aura: IniRead(path,"Lighting","Aura",legacy="aura" ? 1 : 0)="1",
            corsair: IniRead(path,"Lighting","Corsair",legacyCorsair)="1",
            corsairDevices: StrLower(IniRead(path,"Lighting","CorsairDevices",ScreenOffDefaults.CorsairDevices)),
            openrgb: IniRead(path,"Lighting","OpenRGB",legacy="openrgb" ? 1 : 0)="1",
            dynamic: IniRead(path,"Lighting","DynamicLighting",legacy="dynamic" ? 1 : 0)="1",
            port: IniRead(path,"OpenRGB","Port","6742"),
            lock: IniRead(path,"Security","LockOnWake","1")="1",
            off: IniRead(path,"Keys","OffHotkey","^!F12"),
            wake: IniRead(path,"Keys","WakeKey","Space"),
            noticeMs: IniRead(path,"UI","NoticeSeconds",ScreenOffDefaults.NoticeMs//1000)*1000,
            auraMethod: IniRead(path,"Aura","Method",ScreenOffDefaults.AuraMethod),
            auraWake: IniRead(path,"Aura","WakeEffect",ScreenOffDefaults.AuraWakeEffect),
            auraPrevious: IniRead(path,"Aura","RestorePrevious",ScreenOffDefaults.AuraRestorePrevious ? 1 : 0)="1"}
        this.Validate(cfg)
        return cfg
    }
    static Validate(cfg) {
        ; Backward-compatible defaults for callers built before these options.
        for name, value in Map("noticeMs",ScreenOffDefaults.NoticeMs,"auraMethod",ScreenOffDefaults.AuraMethod,
            "auraWake",ScreenOffDefaults.AuraWakeEffect,"auraPrevious",ScreenOffDefaults.AuraRestorePrevious,
            "aura",false,"corsair",false,"openrgb",false,"dynamic",false,"corsairDevices",ScreenOffDefaults.CorsairDevices)
            if !cfg.HasOwnProp(name)
                cfg.%name% := value
        if !RegExMatch(cfg.auraMethod,"^(sdk|profile)$")
            throw Error("Aura method must be sdk or profile.")
        if !RegExMatch(cfg.auraWake,"^(breathing|rainbow|colorcycle|static|dark)$")
            throw Error("Choose a supported Aura wake effect.")
        if !IsInteger(cfg.noticeMs) || cfg.noticeMs<1000 || cfg.noticeMs>120000 || Mod(cfg.noticeMs,1000)
            throw Error("Notification duration must be 1 to 120 whole seconds.")
        if !RegExMatch(String(cfg.port),"^\d{1,5}$") || cfg.port<1 || cfg.port>65535
            throw Error("OpenRGB port must be between 1 and 65535.")
        ; OpenRGB and Dynamic Lighting reach the same devices as the vendor apps, so two
        ; controllers would fight over one LED. They therefore run alone.
        if cfg.openrgb && (cfg.aura || cfg.corsair || cfg.dynamic)
            throw Error("OpenRGB controls ASUS and Corsair devices itself. Turn off Aura, Corsair and Dynamic Lighting to use it.")
        if cfg.dynamic && (cfg.aura || cfg.corsair)
            throw Error("Windows Dynamic Lighting can reach the same devices as Aura and iCUE. Use it on its own.")
        if cfg.corsair {
            if cfg.corsairDevices=""
                throw Error("Choose at least one Corsair device type, or turn Corsair off.")
            for deviceType in StrSplit(cfg.corsairDevices,",") {
                known := false
                for allowed in CORSAIR_DEVICE_TYPES
                    known := known || deviceType=allowed
                if !known
                    throw Error("Unknown Corsair device type: " deviceType)
            }
        }
        if !cfg.off || !GetKeyVK(cfg.wake)
            throw Error("Choose a shortcut and a valid single wake key.")
        if cfg.off="^!Escape" || cfg.off="^!Esc"
            throw Error("Ctrl+Alt+Esc is reserved for restore and exit.")
        ReleaseKeys(cfg.off,cfg.wake)
    }
    static Save(path,cfg) {
        this.Validate(cfg)
        IniWrite(cfg.aura ? 1 : 0,path,"Lighting","Aura")
        IniWrite(cfg.corsair ? 1 : 0,path,"Lighting","Corsair")
        IniWrite(cfg.corsairDevices,path,"Lighting","CorsairDevices")
        IniWrite(cfg.openrgb ? 1 : 0,path,"Lighting","OpenRGB")
        IniWrite(cfg.dynamic ? 1 : 0,path,"Lighting","DynamicLighting")
        ; Superseded keys stay readable by older versions but are no longer the source of truth.
        try IniDelete(path,"RGB")
        IniWrite(cfg.port,path,"OpenRGB","Port")
        IniWrite(cfg.lock ? 1 : 0,path,"Security","LockOnWake")
        IniWrite(cfg.off,path,"Keys","OffHotkey")
        IniWrite(cfg.wake,path,"Keys","WakeKey")
        IniWrite(cfg.noticeMs//1000,path,"UI","NoticeSeconds")
        IniWrite(cfg.auraMethod,path,"Aura","Method")
        IniWrite(cfg.auraWake,path,"Aura","WakeEffect")
        IniWrite(cfg.auraPrevious ? 1 : 0,path,"Aura","RestorePrevious")
    }
    ; Short human-readable list of the lighting systems this configuration controls.
    static Describe(cfg) {
        parts := []
        if cfg.aura
            parts.Push("Aura (" cfg.auraMethod ")")
        if cfg.corsair
            parts.Push("Corsair (" cfg.corsairDevices ")")
        if cfg.openrgb
            parts.Push("OpenRGB :" cfg.port)
        if cfg.dynamic
            parts.Push("Dynamic Lighting")
        text := ""
        for part in parts
            text .= (text = "" ? "" : " + ") part
        return text = "" ? "none (display only)" : text
    }
    static Override(cfg,args) {
        for arg in args {
            if !RegExMatch(arg,"^--([^=]+)=(.*)$",&match)
                throw Error("Expected --name=value; received " arg)
            name := match[1], value := match[2]
            switch name {
                case "backend":
                    ; Older single-controller selection: switch to exactly that system.
                    value := StrLower(value)
                    if !RegExMatch(value,"^(aura|openrgb|dynamic|none)$")
                        throw Error("Lighting backend must be aura, openrgb, dynamic or none.")
                    cfg.aura := value="aura", cfg.openrgb := value="openrgb", cfg.dynamic := value="dynamic"
                    if value!="aura" && value!="none"
                        cfg.corsair := false
                case "openrgb-port": cfg.port := value
                case "aura-method": cfg.auraMethod := StrLower(value)
                case "aura-wake-effect": cfg.auraWake := StrLower(value)
                case "corsair-devices": cfg.corsairDevices := StrLower(StrReplace(value," ",""))
                case "notice-seconds":
                    if !RegExMatch(value,"^\d+$")
                        throw Error("Notice seconds must be a whole number.")
                    cfg.noticeMs := Integer(value)*1000
                case "lock-on-wake", "corsair", "aura", "openrgb", "dynamic", "aura-restore-previous":
                    if value!="0" && value!="1"
                        throw Error(name " must be 0 or 1.")
                    switch name {
                        case "lock-on-wake": cfg.lock := value="1"
                        case "aura-restore-previous": cfg.auraPrevious := value="1"
                        default: cfg.%name% := value="1"
                    }
                default: throw Error("Unknown option: " name)
            }
        }
        this.Validate(cfg)
        return cfg
    }
}
