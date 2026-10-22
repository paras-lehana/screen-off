# Odyssey G7 recovery through NVIDIA's own I2C path (NvAPI), independent of the
# Windows session/desktop. Needed because under Microsoft Remote Desktop the physical
# outputs are not exposed to the Windows monitor-configuration API (20 Oct 22:14).
#
# Modes:
#   -Mode Probe  read EDID identity of every NVIDIA output; NO DDC/CI traffic.
#   -Mode Wake   one DDC/CI Set VCP 0xD6 = 0x01 (On) to the Odyssey's output.
#   -Mode Burst  repeat Wake every 250 ms for -Seconds while the Odyssey is identified;
#                stop at the first acknowledged write.
#   -Mode Input  wait for the Odyssey on HDMI (SAM705A), then try each -Inputs value
#                (VCP 0x60) until the Odyssey appears on DisplayPort (SAM7058).
#                21 Oct: monitor input DP2 with the cable in DP1 hid it from the PC.
#                Samsung SET code 0x09 = DP IN 1 (owner-observed banner). The caps string
#                advertises 60(12 0F 10) and 0x0F was acknowledged but ignored; reads
#                report HDMI as 0x06. Unplug HDMI right after the switch, or Auto Source
#                falls back to the HDMI picture before DisplayPort links.
# -SpeedKhz: 0 = driver default, else 3/10/33/100. The power value is constant (On);
# Off (0x04/0x05) cannot be sent. Targets only EDID SAM 0x7058/0x705A, never SAM 0x0FDC.
# IDs/layouts: NVIDIA nvapi_interface.h / nvapi.h (NV_I2C_INFO_V3, NV_EDID_V3).
param([ValidateSet('Probe', 'Wake', 'Burst', 'Input')][string]$Mode = 'Probe', [int]$Seconds = 120,
      [ValidateSet(0, 3, 10, 33, 100)][int]$SpeedKhz = 0, [byte[]]$Inputs = @(0x09, 0x0F))

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $PSScriptRoot 'odyssey-recovery.log'
function Write-Log([string]$text) {
    $line = '{0} [Nv{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Mode, $text
    Add-Content -Path $logPath -Value $line -Encoding utf8
    Write-Output $line
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class OdysseyNv {
    [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)]
    static extern IntPtr QueryInterface(uint id);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int InitializeFn();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int EnumGpusFn([Out] IntPtr[] handles, out int count);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int AllDisplayIdsFn(IntPtr gpu, IntPtr ids, ref uint count);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GpuOutputFn(uint displayId, out IntPtr gpu, out uint outputId);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GetEdidFn(IntPtr gpu, uint outputId, IntPtr edid);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int I2CWriteFn(IntPtr gpu, IntPtr info);

    static T Fn<T>(uint id) where T : class {
        IntPtr p = QueryInterface(id);
        if (p == IntPtr.Zero) throw new Exception("NvAPI function 0x" + id.ToString("X8") + " unavailable");
        return Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
    }

    public class Output { public IntPtr Gpu; public uint OutputId; public uint DisplayId; public uint Flags; public string Identity; public bool IsOdyssey; }

    public static List<Output> Scan(List<string> log) {
        int status = Fn<InitializeFn>(0x0150E828)();
        log.Add("NvAPI_Initialize=" + status);
        if (status != 0) return new List<Output>();
        var gpus = new IntPtr[64]; int gpuCount;
        log.Add("EnumPhysicalGPUs=" + Fn<EnumGpusFn>(0xE5AC921F)(gpus, out gpuCount) + " count=" + gpuCount);
        var outputs = new List<Output>();
        for (int g = 0; g < gpuCount; g++) {
            const int entrySize = 16; uint count = 16;
            IntPtr ids = Marshal.AllocHGlobal(entrySize * 16);
            try {
                for (int i = 0; i < 16 * entrySize; i += 4) Marshal.WriteInt32(ids, i, 0);
                for (int i = 0; i < 16; i++) Marshal.WriteInt32(ids, i * entrySize, entrySize | (3 << 16));
                int s = Fn<AllDisplayIdsFn>(0x785210A2)(gpus[g], ids, ref count);
                log.Add("GetAllDisplayIds=" + s + " count=" + count);
                if (s != 0) continue;
                for (int i = 0; i < count; i++) {
                    var o = new Output();
                    o.DisplayId = (uint)Marshal.ReadInt32(ids, i * entrySize + 8);
                    o.Flags = (uint)Marshal.ReadInt32(ids, i * entrySize + 12);
                    if (Fn<GpuOutputFn>(0x112BA1A5)(o.DisplayId, out o.Gpu, out o.OutputId) != 0) continue;
                    o.Identity = ReadIdentity(o.Gpu, o.OutputId);
                    o.IsOdyssey = o.Identity == "SAM7058" || o.Identity == "SAM705A";
                    outputs.Add(o);
                }
            } finally { Marshal.FreeHGlobal(ids); }
        }
        return outputs;
    }

    static string ReadIdentity(IntPtr gpu, uint outputId) {
        const int size = 272;   // NV_EDID_V3: version, 256-byte block, sizeofEDID, edidId, offset
        IntPtr edid = Marshal.AllocHGlobal(size);
        try {
            for (int i = 0; i < size; i += 4) Marshal.WriteInt32(edid, i, 0);
            Marshal.WriteInt32(edid, 0, size | (3 << 16));
            int s = Fn<GetEdidFn>(0x37D32E69)(gpu, outputId, edid);
            if (s != 0) return "edid-status=" + s;
            int m = (Marshal.ReadByte(edid, 4 + 8) << 8) | Marshal.ReadByte(edid, 4 + 9);
            string mfg = new string(new[] { (char)('A' - 1 + ((m >> 10) & 31)), (char)('A' - 1 + ((m >> 5) & 31)), (char)('A' - 1 + (m & 31)) });
            int product = Marshal.ReadByte(edid, 4 + 10) | (Marshal.ReadByte(edid, 4 + 11) << 8);
            return mfg + product.ToString("X4");
        } finally { Marshal.FreeHGlobal(edid); }
    }

    // One DDC/CI Set VCP D6=01 (power On). Returns NvAPI status (0 = acknowledged).
    public static int PowerOn(Output o, int speedKhz) { return SetVcp(o, 0xD6, 0x01, speedKhz); }

    // One DDC/CI Set VCP 60 (input select). Only real input codes 0x01-0x12 are allowed.
    public static int SelectInput(Output o, byte input, int speedKhz) {
        if (input < 0x01 || input > 0x12) throw new ArgumentOutOfRangeException("input");
        return SetVcp(o, 0x60, input, speedKhz);
    }

    // Private on purpose: callers can only reach the two whitelisted writes above.
    static int SetVcp(Output o, byte code, byte value, int speedKhz) {
        byte[] message = { 0x84, 0x03, code, 0x00, value, 0x00 };
        byte check = 0x6E ^ 0x51;
        for (int i = 0; i < 5; i++) check ^= message[i];
        message[5] = check;
        int speedEnum = speedKhz == 3 ? 1 : speedKhz == 10 ? 2 : speedKhz == 33 ? 3 : speedKhz == 100 ? 4 : 0;
        IntPtr reg = Marshal.AllocHGlobal(1), data = Marshal.AllocHGlobal(message.Length), info = Marshal.AllocHGlobal(64);
        try {
            Marshal.WriteByte(reg, 0x51);
            Marshal.Copy(message, 0, data, message.Length);
            for (int i = 0; i < 64; i += 4) Marshal.WriteInt32(info, i, 0);
            Marshal.WriteInt32(info, 0, 64 | (3 << 16));     // NV_I2C_INFO_VER3
            Marshal.WriteInt32(info, 4, (int)o.OutputId);   // displayMask
            Marshal.WriteByte(info, 8, 1);                  // bIsDDCPort
            Marshal.WriteByte(info, 9, 0x6E);               // DDC/CI write address
            Marshal.WriteIntPtr(info, 16, reg);             // pbI2cRegAddress = source 0x51
            Marshal.WriteInt32(info, 24, 1);                // regAddrSize
            Marshal.WriteIntPtr(info, 32, data);            // pbData
            Marshal.WriteInt32(info, 40, message.Length);   // cbSize
            Marshal.WriteInt32(info, 44, 0xFFFF);           // i2cSpeed (deprecated marker)
            Marshal.WriteInt32(info, 48, speedEnum);        // i2cSpeedKhz
            return Fn<I2CWriteFn>(0xE812EB07)(o.Gpu, info);
        } finally { Marshal.FreeHGlobal(reg); Marshal.FreeHGlobal(data); Marshal.FreeHGlobal(info); }
    }
}
'@

Write-Log "start speedKhz=$SpeedKhz"
$deadline = (Get-Date).AddSeconds($Seconds)
if ($Mode -eq 'Input') {
    function Find-Odyssey([string]$identity) {
        $log = New-Object System.Collections.Generic.List[string]
        @([OdysseyNv]::Scan($log) | Where-Object { $_.Identity -eq $identity })
    }
    $hdmi = @()
    while ((Get-Date) -lt $deadline) {
        if (@(Find-Odyssey 'SAM7058').Count -gt 0) { Write-Log 'Odyssey already on DisplayPort; nothing to send'; exit 0 }
        $hdmi = Find-Odyssey 'SAM705A'
        if ($hdmi.Count -eq 1) { break }
        Start-Sleep -Milliseconds 500
    }
    if ($hdmi.Count -ne 1) { Write-Log "timeout: Odyssey not seen on HDMI (found $($hdmi.Count))"; exit 4 }
    Write-Log ('Odyssey on HDMI output=0x{0:X}' -f $hdmi[0].OutputId)
    foreach ($code in $Inputs) {
        $status = [OdysseyNv]::SelectInput($hdmi[0], $code, $SpeedKhz)
        Write-Log ('input=0x{0:X2} status={1}' -f $code, $status)
        $check = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $check) {
            $dp = Find-Odyssey 'SAM7058'
            if ($dp.Count -gt 0) { Write-Log ('Odyssey now on DisplayPort output=0x{0:X} after input=0x{1:X2}' -f $dp[0].OutputId, $code); exit 0 }
            Start-Sleep -Milliseconds 500
        }
        Write-Log ('input=0x{0:X2}: no DisplayPort identity within 10 s' -f $code)
    }
    Write-Log 'no input value brought the Odyssey onto DisplayPort'
    exit 5
}
$lastState = ''; $failures = 0
do {
    $log = New-Object System.Collections.Generic.List[string]
    $outputs = [OdysseyNv]::Scan($log)
    $targets = @($outputs | Where-Object IsOdyssey)
    if ($Mode -eq 'Probe' -or $lastState -eq '') {
        $log | ForEach-Object { Write-Log $_ }
        $outputs | ForEach-Object { Write-Log ('display=0x{0:X8} output=0x{1:X} flags=0x{2:X8} identity={3}{4}' -f $_.DisplayId, $_.OutputId, $_.Flags, $_.Identity, $(if ($_.IsOdyssey) { ' TARGET' } else { '' })) }
    }
    if ($Mode -eq 'Probe') { break }
    if ($targets.Count -ne 1) {
        $state = "targets=$($targets.Count)"
    } else {
        $status = [OdysseyNv]::PowerOn($targets[0], $SpeedKhz)
        $state = if ($status -eq 0) { 'acknowledged' } else { "status=$status" }
        if ($status -ne 0) { $failures++ }
    }
    if ($state -ne $lastState) { Write-Log "state=$state failures=$failures"; $lastState = $state }
    if ($state -eq 'acknowledged' -or $Mode -eq 'Wake') { break }
    Start-Sleep -Milliseconds 250
} while ((Get-Date) -lt $deadline)
Write-Log "end failures=$failures"
