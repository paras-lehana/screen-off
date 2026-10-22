# Odyssey G7 recovery

Use this if a Samsung Odyssey G7 (LC32G7xT) shows no picture, no menu and no source banner while its
blue LED stays on, especially after a DDC/CI power command. This happened to the maintainer's monitor
on 19 October 2026 and was recovered on 20 October with the steps below. Other Samsung models may
behave similarly; please report results in an issue.

## What is going on

- A DDC/CI "off" (VCP D6 = 04 or 05) is a soft power-off. The monitor keeps it through mains loss:
  the ring flashes at boot, then it returns to off. The blue LED means off/standby.
- The normal way back is the JOG centre press, which is faulty on this unit.
- While off it drops DisplayPort hot-plug, so nothing can reach it over DP. Its HDMI identity
  stays readable, and HDMI is where a power-on can be delivered.
- If the monitor input (DP IN 1/2) does not match the cable, the PC loses the monitor the same
  way. ControlMyMonitor's "Primary" then means the other screen.

## Steps

1. Run `qwinsta`. If the active session is `rdp-tcp#…`, Windows' monitor API cannot see physical
   screens; `Odyssey-NvWake.ps1` still works. Chrome Remote Desktop keeps the console session.
2. Connect the Odyssey's HDMI input to the graphics card (borrow the C27's cable for a minute).
3. `.\Odyssey-NvWake.ps1 -Mode Probe` must list `identity=SAM705A TARGET`. Probe sends nothing.
4. `.\Odyssey-NvWake.ps1 -Mode Wake` sends one power-on. Use `-Mode Burst -Seconds 120` while
   replugging the monitor's power if a single write is not acknowledged.
5. Wrong input after recovery: `.\Odyssey-NvWake.ps1 -Mode Input -Inputs 9` waits for HDMI and sends
   input 9, Samsung's set code for **DP IN 1** (21 Oct: banner showed DisplayPort 1). **Unplug HDMI from
   the Odyssey as soon as the screen switches**, otherwise it falls back to the HDMI picture. The
   advertised 0x0F was acknowledged but ignored; 0x10 (DP2 per the caps list) is untested.
6. Move HDMI back to the C27.

`Odyssey-HdmiWake.ps1` is the Windows-API version (Probe/Caps/Wake/Watch). On 20 Oct it was refused
while the monitor was off (0xC0262582); the NVIDIA version is the one that worked at 22:17:42.
Both scripts can only send power-on (D6 = 01) or input select (0x60); they cannot send off.
Every attempt is appended to `odyssey-recovery.log`.

## Never

Send D6 = 04 or 05 to this monitor. Screen Off uses Windows standby only, which the monitor
wakes from when the picture returns.
