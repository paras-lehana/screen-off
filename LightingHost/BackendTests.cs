// Local simulated OpenRGB server: exercises real TCP framing and state restoration
// without contacting an RGB server or touching Windows lighting/device APIs.
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace ScreenOff;

internal static class BackendTests
{
    static int checks;
    static void Check(bool value, string message)
    { if (!value) throw new Exception(message); checks++; }
    internal static byte[] Fixture()
    {
        using var ms = new MemoryStream(); using var w = new BinaryWriter(ms);
        void Str(string s) { var bytes = Encoding.UTF8.GetBytes(s + "\0"); w.Write((ushort)bytes.Length); w.Write(bytes); }
        w.Write(0u); w.Write(1u);
        foreach (var text in new[] { "Fake RAM", "Test vendor", "Mock device", "1.0", "SERIAL", "mock-port" }) Str(text);
        w.Write((ushort)1); w.Write(0); Str("Static");
        for (uint i = 0; i < 12; i++) w.Write(i);
        w.Write((ushort)1); w.Write(0x00112233u);
        w.Write((ushort)1); Str("Zone");
        w.Write(0u); w.Write(1u); w.Write(2u); w.Write(2u); w.Write((ushort)0);
        w.Write((ushort)2); Str("LED 1"); w.Write(0u); Str("LED 2"); w.Write(1u);
        w.Write((ushort)2); w.Write(0x00123456u); w.Write(0x00abcdefu);
        ms.Position = 0; w.Write((uint)ms.Length);
        return ms.ToArray();
    }
    internal static async Task<int> Run()
    {
        try
        {
            var data = Fixture(); var parsed = OpenRgbLighting.ParseDevice(0, data);
            Check(parsed.Name == "Fake RAM" && parsed.Colors.SequenceEqual(new uint[] { 0x123456, 0xabcdef }), "Controller parse preserves colours");
            Check(parsed.ActiveMode == 0 && parsed.Modes.Length == 1, "Mode snapshot preserved");
            Check(OpenRgbLighting.ColorPacket(parsed.Colors).Length == 14, "Colour payload size");
            Check(OpenRgbLighting.ModePacket(0, parsed.Modes[0]).Length == 8 + parsed.Modes[0].Length, "Mode payload size");
            foreach (var invalid in new[] { data[..^1], new byte[4], data.Concat(new byte[] { 0 }).ToArray() })
            {
                bool rejected = false;
                try { OpenRgbLighting.ParseDevice(0, invalid); } catch (IOException) { rejected = true; }
                Check(rejected, "Malformed controller must fail before writes");
            }
            using (var server = new MockServer(data))
            using (var rgb = new OpenRgbLighting(server.Port))
            {
                await rgb.PrepareAsync();
                Check(server.Writes.Count == 0, "Preparation/probe must not write lighting");
                rgb.Darken(); rgb.Restore();
                var writes = server.Writes.ToArray();
                Check(writes.Length == 4 && writes[0].Id == 1100, "Direct mode precedes black");
                Check(writes[1].Data.SequenceEqual(OpenRgbLighting.ColorPacket(new uint[2])), "All LEDs black");
                Check(writes[2].Data.SequenceEqual(OpenRgbLighting.ColorPacket(parsed.Colors)), "Restore original colours");
                Check(writes[3].Id == 1101 && writes[3].Data.SequenceEqual(OpenRgbLighting.ModePacket(0, parsed.Modes[0])), "Restore original mode and parameters");
            }
            using (var server = new MockServer(data))
            using (var rgb = new OpenRgbLighting(server.Port))
            {
                await rgb.PrepareAsync(); server.NotifyTopology = true;
                bool rejected = false;
                try { rgb.Darken(); } catch (IOException) { rejected = true; }
                Check(rejected && server.Writes.Count == 0, "Device-list change prevents stale-index writes");
            }
            Console.WriteLine($"PASS {checks} backend checks; simulated local TCP only; no real lighting writes.");
            return 0;
        }
        catch (Exception ex) { Console.Error.WriteLine("FAIL " + ex); return 1; }
    }

    sealed class MockServer : IDisposable
    {
        readonly TcpListener listener = new(IPAddress.Loopback, 0);
        readonly CancellationTokenSource cancel = new();
        readonly Task run;
        internal int Port => ((IPEndPoint)listener.LocalEndpoint).Port;
        internal volatile bool NotifyTopology;
        internal readonly System.Collections.Concurrent.ConcurrentQueue<(uint Id, byte[] Data)> Writes = new();
        internal MockServer(byte[] device)
        {
            listener.Start();
            run = Task.Run(async () =>
            {
                try
                {
                    using var socket = await listener.AcceptTcpClientAsync(cancel.Token);
                    using var stream = socket.GetStream();
                    async Task Reply(uint id, uint type, byte[] data)
                    {
                        using var ms = new MemoryStream(); using var w = new BinaryWriter(ms);
                        w.Write(Encoding.ASCII.GetBytes("ORGB")); w.Write(id); w.Write(type); w.Write((uint)data.Length); w.Write(data);
                        // Fragmented transport tests ReadExactly rather than one-read assumptions.
                        var packet = ms.ToArray();
                        await stream.WriteAsync(packet.AsMemory(0, 7), cancel.Token);
                        await stream.WriteAsync(packet.AsMemory(7), cancel.Token);
                    }
                    while (!cancel.IsCancellationRequested)
                    {
                        var header = new byte[16]; await stream.ReadExactlyAsync(header, cancel.Token);
                        uint id = BitConverter.ToUInt32(header, 4), type = BitConverter.ToUInt32(header, 8);
                        var payload = new byte[BitConverter.ToUInt32(header, 12)];
                        await stream.ReadExactlyAsync(payload, cancel.Token);
                        if (NotifyTopology) { NotifyTopology = false; await Reply(0, 100, []); }
                        switch (type)
                        {
                            case 40: await Reply(id, type, BitConverter.GetBytes(6u)); break;
                            case 0: await Reply(id, type, BitConverter.GetBytes(1u)); break;
                            case 1: await Reply(id, type, device); break;
                            case 50: break;
                            default: Writes.Enqueue((type, payload)); break;
                        }
                    }
                }
                catch (Exception ex) when (ex is OperationCanceledException or IOException or SocketException) { }
            });
        }
        public void Dispose() { cancel.Cancel(); listener.Stop(); run.GetAwaiter().GetResult(); cancel.Dispose(); }
    }
}
