using KeyBeacon.Core;
using Xunit;

namespace KeyBeacon.Core.Tests;

public class ConnectivityStatusTests
{
    private static byte[] Payload(params byte[] bytes) => bytes;

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    [InlineData(6)]
    public void Parse_ShorterThanSevenBytes_ReturnsNull(int length)
    {
        var data = new byte[length];
        Assert.Null(ConnectivityStatus.Parse(data));
    }

    [Fact]
    public void Parse_TrailingBytes_AreIgnoredAndCounted()
    {
        var status = ConnectivityStatus.Parse(Payload(0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xAA, 0xBB));

        Assert.NotNull(status);
        Assert.Equal(2, status!.TrailingBytesIgnored);
    }

    [Fact]
    public void Parse_Link_DecodesConnectedAndReason()
    {
        var status = ConnectivityStatus.Parse(Payload(0, 0b0000_0111, 0, 0, 0, 0, 0))!;

        Assert.True(status.HostState.Connected);
        Assert.Equal(ConnectivityStatus.DisconnectReason.Reserved, status.HostState.LastDisconnectReason);

        var timeout = ConnectivityStatus.Parse(Payload(0, 0b0000_0100, 0, 0, 0, 0, 0))!;
        Assert.False(timeout.HostState.Connected);
        Assert.Equal(ConnectivityStatus.DisconnectReason.Timeout, timeout.HostState.LastDisconnectReason);
    }

    [Fact]
    public void Parse_Profile_DecodesIndexOpenAndSlots()
    {
        var status = ConnectivityStatus.Parse(Payload(0, 0, 0x83, 0x05, 0, 0, 0))!;

        Assert.Equal(3, status.Profile.Index);
        Assert.True(status.Profile.IsOpen);
        Assert.Equal(5, status.Profile.MaxSlots);
    }

    [Fact]
    public void Profile_OutOfRange_Detected()
    {
        var ok = ConnectivityStatus.Parse(Payload(0, 0, 0x02, 0x05, 0, 0, 0))!;
        Assert.False(ok.Profile.OutOfRange);

        var bad = ConnectivityStatus.Parse(Payload(0, 0, 0x07, 0x05, 0, 0, 0))!;
        Assert.True(bad.Profile.OutOfRange);
    }

    [Theory]
    [InlineData(0x00, false, false)]
    [InlineData(0x01, true, false)]
    [InlineData(0x02, false, true)]
    [InlineData(0x03, true, true)]
    public void Parse_SplitFlags_DecodesHalves(byte raw, bool left, bool right)
    {
        var status = ConnectivityStatus.Parse(Payload(0, 0, 0, 0, raw, 0, 0))!;

        Assert.Equal(left, status.SplitFlags.LeftOnline);
        Assert.Equal(right, status.SplitFlags.RightOnline);
    }

    [Theory]
    [InlineData(0, ConnectivityStatus.OutputKind.Unknown)]
    [InlineData(1, ConnectivityStatus.OutputKind.Usb)]
    [InlineData(2, ConnectivityStatus.OutputKind.Ble)]
    [InlineData(7, ConnectivityStatus.OutputKind.Reserved)]
    public void Parse_OutputEndpoint_DecodesKindAndPreservesRaw(byte raw, ConnectivityStatus.OutputKind kind)
    {
        var status = ConnectivityStatus.Parse(Payload(0, 0, 0, 0, 0, raw, 0))!;

        Assert.Equal(kind, status.Output.Kind);
        Assert.Equal(raw, status.Output.RawByte);
    }

    [Theory]
    [InlineData(0x00, false, false)]
    [InlineData(0x01, true, false)]
    [InlineData(0x02, false, true)]
    [InlineData(0x03, true, true)]
    public void Parse_ChargingFlags_DecodesHalves(byte raw, bool left, bool right)
    {
        var status = ConnectivityStatus.Parse(Payload(0, 0, 0, 0, 0, 0, raw))!;

        Assert.Equal(left, status.Charging.LeftCharging);
        Assert.Equal(right, status.Charging.RightCharging);
    }

    [Fact]
    public void Parse_ReservedBits_ArePreservedForDiagnostics()
    {
        var status = ConnectivityStatus.Parse(Payload(0, 0xF8, 0, 0, 0xFC, 0, 0xFC))!;

        Assert.Equal(0x1F, status.HostState.ReservedBits3To7);
        Assert.Equal(0x3F, status.SplitFlags.ReservedBits2To7);
        Assert.Equal(0x3F, status.Charging.ReservedBits2To7);
    }
}
