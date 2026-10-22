# Device support

What has actually been seen working on real hardware, and what is only implemented.
**Please add your devices** with a [device report](https://github.com/paras-lehana/screen-off/issues/new?template=device-report.yml);
confirmed reports are added here with your hardware, versions and the Screen Off version.

Status key:
- **Verified** — a person watched it work on the hardware listed.
- **Partial** — works with a stated limitation.
- **Implemented** — code and offline tests exist; not yet confirmed on hardware.
- **Not supported** — known not to work, with the reason.

## Monitors (Windows display standby)

| Monitor | Connection | Status | Notes |
|---|---|---|---|
| Samsung Odyssey G7 32" (LC32G7xT / C32G75T) | DisplayPort 1.4, 2560x1440 240 Hz | **Verified** (v1.9–1.10) | Sleeps and wakes with both monitors. It reconnects on DisplayPort after each wake, which Screen Off checks. **Never send it DDC power-off (VCP D6 04/05)**: it stays off and unreachable over DisplayPort; see [recovery](recovery/README.md). |
| Samsung C27JG5x (C27JG50) | DisplayPort 1.2 / HDMI | **Verified** (v1.9) | |
| Any monitor that sleeps when the signal stops | any | Expected | Screen Off only uses Windows standby, the same as Windows' own display timeout. |

## Lighting

| Device | System | Status | Notes |
|---|---|---|---|
| ASUS motherboard, ASUS GPU, desktop strips | ASUS Aura, *profile* method (Armoury Crate) | **Verified** (v1.8–1.10) | All dark during standby and the configured effect returns on wake. Devices must be in Armoury Crate's *Sync devices*. |
| RAM synced in Armoury Crate | ASUS Aura, *profile* method | **Verified** (v1.8) | Previously excluded "Desktop" sync entry had to be included. |
| Same devices | ASUS Aura, *SDK* method | **Partial** | GPU and strips went dark; RAM stayed lit in testing. |
| Armoury Crate window | ASUS Aura, *profile* method | **Implemented** (v1.10) | Covers hide it while turning off; it is closed after each change. Owner confirmation pending. |
| Third-party case fans on the ASUS ARGB header | ASUS Aura | **Partial** | A faint glow was seen with the SDK method; dark with the profile method when synced. |
| Corsair K100 RGB (USB PID 1BC5) | Corsair iCUE SDK 4.0.84 | **Implemented** (v1.11) | Needs the SDK enabled in iCUE and a local session. Exclusive lighting control, black every 2 s, released so iCUE restores its profile. Hardware result pending. |
| Other Corsair devices (mice, headsets, pads, coolers, RAM) | Corsair iCUE SDK | **Implemented** | Choose device types in Settings. iCUE's own mirrors of other brands' motherboards/GPUs are never requested. |
| Devices exposed by OpenRGB | OpenRGB SDK server | **Implemented** | Simulated protocol tests only. Corsair K100 support needs OpenRGB 1.0+ and iCUE closed. |
| Windows Dynamic Lighting devices | LampArray | **Implemented** | Needs the registered helper package and background priority. |
| Corsair K100 | Windows Dynamic Lighting | **Not supported** | Corsair is not in Microsoft's Dynamic Lighting device list. |

## Software versions seen

Windows 11, AutoHotkey 2.0.30, Armoury Crate (Microsoft Store, 2026), iCUE 4.33.138,
NVIDIA RTX 3080 driver 32.0.16.1742.

## Adding a new lighting system

See [CONTRIBUTING.md](CONTRIBUTING.md#adding-a-lighting-system). A system needs a worker that
writes `APPLIED|`, `RESTORED|` or `ERROR|` status files and exits after restoring.
