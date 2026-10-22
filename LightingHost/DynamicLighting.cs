// Windows HID LampArray backend. Background control requires the accompanying
// registered identity package and user priority in Windows Dynamic Lighting.
using Windows.Devices.Enumeration;
using Windows.Devices.Lights;
using Windows.Foundation.Metadata;
using Windows.UI;

namespace ScreenOff;

internal sealed class DynamicLighting(bool probe) : ILightingBackend
{
    readonly List<(LampArray Array, double Brightness)> arrays = [];
    bool changed;
    public string Description { get; private set; } = "Windows Dynamic Lighting";

    public async Task PrepareAsync()
    {
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22631))
            throw new InvalidOperationException("Windows Dynamic Lighting background control requires Windows 11 23H2 or later.");
        if (!ApiInformation.IsPropertyPresent("Windows.Devices.Lights.LampArray", "IsAvailable"))
            throw new InvalidOperationException("This Windows build lacks LampArray background availability APIs.");
        // Do not pretend an unpackaged background worker can own these devices.
        try { _ = Windows.ApplicationModel.Package.Current.Id.FullName; }
        catch { throw new InvalidOperationException("Dynamic Lighting identity is not registered. Run Install-DynamicLighting.ps1; then prioritize Screen Off Lighting in Windows Settings."); }
        var devices = await DeviceInformation.FindAllAsync(LampArray.GetDeviceSelector());
        foreach (var device in devices)
        {
            var array = await LampArray.FromIdAsync(device.Id);
            if (array == null) continue;
            if (!array.IsAvailable)
                throw new InvalidOperationException("Windows has not granted lighting control for " + device.Name + ". Check Dynamic Lighting background priority.");
            arrays.Add((array, array.BrightnessLevel));
        }
        if (arrays.Count == 0)
            throw new InvalidOperationException("No compatible HID LampArray devices found. Aura/RAM/K100 compatibility is not implied.");
        Description = "Windows Dynamic Lighting: " + arrays.Count + " available LampArray device(s)";
    }

    public void Darken()
    {
        if (probe) throw new InvalidOperationException("Probe cannot change lighting.");
        foreach (var entry in arrays)
        {
            if (!entry.Array.IsAvailable)
                throw new InvalidOperationException("Dynamic Lighting ownership was lost. Check Windows background priority.");
            changed = true;
            entry.Array.SetColor(Color.FromArgb(255, 0, 0, 0));
            entry.Array.BrightnessLevel = 0;
        }
    }

    public void Restore()
    {
        List<string> errors = [];
        if (changed)
            foreach (var entry in arrays)
                try { entry.Array.BrightnessLevel = entry.Brightness; }
                catch (Exception ex) { errors.Add(ex.Message); }
        // There is no GetColor snapshot API. Worker exit releases app ownership
        // to Windows' next lighting controller; it cannot restore an animation frame.
        if (errors.Count > 0) throw new InvalidOperationException(string.Join("; ", errors));
    }

    public void Dispose() { arrays.Clear(); }
}
