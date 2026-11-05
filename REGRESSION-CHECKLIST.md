# Regression checklist

Every problem Screen Off has had gets a line here, with the check that proves it is still fixed. Run the
whole list after **any** change, not only the checks for the part you touched: most regressions so far
came from a change in one place breaking a timing or ordering assumption somewhere else.

How to use it:

1. Run `.\Test-ScreenOff.ps1` (automated rows, marked **A**). All must pass.
2. Restart the utility on the new version and do one real cycle at the PC with the physical rows (**P**).
   Watch the hardware; a log line alone is not a pass for a **P** row.
3. In the release notes, list every **P** row that was not run. Never report it as passed.
4. A new problem that reaches the owner gets a new row here in the same change that fixes it.

## Cycle to run (about 3 minutes)

1. Lights on, a maximized VS Code window on the second screen, Windows set to lock on wake.
2. Ctrl+Alt+F12, release. Wait 60 s. Move the mouse and press a few keys (not the wake key).
3. Space. Sign in. Wait 60 s.
4. Within 5 s of signing in, press Ctrl+Alt+F12 again. Wait 30 s. Space, sign in.

## Checks

| # | Problem it guards against | First fixed | Type | Check | Pass when |
|---|---|---|---|---|---|
| 1 | Off hotkey fired before the keys were released, or scanned every key | 1.4 | A | input-release tests | PASS 7 scenarios |
| 2 | Mouse or other keys woke the screens; anything except Esc cancelled | 1.4, 1.12 | A + P | preparation tests; cycle step 2 | screens stay dark until Space |
| 3 | ASUS lights stayed on during off (Armoury Crate cannot work in display standby) | 1.13 | P | cycle step 2 | motherboard, GPU, strips and RAM all dark |
| 4 | ASUS lights stayed dark after wake when Windows locked | 1.18 | P | cycle step 3 | effect is back within ~15 s of sign-in; log has `Restored lighting effect` |
| 5 | Armoury Crate window empty after a lock, restore failed | 1.19, 1.20 | P | after a lock longer than a few minutes | log has no `control unavailable`; lights back |
| 6 | Armoury Crate window visible on screen or left open | 1.10, 1.14, 1.15 | P | cycle steps 2-3 | no Armoury window seen; none open afterwards |
| 7 | Corsair keyboard stayed lit during off | 1.11 | P + log | cycle step 2 | keyboard dark; worker log `0 nonblack` |
| 8 | Corsair keyboard stayed dark after wake | 1.19 | P | cycle step 3 | keyboard shows the active iCUE profile. If that profile is itself a lights-off profile the keyboard stays dark, which is not a Screen Off fault |
| 9 | Off pressed right after a wake skipped the lights (both still restoring) | 1.21 | A + P | lighting-set test `Off waits for a restore that is still running`; cycle step 4 | lights go dark in step 4 too; log may show `Waited ... s for the previous` |
| 10 | Windows moved to the primary screen after wake (incl. maximized VS Code) | 1.13, 1.16 | A + P | window-layout tests; cycle step 3 | every window back on its own screen |
| 11 | A monitor did not come back after wake | 1.9 | P + log | cycle step 3 | log `Screens back after wake:` names both screens |
| 12 | Utility exited during monitor flapping and left the screens on | 1.17 | log | after any night | log has no `Exiting`/error exit between off and wake |
| 13 | Monitor left unreachable by a DDC power-off | 1.0 (withdrawn) | code review | search changes for VCP `D6` writes | only `D6=01` exists, in `recovery/` |
| 14 | Not running after a restart | 21 Oct | P | sign in after a reboot | tray icon present; log `Ready v` |
| 15 | A lighting app (iCUE, Armoury Crate) left open by the utility | 23 Oct | P | after the cycle | no iCUE or Armoury Crate window open |

## Known open items

- 6 Nov: after a wake with nothing switched off (the skipped case in row 9), the owner saw the ASUS lights go
  dark for a while. Screen Off sent no lighting command at that moment. The likely cause is Armoury Crate
  applying the effect change from 30 s earlier, but that is not proven. Watch for it during row 9.
