using System;

namespace KeyBeacon.Core;

/// <summary>
/// Parsed KBP 1.1 Connectivity payload (7 bytes).
/// Wire contract: protocol/README.md §14.3.
/// </summary>
public sealed record ConnectivityStatus(
    CapabilityMatrix Capability,
    ConnectivityStatus.Link HostState,
    ConnectivityStatus.ProfileData Profile,
    ConnectivityStatus.SplitLinkFlags SplitFlags,
    ConnectivityStatus.OutputEndpoint Output,
    ConnectivityStatus.ChargingFlags Charging,
    int TrailingBytesIgnored)
{
    public enum DisconnectReason : byte
    {
        Unknown = 0,
        Explicit = 1,
        Timeout = 2,
        Reserved = 3
    }

    /// <summary><c>host_state</c> (byte 1).</summary>
    public sealed record Link(bool Connected, DisconnectReason LastDisconnectReason, byte ReservedBits3To7)
    {
        public static Link FromByte(byte b) => new(
            Connected: (b & 0x01) != 0,
            LastDisconnectReason: (DisconnectReason)((b >> 1) & 0x03),
            ReservedBits3To7: (byte)((b >> 3) & 0x1F));
    }

    /// <summary><c>profile_index</c> + <c>profile_max_slots</c> (bytes 2–3).</summary>
    public sealed record ProfileData(byte Index, bool IsOpen, byte MaxSlots)
    {
        /// <summary>Index is 1-based; 0 means "field not applicable".</summary>
        public bool OutOfRange => Index != 0 && MaxSlots != 0 && Index > MaxSlots;

        public static ProfileData FromBytes(byte b2, byte b3) => new(
            Index: (byte)(b2 & 0x7F),
            IsOpen: (b2 & 0x80) != 0,
            MaxSlots: b3);
    }

    /// <summary><c>split_link_flags</c> (byte 4).</summary>
    public sealed record SplitLinkFlags(bool LeftOnline, bool RightOnline, byte ReservedBits2To7)
    {
        public static SplitLinkFlags FromByte(byte b) => new(
            LeftOnline: (b & 0x01) != 0,
            RightOnline: (b & 0x02) != 0,
            ReservedBits2To7: (byte)((b >> 2) & 0x3F));
    }

    public enum OutputKind : byte
    {
        Unknown = 0,
        Usb = 1,
        Ble = 2,
        Reserved = 3
    }

    /// <summary>
    /// <c>output_endpoint</c> (byte 5). <see cref="RawByte"/> preserves reserved
    /// values losslessly, matching the reference implementation.
    /// </summary>
    public readonly record struct OutputEndpoint(OutputKind Kind, byte RawByte)
    {
        public static OutputEndpoint FromByte(byte b) => new(
            b switch
            {
                0 => OutputKind.Unknown,
                1 => OutputKind.Usb,
                2 => OutputKind.Ble,
                _ => OutputKind.Reserved
            },
            b);

        public override string ToString() => Kind switch
        {
            OutputKind.Unknown => "unknown",
            OutputKind.Usb => "usb",
            OutputKind.Ble => "ble",
            _ => $"reserved(0x{RawByte:X2})"
        };
    }

    /// <summary><c>charging_flags</c> (byte 6).</summary>
    public sealed record ChargingFlags(bool LeftCharging, bool RightCharging, byte ReservedBits2To7)
    {
        public static ChargingFlags FromByte(byte b) => new(
            LeftCharging: (b & 0x01) != 0,
            RightCharging: (b & 0x02) != 0,
            ReservedBits2To7: (byte)((b >> 2) & 0x3F));
    }

    /// <summary>
    /// Decodes a Connectivity payload. Returns null when shorter than 7 bytes
    /// (C-C1). Bytes beyond offset 6 are ignored and counted (C-C2).
    /// </summary>
    public static ConnectivityStatus? Parse(ReadOnlySpan<byte> data)
    {
        if (data.Length < 7) return null;

        return new ConnectivityStatus(
            Capability: CapabilityMatrix.FromByte(data[0]),
            HostState: Link.FromByte(data[1]),
            Profile: ProfileData.FromBytes(data[2], data[3]),
            SplitFlags: SplitLinkFlags.FromByte(data[4]),
            Output: OutputEndpoint.FromByte(data[5]),
            Charging: ChargingFlags.FromByte(data[6]),
            TrailingBytesIgnored: data.Length - 7);
    }

    /// <summary>Raw payload hex, for diagnostics on parse/validation failures.</summary>
    public static string ToHex(ReadOnlySpan<byte> data) => Convert.ToHexString(data);
}
