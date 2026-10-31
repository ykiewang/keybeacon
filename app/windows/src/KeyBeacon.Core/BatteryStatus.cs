using System;

namespace KeyBeacon.Core;

/// <summary>
/// Parsed KBP 1.1 Battery payload.
/// Wire contract: protocol/README.md §14.4.
/// Length rules: non-split must be exactly 1 byte (C-B1); split must be
/// exactly 2 bytes <c>[left, right]</c> (C-B2).
/// </summary>
public sealed record BatteryStatus(BatteryStatus.Kind Shape)
{
    /// <summary>Single battery byte decoded per §14.4.2.</summary>
    public readonly record struct BatteryReading(byte RawByte, bool OutOfRange)
    {
        public bool IsPercent => !OutOfRange && RawByte <= 100;
        public int? Percent => IsPercent ? RawByte : null;

        public static BatteryReading FromByte(byte b) => b switch
        {
            <= 100 => new BatteryReading(b, false),
            255 => new BatteryReading(b, false),
            _ => new BatteryReading(b, true)
        };
    }

    public abstract record Kind
    {
        public sealed record Overall(BatteryReading Reading) : Kind;
        public sealed record Split(BatteryReading Left, BatteryReading Right) : Kind;
    }

    /// <summary>
    /// Decodes a Battery payload using the Connectivity-advertised
    /// <paramref name="isSplit"/>. Returns null on length mismatch.
    /// </summary>
    public static BatteryStatus? Parse(ReadOnlySpan<byte> data, bool isSplit)
    {
        if (isSplit)
        {
            if (data.Length != 2) return null;
            return new BatteryStatus(new Kind.Split(
                BatteryReading.FromByte(data[0]),
                BatteryReading.FromByte(data[1])));
        }

        if (data.Length != 1) return null;
        return new BatteryStatus(new Kind.Overall(BatteryReading.FromByte(data[0])));
    }
}
