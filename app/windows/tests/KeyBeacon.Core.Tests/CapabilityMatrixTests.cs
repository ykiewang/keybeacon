using KeyBeacon.Core;
using Xunit;

namespace KeyBeacon.Core.Tests;

public class CapabilityMatrixTests
{
    [Theory]
    [InlineData(0x00, false, false, false, false, false, false, false)]
    [InlineData(0x01, true,  false, false, false, false, false, false)]
    [InlineData(0x02, false, true,  false, false, false, false, false)]
    [InlineData(0x04, false, false, true,  false, false, false, false)]
    [InlineData(0x10, false, false, false, true,  false, false, false)]
    [InlineData(0x20, false, false, false, false, true,  false, false)]
    [InlineData(0x40, false, false, false, false, false, true,  false)]
    [InlineData(0x80, false, false, false, false, false, false, false)]
    public void FromByte_DecodesEachBit(
        byte raw, bool isSplit, bool host, bool profile, bool output, bool leftCharging, bool rightCharging, bool reserved7Ignored)
    {
        _ = reserved7Ignored;
        var cap = CapabilityMatrix.FromByte(raw);

        Assert.Equal(isSplit, cap.IsSplit);
        Assert.Equal(host, cap.HasHostConnection);
        Assert.Equal(profile, cap.HasProfile);
        Assert.Equal(output, cap.HasOutputEndpoint);
        Assert.Equal(leftCharging, cap.HasLeftCharging);
        Assert.Equal(rightCharging, cap.HasRightCharging);
    }

    [Theory]
    [InlineData(0x00)]
    [InlineData(0x7F)]
    [InlineData(0x80)]
    [InlineData(0xFF)]
    [InlineData(0xA5)]
    public void ToByte_RoundTripsLosslessly_IncludingReservedBit(byte raw)
    {
        Assert.Equal(raw, CapabilityMatrix.FromByte(raw).ToByte());
    }

    [Theory]
    [InlineData(0x00, true)]   // nothing set
    [InlineData(0x01, true)]   // split only
    [InlineData(0x09, true)]   // split + split-link (IV-C1 ok)
    [InlineData(0x21, true)]   // split + left charging
    [InlineData(0x61, true)]   // split + left + right charging (IV-C3 ok)
    [InlineData(0x08, false)]  // split-link without split -> IV-C1 violated
    [InlineData(0x40, false)]  // right charging without split -> IV-C3 violated
    [InlineData(0x41, false)]  // split + right charging without left -> IV-C3 violated
    public void IsConsistent_EnforcesCrossFieldInvariants(byte raw, bool expected)
    {
        Assert.Equal(expected, CapabilityMatrix.FromByte(raw).IsConsistent);
    }

    [Fact]
    public void InconsistencyReason_NamesViolatedInvariant()
    {
        Assert.Equal("IV-C1:has_split_link_without_is_split", CapabilityMatrix.FromByte(0x08).InconsistencyReason());
        Assert.Equal("IV-C3:right_charging_without_split", CapabilityMatrix.FromByte(0x40).InconsistencyReason());
        Assert.Equal("IV-C3:right_charging_without_left", CapabilityMatrix.FromByte(0x41).InconsistencyReason());
        Assert.Null(CapabilityMatrix.FromByte(0x61).InconsistencyReason());
    }

    [Fact]
    public void Normalized_DropsViolatingBits()
    {
        var normalized = CapabilityMatrix.FromByte(0x48).Normalized();

        Assert.True(normalized.IsConsistent);
        Assert.False(normalized.HasSplitLink);
        Assert.False(normalized.HasRightCharging);
    }
}
