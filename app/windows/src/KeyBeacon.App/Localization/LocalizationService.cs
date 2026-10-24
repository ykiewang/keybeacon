using System;
using System.Globalization;
using System.Resources;
using KeyBeacon.App.Settings;

namespace KeyBeacon.App.Localization;

/// <summary>
/// UI string lookup (FR-021). Language follows the OS locale by default:
/// any zh-* culture resolves to Chinese, everything else to English.
/// </summary>
public sealed class LocalizationService
{
    private static readonly ResourceManager Resources = new(
        "KeyBeacon.App.Localization.Resources",
        typeof(LocalizationService).Assembly);

    public LocalizationService(CultureInfo culture)
    {
        Culture = culture;
    }

    public CultureInfo Culture { get; }

    /// <summary>Resolves the UI culture from the user preference, defaulting to the OS setting.</summary>
    public static CultureInfo ResolveCulture(UiCulturePreference preference) => preference switch
    {
        UiCulturePreference.Chinese => new CultureInfo("zh-CN"),
        UiCulturePreference.English => new CultureInfo("en"),
        _ => CultureInfo.CurrentUICulture
    };

    public static LocalizationService FromPreference(UiCulturePreference preference) =>
        new(ResolveCulture(preference));

    /// <summary>Returns the localized string, falling back to the key itself when missing.</summary>
    public string this[string key] => Get(key);

    public string Get(string key) => Resources.GetString(key, Culture) ?? key;

    public string Format(string key, params object?[] args)
    {
        var template = Get(key);
        try
        {
            return string.Format(Culture, template, args);
        }
        catch (FormatException)
        {
            return template;
        }
    }

    /// <summary>Layer label with the <c>L{index}</c> fallback baked in (FR-004).</summary>
    public string LayerLabel(byte index, string? reportedName) =>
        string.IsNullOrWhiteSpace(reportedName) ? Format("Layer_Fallback", index) : reportedName!;

    /// <summary>Battery label honouring the unavailable sentinel — never fabricates a value (FR-017).</summary>
    public string BatteryLabel(int? percent) =>
        percent is null ? Get("Battery_Unavailable") : Format("Battery_Percent", percent.Value);
}
