# Changelog

## 1.11 — 22 October 2026
- Settings > Lighting: switch each lighting system on or off independently (ASUS Aura, Corsair
  iCUE, OpenRGB, Windows Dynamic Lighting) and choose which Corsair device types to control.
  Aura and Corsair run together; OpenRGB and Dynamic Lighting run alone.
- New Corsair worker using the official iCUE SDK: exclusive lighting control, black every 2 s,
  released on wake so iCUE restores its own profile. Clear messages when iCUE is closed, its SDK
  is off, or the session is locked or remote.
- A system that cannot be reached is skipped and reported after wake; the rest still go dark.
- "Check ticked systems" runs in the background and never changes colours.
- Workers that do not release within 12 s of wake are ended so vendor services restore lighting.
- Portable setup: AutoHotkey is found automatically, `Get-CorsairSdk.ps1` fetches and verifies the
  iCUE SDK, `Install-Startup.ps1` adds a sign-in shortcut, fresh installs start display-only.
- Settings window fits 1080p at 150% scaling.

## 1.10 — 21 October 2026
- Black covers go up before the lighting change, hiding Armoury Crate; it is closed after each
  change. Wake allows 15 s for lighting before skipping the automatic lock.

## 1.9 — 21 October 2026
- After wake, checks every monitor came back and shows a notice naming any that did not.
- `recovery/` tools for a Samsung Odyssey G7 left off by a DDC power command.

## 1.8 and earlier — 19 October 2026
- Windows display standby with input suppression, wake key, emergency exit, tray icon and
  settings, lock after recovery, and ASUS Aura via Armoury Crate's Dark effect.
- The original 1.0 used DDC/CI power-off; it was withdrawn after it left a monitor unreachable.
