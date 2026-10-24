using KeyBeacon.Core;
using Xunit;

namespace KeyBeacon.Core.Tests;

public class KbpUuidsTests
{
    [Fact]
    public void Uuids_ShareFamilySuffix()
    {
        Assert.True(KbpUuids.IsKeyBeaconFamily(KbpUuids.Service));
        Assert.True(KbpUuids.IsKeyBeaconFamily(KbpUuids.Status));
        Assert.True(KbpUuids.IsKeyBeaconFamily(KbpUuids.Connectivity));
        Assert.True(KbpUuids.IsKeyBeaconFamily(KbpUuids.Battery));
    }

    [Fact]
    public void Family_AcceptsFutureMajorWithSameSuffix()
    {
        var futureMajor = Guid.Parse("aa440aa0-f5ed-4c48-84a1-8062d20d3d55");
        var otherMajor = Guid.Parse("bb550bb0-f5ed-4c48-84a1-8062d20d3d55");

        Assert.True(KbpUuids.IsKeyBeaconFamily(futureMajor));
        Assert.True(KbpUuids.IsKeyBeaconFamily(otherMajor));
    }

    [Fact]
    public void Family_RejectsUnrelatedUuid()
    {
        Assert.False(KbpUuids.IsKeyBeaconFamily(Guid.Parse("0000180f-0000-1000-8000-00805f9b34fb")));
    }

    [Fact]
    public void Classify_SupportedWhenServicePresent()
    {
        Assert.Equal(KbpClassification.Supported,
            KbpUuids.Classify(new[] { KbpUuids.Service, Guid.Parse("0000180f-0000-1000-8000-00805f9b34fb") }));
    }

    [Fact]
    public void Classify_UnsupportedVersionForFamilyWithoutSupportedMajor()
    {
        var futureMajor = Guid.Parse("bb550bb0-f5ed-4c48-84a1-8062d20d3d55");
        Assert.Equal(KbpClassification.UnsupportedVersion, KbpUuids.Classify(new[] { futureMajor }));
    }

    [Fact]
    public void Classify_NotAKeyboardWhenNothingMatches()
    {
        Assert.Equal(KbpClassification.NotAKeyboard, KbpUuids.Classify(new[] { Guid.NewGuid() }));
        Assert.Equal(KbpClassification.NotAKeyboard, KbpUuids.Classify(Array.Empty<Guid>()));
        Assert.Equal(KbpClassification.NotAKeyboard, KbpUuids.Classify(null));
    }
}
