using System.Text;
using KeyBeacon.Core;
using Xunit;

namespace KeyBeacon.Core.Tests;

public class KeyboardStatusTests
{
    private static byte[] Payload(byte index, byte mods, string? name)
    {
        var nameBytes = string.IsNullOrEmpty(name) ? Array.Empty<byte>() : Encoding.UTF8.GetBytes(name);
        var buf = new byte[2 + nameBytes.Length];
        buf[0] = index;
        buf[1] = mods;
        nameBytes.CopyTo(buf, 2);
        return buf;
    }

    [Fact]
    public void Parse_TooShort_ReturnsNull()
    {
        Assert.Null(KeyboardStatus.Parse(ReadOnlySpan<byte>.Empty));
        Assert.Null(KeyboardStatus.Parse(new byte[] { 0x02 }));
    }

    [Theory]
    [InlineData(0, "Base")]
    [InlineData(2, "Nav")]
    [InlineData(5, "Symbols")]
    [InlineData(127, "Adjust")]
    public void Parse_ReadsLayerIndexAndName(byte index, string name)
    {
        var status = KeyboardStatus.Parse(Payload(index, 0, name));

        Assert.NotNull(status);
        Assert.Equal(index, status!.LayerIndex);
        Assert.Equal(name, status.LayerName);
        Assert.True(status.Connected);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(3)]
    public void Parse_EmptyOrMissingName_FallsBackToLayerIndex(byte index)
    {
        Assert.Equal($"L{index}", KeyboardStatus.Parse(Payload(index, 0, ""))!.LayerName);
        Assert.Equal($"L{index}", KeyboardStatus.Parse(new byte[] { index, 0 })!.LayerName);
    }

    [Fact]
    public void Parse_InvalidUtf8_FallsBackToLayerIndex()
    {
        var status = KeyboardStatus.Parse(new byte[] { 4, 0, 0xC3, 0x28 });

        Assert.NotNull(status);
        Assert.Equal("L4", status!.LayerName);
    }

    [Theory]
    [InlineData(0x02, true, false, false, false)]  // left shift
    [InlineData(0x20, true, false, false, false)]  // right shift
    [InlineData(0x22, true, false, false, false)]  // both shifts
    [InlineData(0x01, false, true, false, false)]  // left ctrl
    [InlineData(0x10, false, true, false, false)]  // right ctrl
    [InlineData(0x04, false, false, true, false)]  // left alt
    [InlineData(0x40, false, false, true, false)]  // right alt
    [InlineData(0x08, false, false, false, true)]  // left gui
    [InlineData(0x80, false, false, false, true)]  // right gui
    [InlineData(0x00, false, false, false, false)]
    [InlineData(0xFF, true, true, true, true)]
    public void ModifierIndicators_MergeLeftAndRight(byte mods, bool shift, bool ctrl, bool alt, bool gui)
    {
        var status = KeyboardStatus.Parse(Payload(0, mods, "Base"))!;

        Assert.Equal(shift, status.ShiftActive);
        Assert.Equal(ctrl, status.ControlActive);
        Assert.Equal(alt, status.AltActive);
        Assert.Equal(gui, status.GuiActive);
    }

    [Fact]
    public void Disconnected_HasNoLiveReading()
    {
        Assert.False(KeyboardStatus.Disconnected.Connected);
        Assert.Equal(string.Empty, KeyboardStatus.Disconnected.LayerName);
        Assert.False(KeyboardStatus.Disconnected.ShiftActive);
    }
}
