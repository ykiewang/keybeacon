using System;

namespace KeyBeacon.Core;

public enum KbpClassification
{
    Supported,
    UnsupportedVersion,
    NotAKeyboard
}

public static class KbpUuids
{
    public static readonly Guid Service = new("aa440aa0-f5ed-4c48-84a1-8062d20d3d55");
    public static readonly Guid Status = new("aa440aa1-f5ed-4c48-84a1-8062d20d3d55");
    public static readonly Guid Connectivity = new("aa440aa2-f5ed-4c48-84a1-8062d20d3d55");
    public static readonly Guid Battery = new("aa440aa3-f5ed-4c48-84a1-8062d20d3d55");

    private const string FamilySuffix = "-f5ed-4c48-84a1-8062d20d3d55";

    private static readonly Guid[] SupportedServices = { Service };

    public static bool IsKeyBeaconFamily(Guid uuid) =>
        uuid.ToString("D").EndsWith(FamilySuffix, StringComparison.OrdinalIgnoreCase);

    public static KbpClassification Classify(IEnumerable<Guid>? discoveredServices)
    {
        if (discoveredServices is null) return KbpClassification.NotAKeyboard;

        var services = discoveredServices as ICollection<Guid> ?? discoveredServices.ToList();
        foreach (var supported in SupportedServices)
        {
            if (services.Contains(supported)) return KbpClassification.Supported;
        }

        return services.Any(IsKeyBeaconFamily)
            ? KbpClassification.UnsupportedVersion
            : KbpClassification.NotAKeyboard;
    }
}
