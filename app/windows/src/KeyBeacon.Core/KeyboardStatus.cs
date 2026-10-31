using System;
using System.Text;

namespace KeyBeacon.Core;

/// <summary>
/// KBP 1.0 status payload (service <see cref="KbpUuids.Status"/>).
/// Wire contract: protocol/README.md §4. Byte 0 = layer index, byte 1 =
/// HID modifier mask, bytes 2..n = UTF-8 layer name.
/// </summary>
public sealed record KeyboardStatus(byte LayerIndex, string LayerName, byte Mods, bool Connected)
{
    public static readonly KeyboardStatus Disconnected = new(0, string.Empty, 0, false);

    /// <summary>Left/right HID bit pairs: 0x22 Shift, 0x11 Control, 0x44 Alt, 0x88 Gui.</summary>
    public bool ShiftActive => (Mods & 0x22) != 0;
    public bool ControlActive => (Mods & 0x11) != 0;
    public bool AltActive => (Mods & 0x44) != 0;
    public bool GuiActive => (Mods & 0x88) != 0;

    public static KeyboardStatus? Parse(ReadOnlySpan<byte> data)
    {
        if (data.Length < 2) return null;

        var index = data[0];
        var mods = data[1];

        var name = data.Length > 2
            ? DecodeUtf8(data[2..])
            : string.Empty;

        return new KeyboardStatus(
            index,
            name.Length == 0 ? $"L{index}" : name,
            mods,
            Connected: true);
    }

    private static string DecodeUtf8(ReadOnlySpan<byte> bytes)
    {
        try
        {
            return new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true)
                .GetString(bytes);
        }
        catch (ArgumentException)
        {
            return string.Empty;
        }
    }
}
