// Loopback-only OpenRGB SDK client, negotiated protocol 3. Hardware access stays
// in the user's OpenRGB server; no driver loading, scanning, or service startup.
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace ScreenOff;

internal sealed record RgbDevice(uint Id, string Identity, string Name, int ActiveMode, byte[][] Modes, uint[] Colors);

internal sealed class OpenRgbLighting(int port) : ILightingBackend
{
    TcpClient? client;
    NetworkStream? stream;
    List<RgbDevice> saved = [];
    bool changed, topologyChanged;
    public string Description { get; private set; } = "OpenRGB";
    const uint Protocol = 3;
    const int MaxPacket = 4 * 1024 * 1024;

    public async Task PrepareAsync()
    {
        if (port < 1 || port > 65535) throw new ArgumentOutOfRangeException(nameof(port));
        client = new TcpClient { ReceiveTimeout = 2500, SendTimeout = 2500 };
        using var timeout = new CancellationTokenSource(2500);
        try { await client.ConnectAsync(IPAddress.Loopback, port, timeout.Token); }
        catch (Exception ex) { throw new IOException("OpenRGB SDK server unavailable at 127.0.0.1:" + port + ". Start its SDK server. " + ex.Message); }
        stream = client.GetStream();
        stream.ReadTimeout = stream.WriteTimeout = 2500;
        Send(0, 40, BitConverter.GetBytes(Protocol));
        byte[] version = Receive(0, 40);
        if (version.Length != 4 || BitConverter.ToUInt32(version) < Protocol)
            throw new IOException("OpenRGB SDK protocol 3 or newer is required.");
        Send(0, 50, Encoding.UTF8.GetBytes("Screen Off 1.6\0"));
        saved = ReadDevices();
        if (saved.Count == 0 || saved.All(d => d.Colors.Length == 0))
            throw new IOException("OpenRGB reports no controllable LEDs.");
        if (topologyChanged) throw new IOException("OpenRGB device list changed during preparation; retry when stable.");
        Description = "OpenRGB: " + string.Join(", ", saved.Select(d => d.Name));
    }

    List<RgbDevice> ReadDevices()
    {
        Send(0, 0, []);
        byte[] countPacket = Receive(0, 0);
        if (countPacket.Length != 4) throw new IOException("Unexpected OpenRGB controller-count packet.");
        uint count = BitConverter.ToUInt32(countPacket);
        if (count > 256) throw new IOException("OpenRGB controller count exceeds limit.");
        List<RgbDevice> result = [];
        for (uint id = 0; id < count; id++)
        {
            Send(id, 1, BitConverter.GetBytes(Protocol));
            result.Add(ParseDevice(id, Receive(id, 1)));
        }
        return result;
    }

    // Parse only the negotiated format. Bounds checks reject truncated or oversized
    // packets before any device writes, rather than guessing offsets.
    internal static RgbDevice ParseDevice(uint id, byte[] packet)
    {
        using var memory = new MemoryStream(packet, false);
        using var r = new BinaryReader(memory, Encoding.UTF8);
        if (r.ReadUInt32() != packet.Length) throw new IOException("Invalid OpenRGB device data size.");
        _ = r.ReadUInt32(); // Controller type.
        string ReadString()
        {
            int size = r.ReadUInt16();
            byte[] bytes = r.ReadBytes(size);
            if (bytes.Length != size || size == 0 || bytes[^1] != 0)
                throw new IOException("Invalid OpenRGB string.");
            return Encoding.UTF8.GetString(bytes, 0, size - 1);
        }
        void Skip(int size)
        {
            if (size < 0 || memory.Position + size > memory.Length) throw new EndOfStreamException();
            memory.Position += size;
        }
        string name = ReadString(), vendor = ReadString();
        _ = ReadString(); _ = ReadString(); // Description, firmware version.
        string serial = ReadString(), location = ReadString();
        int modes = r.ReadUInt16(), active = r.ReadInt32();
        if (modes < 1 || modes > 1024 || active < 0 || active >= modes)
            throw new IOException("Invalid OpenRGB active mode.");
        byte[][] modeData = new byte[modes][];
        for (int i = 0; i < modes; i++)
        {
            int start = checked((int)memory.Position);
            _ = ReadString();
            Skip(12 * 4); // protocol 3 includes brightness bounds and current brightness.
            int colors = r.ReadUInt16();
            Skip(colors * 4);
            modeData[i] = packet[start..checked((int)memory.Position)];
        }
        int zones = r.ReadUInt16();
        for (int i = 0; i < zones; i++) { _ = ReadString(); Skip(4 * 4); Skip(r.ReadUInt16()); }
        int leds = r.ReadUInt16();
        for (int i = 0; i < leds; i++) { _ = ReadString(); Skip(4); }
        int colorCount = r.ReadUInt16();
        uint[] values = new uint[colorCount];
        for (int i = 0; i < values.Length; i++) values[i] = r.ReadUInt32();
        if (memory.Position != memory.Length) throw new IOException("Unexpected OpenRGB protocol 3 device data tail.");
        return new RgbDevice(id, string.Join("\u001f", name, vendor, serial, location), name, active, modeData, values);
    }

    public void Darken()
    {
        // A request/response barrier also consumes asynchronous device-list changes.
        Send(0, 0, []);
        var count = Receive(0, 0);
        if (topologyChanged || count.Length != 4 || BitConverter.ToUInt32(count) != saved.Count)
            throw new IOException("OpenRGB device list changed; stopped black submissions to avoid stale device indices.");
        foreach (var device in saved.Where(d => d.Colors.Length > 0))
        {
            changed = true; // Restore even if a write fails part-way through.
            Send(device.Id, 1100, []);
            Send(device.Id, 1050, ColorPacket(new uint[device.Colors.Length]));
        }
    }

    public void Restore()
    {
        if (!changed) return;
        var current = ReadDevices();
        List<string> errors = [];
        foreach (var old in saved.Where(d => d.Colors.Length > 0))
        {
            // Remap after unplug/reorder by identity; never apply a saved state to
            // an ambiguous or replacement device at the same numeric index.
            var matches = current.Where(d => d.Identity == old.Identity).ToArray();
            if (matches.Length != 1 || saved.Count(d => d.Identity == old.Identity) != 1
                || matches[0].Colors.Length != old.Colors.Length || matches[0].Modes.Length != old.Modes.Length)
            { errors.Add(old.Name + " missing/ambiguous/changed"); continue; }
            var target = matches[0];
            Send(target.Id, 1050, ColorPacket(old.Colors));
            Send(target.Id, 1101, ModePacket(old.ActiveMode, old.Modes[old.ActiveMode]));
        }
        // Barrier confirms server communication, not physical light output.
        Send(0, 0, []); _ = Receive(0, 0);
        changed = false;
        if (errors.Count > 0) throw new IOException(string.Join("; ", errors));
    }

    internal static byte[] ColorPacket(uint[] colors)
    {
        using var data = new MemoryStream(); using var w = new BinaryWriter(data);
        w.Write(checked((uint)(6 + colors.Length * 4))); w.Write(checked((ushort)colors.Length));
        foreach (uint color in colors) w.Write(color);
        return data.ToArray();
    }
    internal static byte[] ModePacket(int mode, byte[] data)
    {
        using var packet = new MemoryStream(); using var w = new BinaryWriter(packet);
        w.Write(checked((uint)(8 + data.Length))); w.Write(mode); w.Write(data);
        return packet.ToArray();
    }
    void Send(uint device, uint packetId, byte[] data)
    {
        using var packet = new MemoryStream(); using var writer = new BinaryWriter(packet);
        writer.Write(Encoding.ASCII.GetBytes("ORGB")); writer.Write(device); writer.Write(packetId);
        writer.Write((uint)data.Length); writer.Write(data);
        stream!.Write(packet.ToArray());
    }
    byte[] Receive(uint device, uint packetId)
    {
        for (int skipped = 0; skipped < 32; skipped++)
        {
            byte[] header = new byte[16]; stream!.ReadExactly(header);
            if (Encoding.ASCII.GetString(header, 0, 4) != "ORGB") throw new IOException("Invalid OpenRGB packet signature.");
            uint id = BitConverter.ToUInt32(header, 4), type = BitConverter.ToUInt32(header, 8), size = BitConverter.ToUInt32(header, 12);
            if (size > MaxPacket) throw new IOException("OpenRGB packet exceeds limit.");
            byte[] data = new byte[checked((int)size)]; stream.ReadExactly(data);
            if (type == 100) { topologyChanged = true; continue; }
            if (type == 51) continue; // Optional server name.
            if (id == device && type == packetId) return data;
            throw new IOException("Unexpected OpenRGB response " + type + ".");
        }
        throw new IOException("Too many unsolicited OpenRGB messages.");
    }
    public void Dispose() { stream?.Dispose(); client?.Dispose(); }
}
