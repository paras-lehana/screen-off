// Optional lighting worker. Probe mode only enumerates; normal mode restores on
// stop or parent exit. It never controls display power or Windows session locks.
using System.Diagnostics;
using System.Text;

namespace ScreenOff;

internal interface ILightingBackend : IDisposable
{
    string Description { get; }
    Task PrepareAsync();
    void Darken();
    void Restore();
}

internal static class Program
{
    static async Task<int> Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--self-test")
            return await BackendTests.Run();
        var options = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (int i = 0; i < args.Length; i += 2)
        {
            if (i + 1 >= args.Length || !args[i].StartsWith("--"))
            { Console.Error.WriteLine("Expected --name value pairs."); return 2; }
            options.Add(args[i], args[i + 1]);
        }
        string backend = options.GetValueOrDefault("--backend", "dynamic");
        string prefix = options.GetValueOrDefault("--state", "");
        bool probe = options.GetValueOrDefault("--probe", "0") == "1";
        void Status(string value)
        {
            if (prefix.Length > 0)
            {
                // Atomic replacement keeps the AHK reader from seeing partial status.
                File.WriteAllText(prefix + ".status.tmp", value, new UTF8Encoding(false));
                File.Move(prefix + ".status.tmp", prefix + ".status", true);
                File.AppendAllText(prefix + ".log", DateTimeOffset.Now.ToString("O") + " " + value + Environment.NewLine);
            }
            Console.WriteLine(value);
        }
        ILightingBackend? lights = null;
        Process? parent = null;
        string? failure = null;
        bool prepared = false;
        try
        {
            if (!probe)
            {
                if (prefix.Length == 0) throw new ArgumentException("--state is required.");
                parent = Process.GetProcessById(int.Parse(options["--parent"]));
                _ = parent.Handle; // Retain identity even if its PID is later reused.
                if (parent.HasExited || File.Exists(prefix + ".stop")) return 0;
            }
            lights = backend switch
            {
                "dynamic" => new DynamicLighting(probe),
                "openrgb" => new OpenRgbLighting(int.Parse(options.GetValueOrDefault("--port", "6742"))),
                _ => throw new ArgumentException("Backend must be dynamic or openrgb.")
            };
            await lights.PrepareAsync();
            prepared = true;
            if (probe) { Status("AVAILABLE|" + lights.Description + "; no lighting writes"); return 0; }
            int frames = 0;
            while (!parent!.HasExited && !File.Exists(prefix + ".stop"))
            {
                lights.Darken();
                if (++frames == 1) Status("APPLIED|" + lights.Description + "; physical result unverified");
                await Task.Delay(500);
            }
        }
        catch (Exception ex) { failure = ex.Message; }
        finally
        {
            if (lights != null)
            {
                if (!probe && prepared)
                    try { lights.Restore(); }
                    catch (Exception ex) { failure = (failure == null ? "" : failure + "; ") + "Restore: " + ex.Message; }
                lights.Dispose();
            }
            parent?.Dispose();
            if (failure != null) Status("ERROR|" + failure);
            else if (!probe) Status("RESTORED|Lighting ownership/state released; physical result unverified");
        }
        return failure == null ? 0 : 1;
    }
}
