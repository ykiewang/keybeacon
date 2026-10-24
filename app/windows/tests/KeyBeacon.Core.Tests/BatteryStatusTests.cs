using KeyBeacon.Core;
using Xunit;

namespace KeyBeacon.Core.Tests;

public class BatteryStatusTests
{
    [Theory]
    [InlineData(0, 0)]
    [InlineData(1, 1)]
    [InlineData(50, 50)]
    [InlineData(100, 100)]
    public void Parse_Overall_Percent(byte raw, int expected)
    {
        var status = BatteryStatus.Parse(new[] { raw }, isSplit: false);

        Assert.NotNull(status);
        var overall = Assert.IsType<BatteryStatus.Kind.Overall>(status!.Shape);
        Assert.True(overall.Reading.IsPercent);
        Assert.Equal(expected, overall.Reading.Percent);
    }

    [Fact]
    public void Parse_Overall_Sentinel255_IsUnavailableNotZero()
    {
        var status = BatteryStatus.Parse(new byte[] { 255 }, isSplit: false)!;
        var overall = Assert.IsType<BatteryStatus.Kind.Overall>(status.Shape);

        Assert.False(overall.Reading.IsPercent);
        Assert.Null(overall.Reading.Percent);
        Assert.False(overall.Reading.OutOfRange);
    }

    [Theory]
    [InlineData(101)]
    [InlineData(200)]
    [InlineData(254)]
    public void Parse_Overall_ReservedValues_AreOutOfRange(byte raw)
    {
        var status = BatteryStatus.Parse(new byte[] { raw }, isSplit: false)!;
        var overall = Assert.IsType<BatteryStatus.Kind.Overall>(status.Shape);

        Assert.False(overall.Reading.IsPercent);
        Assert.Null(overall.Reading.Percent);
        Assert.True(overall.Reading.OutOfRange);
    }

    [Fact]
    public void Parse_Split_DecodesBothHalves()
    {
        var status = BatteryStatus.Parse(new byte[] { 80, 255 }, isSplit: true)!;
        var split = Assert.IsType<BatteryStatus.Kind.Split>(status.Shape);

        Assert.Equal(80, split.Left.Percent);
        Assert.Null(split.Right.Percent);
    }

    [Theory]
    [InlineData(new byte[] { }, false)]
    [InlineData(new byte[] { 50, 60 }, false)]   // non-split must be 1 byte (C-B1)
    [InlineData(new byte[] { 50 }, true)]        // split must be 2 bytes (C-B2)
    [InlineData(new byte[] { 50, 60, 70 }, true)]
    public void Parse_LengthMismatch_ReturnsNull(byte[] data, bool isSplit)
    {
        Assert.Null(BatteryStatus.Parse(data, isSplit));
    }
}
