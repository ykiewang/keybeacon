using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace KeyBeacon.App.Settings;

public enum DisplayMode
{
    Full,
    Compact
}

public enum PinnedCorner
{
    TopLeft,
    TopRight,
    BottomLeft,
    BottomRight
}

public enum UiCulturePreference
{
    System,
    English,
    Chinese
}

/// <summary>
/// Persisted user settings (data-model.md §8), stored at
/// <c>%LOCALAPPDATA%\KeyBeacon\settings.json</c>.
/// </summary>
public sealed class AppSettings
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public string? SelectedKeyboardId { get; set; }
    public DisplayMode DisplayMode { get; set; } = DisplayMode.Full;
    public PinnedCorner PinnedCorner { get; set; } = PinnedCorner.TopRight;
    public bool VerboseLogging { get; set; }
    public UiCulturePreference UICulture { get; set; } = UiCulturePreference.System;

    public static string DefaultPath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "KeyBeacon",
        "settings.json");

    /// <summary>Loads settings, falling back to defaults when absent or unreadable.</summary>
    public static AppSettings Load(string? path = null)
    {
        var file = path ?? DefaultPath;
        try
        {
            if (!File.Exists(file)) return new AppSettings();
            var json = File.ReadAllText(file);
            return JsonSerializer.Deserialize<AppSettings>(json, JsonOptions) ?? new AppSettings();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            return new AppSettings();
        }
    }

    /// <summary>Writes settings atomically (temp file + replace) so a crash cannot truncate them.</summary>
    public void Save(string? path = null)
    {
        var file = path ?? DefaultPath;
        var dir = Path.GetDirectoryName(file);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

        var temp = file + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(this, JsonOptions));
        File.Move(temp, file, overwrite: true);
    }
}
