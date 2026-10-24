# Changelog

## 1.15 — 24 October 2026
- Waking no longer waits for the lighting restore. The restore is fired first and runs in the
  background; the screens come back as soon as no lighting app window can show (normally under a
  second). The Armoury Crate window is moved far off-screen the moment it exists and closed at the
  end of the restore. A problem found afterwards is reported in a notice and the tray.
- Windows locks as soon as the screens are back, instead of after the lighting finished.
- Turning off is unchanged: covers and the input block make the screens look off at once, the
  lighting work happens behind them, and real display standby follows (Armoury Crate cannot work
  during standby).
- Live test: window parked at -32000,-32000 from 38 ms after it appears; restore 2.1 s, window closed.

## 1.14 — 24 October 2026
- Fixed: after a long sleep the ASUS lights were never restored and Armoury Crate stayed open. The
  worker closed Armoury Crate right after selecting Dark; relaunching it from cold took ~11 s (its
  navigation alone needs ~6 s) and the 12 s limit ended the restore mid-way, leaving Dark selected.
- Armoury Crate is now left open (hidden behind the covers) after Dark and closed as the last step of
  the restore. Cold-start allowances are generous (window 40 s, supervisor 60 s, screens wait up to
  65 s) and every step is logged. New `-RestoreOnly` worker mode restores the effect on its own.

## 1.13 — 23 October 2026
- Fixed: ASUS lighting stayed on in 1.12. Armoury Crate builds no UI while displays are in standby,
  so the Dark effect could not be selected and its launch woke the displays (grey flash, monitor
  source banner). Now black covers go up at once (the screens look off), lighting and apps are
  handled behind them with the display still powered, and only then does real standby start. On
  wake the display powers up behind the covers, lighting is restored, then the covers lift.
- New: window positions are saved before standby and put back after the screens return (and again
  after sign-in). DisplayPort monitors disconnect while asleep and Windows moves their windows to
  the remaining screen. Only moved windows are touched; maximized windows return maximized.
- If every lighting system fails, the screens still go off; the problem is reported after wake.

## 1.12 â€” 23 October 2026
- Turning off now starts with the screens (covers, input block, Windows standby); lighting and its
  apps are switched off afterwards, out of sight. Pressing the wake key during that step stops it.
- Waking now restores lighting and closes the apps while the screens are still dark; the screens
  come back only afterwards. A lighting system interrupted mid-switch is still waited for.
- The notice has no Cancel button; **Esc is the only cancel**. It works until the lights have finished
  switching off, restoring lights then screens without locking. The wake key is a plain wake.
- Emergency exit and shutdown finish the same sequence synchronously.

## 1.11 â€” 22 October 2026
- Corsair SDK version fix (23 Oct): iCUE 4.33 speaks SDK protocol 4.0.12 and rejected the 4.0.84
  client ("handshake failed", shown as state 4). The worker now uses SDK 4.0.48 with iCUE 4 and
  4.0.84 with iCUE 5; `Get-CorsairSdk.ps1` fetches both. K100 verified on hardware.
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

## 1.10 â€” 21 October 2026
- Black covers go up before the lighting change, hiding Armoury Crate; it is closed after each
  change. Wake allows 15 s for lighting before skipping the automatic lock.

## 1.9 â€” 21 October 2026
- After wake, checks every monitor came back and shows a notice naming any that did not.
- `recovery/` tools for a Samsung Odyssey G7 left off by a DDC power command.

## 1.8 and earlier â€” 19 October 2026
- Windows display standby with input suppression, wake key, emergency exit, tray icon and
  settings, lock after recovery, and ASUS Aura via Armoury Crate's Dark effect.
- The original 1.0 used DDC/CI power-off; it was withdrawn after it left a monitor unreachable.
