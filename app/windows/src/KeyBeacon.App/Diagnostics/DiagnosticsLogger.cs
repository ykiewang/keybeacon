using System;
using Microsoft.Extensions.Logging;

namespace KeyBeacon.App.Diagnostics;

/// <summary>
/// Structured diagnostic facade (FR-018). Category and event names are kept
/// byte-identical to the macOS <c>DiagnosticsLogger</c> so cross-platform issue
/// reports read the same way (research.md §4).
/// Every degradation event emits exactly one entry.
/// </summary>
public static class DiagnosticsLogger
{
    public const string Subsystem = "KeyBeacon";

    public static class Categories
    {
        public const string Capability = "capability";
        public const string Profile = "profile";
        public const string Battery = "battery";
        public const string Staleness = "staleness";
        public const string Connection = "connection";
        public const string Discovery = "discovery";
    }

    /// <summary>Category-scoped logger. Pass the category constant from <see cref="Categories"/>.</summary>
    public static ILogger For(ILoggerFactory factory, string category)
    {
        ArgumentNullException.ThrowIfNull(factory);
        ArgumentException.ThrowIfNullOrWhiteSpace(category);
        return factory.CreateLogger($"{Subsystem}.{category}");
    }
}

/// <summary>
/// Stable event names. Using constants keeps the wire-adjacent vocabulary
/// consistent between code, logs and issue reports.
/// </summary>
public static class DiagnosticEvents
{
    // capability
    public const string CapabilityDiscovered = "capability.discovered";
    public const string CapabilityInconsistent = "capability.inconsistent";
    public const string CapabilityMutated = "capability.mutated";

    // profile
    public const string ProfileOutOfRange = "profile.out_of_range";

    // battery
    public const string BatteryLengthMismatch = "battery.length_mismatch";
    public const string BatteryOutOfRange = "battery.out_of_range";

    // staleness
    public const string StalenessFieldStale = "staleness.field_stale";
    public const string StalenessFieldLive = "staleness.field_live";

    // connection
    public const string ConnectionStateChanged = "connection.state_changed";
    public const string ConnectivityShortPayload = "connectivity.short_payload";
    public const string DiscoveryAnomaly = "discovery.anomaly";

    // lifecycle / diagnostics
    public const string AppStarted = "app.started";
    public const string AppStopping = "app.stopping";
    public const string AdapterUnavailable = "adapter.unavailable";
    public const string AdapterAvailable = "adapter.available";
    public const string DiagnosticsExported = "diagnostics.exported";
    public const string DiagnosticsExportFailed = "diagnostics.export_failed";
}
