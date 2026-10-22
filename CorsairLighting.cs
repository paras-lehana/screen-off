using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

// ABI from the pinned official iCUE SDK 4.0.84 headers. Lighting only: no key
// interception, device resets, hardware profiles, or other device configuration.
public sealed class CorsairLighting : IDisposable {
    const string Dll = "iCUESDK.x64_2019.dll";
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
    public struct Device {
        public int Type;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Id;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Serial;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Model;
        public int LedCount, ChannelCount;
    }
    [StructLayout(LayoutKind.Sequential)] struct Filter { public int Mask; }
    [StructLayout(LayoutKind.Sequential)] struct Position { public uint Id; public double X,Y; }
    [StructLayout(LayoutKind.Sequential)] struct Color { public uint Id; public byte R,G,B,A; }
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void Changed(IntPtr context, IntPtr data);
    [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] static extern int CorsairConnect(Changed handler, IntPtr context);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] static extern int CorsairDisconnect();
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl)] static extern int CorsairGetDevices(ref Filter filter, int max, [Out] Device[] devices, out int size);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl, CharSet=CharSet.Ansi)] static extern int CorsairGetLedPositions(string id, int max, [Out] Position[] positions, out int size);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl, CharSet=CharSet.Ansi)] static extern int CorsairRequestControl(string id, int level);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl, CharSet=CharSet.Ansi)] static extern int CorsairReleaseControl(string id);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl, CharSet=CharSet.Ansi)] static extern int CorsairSetLedColors(string id, int size, Color[] colors);
    [DllImport(Dll, CallingConvention=CallingConvention.Cdecl, CharSet=CharSet.Ansi)] static extern int CorsairGetLedColors(string id, int size, [In,Out] Color[] colors);
    Changed handler;
    volatile int state;
    bool connected;
    readonly List<Device> owned = new List<Device>();
    readonly Dictionary<string,Color[]> frames = new Dictionary<string,Color[]>();
    static void Check(int result, string operation) { if(result != 0) throw new Exception(operation+" failed (iCUE error "+result+")"); }
    // typeMask uses the SDK's CorsairDeviceType bits (keyboard 0x1, mouse 0x2, ...).
    public Device[] Discover(string dllPath, int typeMask) {
        if(LoadLibraryEx(dllPath, IntPtr.Zero, 0x1100)==IntPtr.Zero)
            throw new Exception("Cannot load official iCUE SDK: Win32 "+Marshal.GetLastWin32Error());
        handler = delegate(IntPtr context, IntPtr data) { state=Marshal.ReadInt32(data); };
        Check(CorsairConnect(handler, IntPtr.Zero), "Connect");
        connected=true;
        // 3 (Timeout) means the SDK is still retrying; wait for Connected, Refused or Lost.
        for(int i=0;i<150 && state!=6 && state!=4 && state!=5;i++) Thread.Sleep(100);
        if(state!=6) throw new Exception(StateText(state));
        var filter=new Filter { Mask=typeMask };
        var devices=new Device[64]; int size;
        Check(CorsairGetDevices(ref filter, devices.Length, devices, out size), "Device discovery");
        var selected=new List<Device>();
        for(int i=0;i<size;i++) if(devices[i].LedCount>0) selected.Add(devices[i]);
        if(selected.Count==0) throw new Exception("iCUE exposes no Corsair devices of the selected types");
        return selected.ToArray();
    }
    static string StateText(int value) {
        switch(value) {
            case 3: return "iCUE did not answer the SDK within 15 s (session state 3). iCUE pauses its SDK while Windows is locked or used over Remote Desktop; otherwise check iCUE Settings > Software and Games > Software Integrations.";
            case 4: return "iCUE refused the SDK connection (session state 4). Turn on iCUE Settings > Software and Games > Software Integrations (iCUE 5: Settings > SDK).";
            case 5: return "iCUE closed the SDK connection (session state 5).";
            default: return "iCUE SDK session state "+value;
        }
    }
    public void Acquire(Device[] devices) {
        foreach(var device in devices) {
            Check(CorsairRequestControl(device.Id,1), "Exclusive lighting control of "+device.Model);
            owned.Add(device);
            var positions=new Position[device.LedCount]; int size;
            Check(CorsairGetLedPositions(device.Id,positions.Length,positions,out size), "LED discovery");
            if(size==0) throw new Exception(device.Model+" has no controllable LEDs");
            var frame=new Color[size];
            for(int i=0;i<size;i++) frame[i]=new Color { Id=positions[i].Id, A=255 };
            frames[device.Id]=frame;
        }
        Darken();
    }
    public void Darken() {
        foreach(var item in frames) Check(CorsairSetLedColors(item.Key,item.Value.Length,item.Value),"Corsair black frame");
    }
    public string Verify() {
        int lit=0,total=0;
        foreach(var item in frames) {
            var colors=(Color[])item.Value.Clone();
            Check(CorsairGetLedColors(item.Key,colors.Length,colors),"Corsair readback");
            foreach(var color in colors) { total++; if(color.R!=0 || color.G!=0 || color.B!=0) lit++; }
        }
        return "Corsair LED readback: "+lit+" nonblack / "+total;
    }
    public void Dispose() {
        foreach(var device in owned) CorsairReleaseControl(device.Id);
        owned.Clear(); frames.Clear();
        if(connected) { CorsairDisconnect(); connected=false; }
        GC.KeepAlive(handler);
    }
}
