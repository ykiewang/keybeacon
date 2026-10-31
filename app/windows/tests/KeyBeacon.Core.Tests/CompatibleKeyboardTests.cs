using KeyBeacon.Core;
using Xunit;

namespace KeyBeacon.Core.Tests;

public class CompatibleKeyboardTests
{
    [Fact]
    public void DisplayName_UsesDeviceNameWhenPresent()
    {
        var kb = new CompatibleKeyboard("dev-1", "Corne", BleConnectionState.Connected, true);
        Assert.Equal("Corne", kb.DisplayName);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void DisplayName_FallsBackWhenMissingOrBlank(string? name)
    {
        var kb = new CompatibleKeyboard("0123456789abcdef", name, BleConnectionState.Connected, true);
        Assert.Equal("Keyboard 01234567", kb.DisplayName);
    }

    [Fact]
    public void DisplayName_ShortIdentifier_UsesWholeIdentifier()
    {
        var kb = new CompatibleKeyboard("abc", null, BleConnectionState.Connected, true);
        Assert.Equal("Keyboard abc", kb.DisplayName);
    }

    [Fact]
    public void IsCompatibleServices_TrueOnlyWithKeyBeaconService()
    {
        Assert.True(CompatibleKeyboard.IsCompatibleServices(new[] { KbpUuids.Service }));
        Assert.False(CompatibleKeyboard.IsCompatibleServices(new[] { Guid.NewGuid() }));
        Assert.False(CompatibleKeyboard.IsCompatibleServices(Array.Empty<Guid>()));
    }

    [Fact]
    public void ResolveSelection_PrefersRememberedWhenPresent()
    {
        var selected = CompatibleKeyboard.ResolveSelection(new[] { "a", "b" }, "b");
        Assert.Equal("b", selected);
    }

    [Fact]
    public void ResolveSelection_IgnoresRememberedWhenGone()
    {
        Assert.Null(CompatibleKeyboard.ResolveSelection(new[] { "a", "b" }, "gone"));
    }

    [Fact]
    public void ResolveSelection_SoleCandidateIsSelected()
    {
        Assert.Equal("only", CompatibleKeyboard.ResolveSelection(new[] { "only" }, null));
    }

    [Fact]
    public void ResolveSelection_AmbiguousWithoutMemory_IsUndecided()
    {
        Assert.Null(CompatibleKeyboard.ResolveSelection(new[] { "a", "b" }, null));
    }
}
