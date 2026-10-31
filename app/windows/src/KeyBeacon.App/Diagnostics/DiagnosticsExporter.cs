using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using KeyBeacon.App.Ble;
using KeyBeacon.Core;

namespace KeyBeacon.App.Diagnostics;

/// <summary>
/// Context the exporter captures about the current runtime for environment.json.
/// </summary>
public sealed record DiagnosticsContext(
    string AppVersion,
    string DetectedKbpVersion,
    string? BluetoothAdapter,
    IReadOnlyList<DiagnosticsKeyboard> Keyboards);

public sealed record DiagnosticsKeyboard(
    string Identifier,
    string? Name,
    string Shape,
    string ConnectionState,
    byte? CapabilityByte);

/// <summary>
/// Builds a single shareable .zip for issue reports (US6, FR-023/FR-025).
/// Bluetooth identifiers are hashed, device names masked by default; the user
/// may opt to include full names after reviewing what the bundle will contain.
/// </summary>
public sealed class DiagnosticsExporter
{
    private readonly string _logDirectory;

    public DiagnosticsExporter(string logDirectory)
    {
        _logDirectory = logDirectory;
    }

    /// <param name="includeFullNames">When false (default), device names are masked (FR-025).</param>
    public string Export(string targetDirectory, DiagnosticsContext context, bool includeFullNames)
    {
        Directory.CreateDirectory(targetDirectory);
        var stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
        var zipPath = Path.Combine(targetDirectory, $"keybeacon-diagnostics-{stamp}.zip");

        using var zip = ZipFile.Open(zipPath, ZipArchiveMode.Create);

        WriteEntry(zip, "environment.json", BuildEnvironmentJson(context, includeFullNames));
        WriteEntry(zip, "README.txt", ReadmeText);

        CopyLogs(zip);

        return zipPath;
    }

    private string BuildEnvironmentJson(DiagnosticsContext context, bool includeFullNames)
    {
        var env = new Dictionary<string, object?>
        {
            ["appVersion"] = context.AppVersion,
            ["osVersion"] = Environment.OSVersion.VersionString,
            ["architecture"] = RuntimeInformation.OSArchitecture.ToString(),
            ["dotnetRuntime"] = RuntimeInformation.FrameworkDescription,
            ["bluetoothAdapter"] = context.BluetoothAdapter,
            ["detectedKbpVersion"] = context.DetectedKbpVersion,
            ["keyboards"] = context.Keyboards.Select(k => new Dictionary<string, object?>
            {
                ["id"] = HashIdentifier(k.Identifier),
                ["name"] = includeFullNames ? k.Name : MaskName(k.Name),
                ["shape"] = k.Shape,
                ["connectionState"] = k.ConnectionState,
                ["capabilityByte"] = k.CapabilityByte is { } b ? $"0x{b:X2}" : null
            }).ToArray()
        };

        return JsonSerializer.Serialize(env, new JsonSerializerOptions { WriteIndented = true });
    }

    private void CopyLogs(ZipArchive zip)
    {
        if (!Directory.Exists(_logDirectory)) return;

        foreach (var log in Directory.EnumerateFiles(_logDirectory, "*.log"))
        {
            var entry = zip.CreateEntry(Path.Combine("logs", Path.GetFileName(log)), CompressionLevel.Optimal);
            using var entryStream = entry.Open();
            // Open shared so an in-use rolling file can still be copied.
            using var source = new FileStream(log, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            source.CopyTo(entryStream);
        }
    }

    private static void WriteEntry(ZipArchive zip, string name, string content)
    {
        var entry = zip.CreateEntry(name, CompressionLevel.Optimal);
        using var writer = new StreamWriter(entry.Open(), new UTF8Encoding(false));
        writer.Write(content);
    }

    /// <summary>Stable, non-reversible identifier so maintainers can correlate without exposing the raw id.</summary>
    internal static string HashIdentifier(string identifier)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(identifier));
        return "sha256:" + Convert.ToHexString(bytes.AsSpan(0, 6));
    }

    /// <summary>Keeps the first token plus a length hint (e.g. "Corne-***(12)").</summary>
    internal static string? MaskName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return name;
        var token = name.Split(new[] { ' ', '-', '_' }, 2)[0];
        return $"{token}-***({name.Length})";
    }

    private const string ReadmeText = """
        KeyBeacon diagnostics bundle
        ============================

        This archive helps maintainers diagnose an issue without accessing your
        hardware. It contains:
          - environment.json : app / OS / .NET versions, detected KBP protocol
            version, Bluetooth adapter summary, and a keyboard summary.
          - logs/            : recent rolling diagnostic logs.

        Privacy: Bluetooth addresses and device identifiers are hashed, not
        included verbatim. Keyboard device names are masked by default; if you
        chose "include full names", they appear in environment.json. Review the
        contents before sharing publicly.

        ----

        KeyBeacon 诊断包
        ================

        本压缩包帮助维护者在无需访问你硬件的情况下定位问题，包含：
          - environment.json：应用/操作系统/.NET 版本、检测到的 KBP 协议版本、
            蓝牙适配器摘要与键盘摘要。
          - logs/：近期滚动诊断日志。

        隐私：蓝牙地址与设备标识符经哈希处理，不以明文包含；键盘设备名默认打码。
        若你选择"包含完整设备名"，其将出现在 environment.json 中。公开分享前请
        先审阅内容。
        """;
}
