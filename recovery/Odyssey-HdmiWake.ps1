# Odyssey G7 (LC32G7xT) recovery after the 19 October DDC D6=4 soft-off.
#
# Why HDMI: a soft-off Samsung drops DisplayPort hot-plug, so Windows/NVIDIA cannot
# reach DDC over DP AUX. HDMI DDC is plain I2C powered by the source, and Windows
# enumerated the Odyssey's HDMI identity SAM705A at 01:55:12 on 19 October while
# it stayed dark. Related report: https://github.com/microsoft/PowerToys/issues/50449
#
# Modes:
#   -Mode Probe  (default) Windows identity only; sends NO DDC traffic.
#   -Mode Caps   one read-only DDC capabilities-length request to the Odyssey.
#   -Mode Wake   one VCP 0xD6 = 0x01 (On) write to the Odyssey. No retries.
#   -Mode Watch  wait (silently, up to -Minutes) for the Odyssey to join the desktop,
#                confirm it is still there after 5 s, then perform Wake once.
#   -Mode Burst  for up to -Minutes, repeat D6=01 every 250 ms whenever the Odyssey is
#                a desktop target; stop at the first acknowledged write. Covers the
#                boot window after mains reconnect (20 Oct: off-state writes NACKed
#                with 0xC0262582 while EDID stayed readable).
# The power value is a constant: this script can never send Off (0x04/0x05).
param([ValidateSet('Probe', 'Caps', 'Wake', 'Watch', 'Burst')][string]$Mode = 'Probe', [int]$Minutes = 15)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $PSScriptRoot 'odyssey-recovery.log'
function Write-Log([string]$text) {
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Mode, $text
    Add-Content -Path $logPath -Value $line -Encoding utf8
    Write-Output $line
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class OdysseyDdc {
    const byte PowerModeCode = 0xD6;
    const uint PowerOn = 0x01;
    const uint EDD_GET_DEVICE_INTERFACE_NAME = 1;
    const uint DISPLAY_DEVICE_ACTIVE = 1;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct PHYSICAL_MONITOR {
        public IntPtr Handle;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct MONITORINFOEX {
        public int Size; public RECT Monitor; public RECT Work; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Device;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public int Size;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public uint StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }
    delegate bool MonitorEnumProc(IntPtr monitor, IntPtr dc, ref RECT rect, IntPtr data);

    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorEnumProc callback, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFOEX info);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplayDevices(string device, uint index, ref DISPLAY_DEVICE info, uint flags);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr monitor, out uint count);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr monitor, uint count, [Out] PHYSICAL_MONITOR[] monitors);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool DestroyPhysicalMonitors(uint count, PHYSICAL_MONITOR[] monitors);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool GetCapabilitiesStringLength(IntPtr monitor, out uint length);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool SetVCPFeature(IntPtr monitor, byte code, uint value);

    // mode: 0 = identity only, 1 = capabilities-length read, 2 = D6=On write.
    public static List<string> Run(int mode, string targetPattern) {
        var report = new List<string>();
        var monitors = new List<IntPtr>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr m, IntPtr dc, ref RECT r, IntPtr d) => { monitors.Add(m); return true; }, IntPtr.Zero);
        int targets = 0;
        foreach (var monitor in monitors) {
            var info = new MONITORINFOEX(); info.Size = Marshal.SizeOf(info);
            GetMonitorInfo(monitor, ref info);
            var ids = new List<string>();
            var dd = new DISPLAY_DEVICE(); dd.Size = Marshal.SizeOf(dd);
            for (uint i = 0; EnumDisplayDevices(info.Device, i, ref dd, EDD_GET_DEVICE_INTERFACE_NAME); i++) {
                if ((dd.StateFlags & DISPLAY_DEVICE_ACTIVE) != 0) ids.Add(dd.DeviceID);
                dd = new DISPLAY_DEVICE(); dd.Size = Marshal.SizeOf(dd);
            }
            uint count;
            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, out count) || count == 0) {
                report.Add(info.Device + " ids=" + string.Join(",", ids) + " physical=none err=" + Marshal.GetLastWin32Error());
                continue;
            }
            var physical = new PHYSICAL_MONITOR[count];
            if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, physical)) {
                report.Add(info.Device + " ids=" + string.Join(",", ids) + " handles=failed err=" + Marshal.GetLastWin32Error());
                continue;
            }
            try {
                bool mapped = ids.Count == count;
                for (int i = 0; i < count; i++) {
                    string id = mapped ? ids[i] : "(unmapped)";
                    bool isTarget = mapped && System.Text.RegularExpressions.Regex.IsMatch(id, targetPattern);
                    string line = info.Device + " #" + i + " '" + physical[i].Description + "' id=" + id + (isTarget ? " TARGET" : "");
                    if (isTarget) {
                        targets++;
                        if (mode == 1) {
                            uint length;
                            bool ok = GetCapabilitiesStringLength(physical[i].Handle, out length);
                            line += ok ? " caps-length=" + length : " caps-read=failed err=0x" + Marshal.GetLastWin32Error().ToString("X8");
                        } else if (mode == 2) {
                            bool ok = SetVCPFeature(physical[i].Handle, PowerModeCode, PowerOn);
                            line += ok ? " D6=01 write accepted" : " D6=01 write failed err=0x" + Marshal.GetLastWin32Error().ToString("X8");
                        }
                    }
                    report.Add(line);
                }
                if (!mapped) report.Add(info.Device + " id/handle count mismatch (" + ids.Count + "/" + count + "); refused to target");
            } finally {
                DestroyPhysicalMonitors(count, physical);
            }
        }
        report.Add("targets=" + targets);
        return report;
    }
}
'@

$pattern = '#SAM705[0-9A-F]#'   # Odyssey LC32G7xT only: SAM7058 (DP) or SAM705A (HDMI); never SAM0FDC
Write-Log 'start'
if ($Mode -eq 'Watch') {
    $deadline = (Get-Date).AddMinutes($Minutes)
    $lastPnp = ''
    while ((Get-Date) -lt $deadline) {
        $pnp = (Get-PnpDevice -Class Monitor -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object InstanceId) -join ' '
        if ($pnp -ne $lastPnp) { Write-Log "pnp present: $pnp"; $lastPnp = $pnp }
        $found = [OdysseyDdc]::Run(0, $pattern)
        if (($found | Select-Object -Last 1) -eq 'targets=1') {
            $found | ForEach-Object { Write-Log $_ }
            Start-Sleep -Seconds 5
            if ((([OdysseyDdc]::Run(0, $pattern)) | Select-Object -Last 1) -eq 'targets=1') { $Mode = 'Wake'; break }
            Write-Log 'target disappeared during 5 s confirmation; still watching'
        }
        Start-Sleep -Seconds 2
    }
    if ($Mode -ne 'Wake') { Write-Log "timeout after $Minutes min: no single Odyssey desktop target"; exit 4 }
    Write-Log 'target stable; sending the single D6=01 power-on'
}
if ($Mode -eq 'Burst') {
    $deadline = (Get-Date).AddMinutes($Minutes)
    $lastState = ''; $failures = 0
    while ((Get-Date) -lt $deadline) {
        $result = [OdysseyDdc]::Run(2, $pattern)
        $write = $result | Where-Object { $_ -match 'D6=01' }
        $state = if ($write -match 'accepted') { 'accepted' } elseif ($write) { 'nack' } else { 'no-target' }
        if ($state -eq 'nack') { $failures++ }
        if ($state -ne $lastState) { Write-Log "state=$state failures=$failures $write"; $lastState = $state }
        if ($state -eq 'accepted') { Write-Log "acknowledged after $failures failed writes"; exit 0 }
        Start-Sleep -Milliseconds 250
    }
    Write-Log "burst ended after $Minutes min; failed writes=$failures"
    exit 5
}
Get-PnpDevice -Class Monitor -PresentOnly -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Log ('pnp present: {0} {1}' -f $_.Status, $_.InstanceId) }

$modeNumber = @{ Probe = 0; Caps = 1; Wake = 2 }[$Mode]
$identity = [OdysseyDdc]::Run(0, $pattern)
$identity | ForEach-Object { Write-Log $_ }
$targetCount = [int](($identity | Select-Object -Last 1) -replace 'targets=', '')
if ($Mode -ne 'Probe') {
    if ($targetCount -ne 1) {
        Write-Log "refused: expected exactly one Odyssey desktop target, found $targetCount"
        exit 3
    }
    [OdysseyDdc]::Run($modeNumber, $pattern) | ForEach-Object { Write-Log $_ }
}
Write-Log 'end'
