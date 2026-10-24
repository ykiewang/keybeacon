using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using KeyBeacon.Core;
using Windows.Devices.Bluetooth.GenericAttributeProfile;

namespace KeyBeacon.Probe;

/// <summary>A single verification check result (contracts/probe-cli.md CLI-3).</summary>
public sealed class CheckResult
{
    public bool Pass { get; set; }
    public string? Detail { get; set; }
    public long? ElapsedMs { get; set; }
    public Dictionary<string, object?> Data { get; } = new();
}

/// <summary>Full run log serialised to JSON.</summary>
public sealed class ProbeReport
{
    public string Timestamp { get; set; } = DateTimeOffset.UtcNow.ToString("O");
    public Dictionary<string, object?> Host { get; } = new();
    public Dictionary<string, CheckResult> Checks { get; } = new();
    public string Verdict { get; set; } = "PASS";
}

/// <summary>
/// Executes checks P1–P6 (research.md §2). P1–P5 are blocking: any failure
/// flips the verdict to FAIL and maps to exit code 1. P6 only records the
/// observed timeout behaviour and never fails the verdict on its own.
/// </summary>
public sealed class ProbeRunner
{
    private readonly ProbeOptions _options;

    public ProbeRunner(ProbeOptions options)
    {
        _options = options;
    }

    public async Task<ProbeReport> RunAsync(CancellationToken ct = default)
    {
        var report = new ProbeReport();
        report.Host["os_version"] = Environment.OSVersion.VersionString;
        report.Host["arch"] = System.Runtime.InteropServices.RuntimeInformation.OSArchitecture.ToString();
        report.Host["dotnet"] = Environment.Version.ToString();

        await using var ble = new BleProbe(_options.Timeout, Trace);

        // P1 — MTA threading: if we reach here without hanging, the apartment is correct.
        report.Checks["p1_mta"] = new CheckResult
        {
            Pass = Thread.CurrentThread.GetApartmentState() == ApartmentState.MTA,
            Detail = $"apartment={Thread.CurrentThread.GetApartmentState()}"
        };

        // P2 — enumerate connected devices.
        var enumerate = new CheckResult();
        report.Checks["p2_enumerate"] = enumerate;
        List<DiscoveredDevice> devices;
        var sw = Stopwatch.StartNew();
        try
        {
            devices = (await ble.EnumerateConnectedAsync(ct)).ToList();
            enumerate.ElapsedMs = sw.ElapsedMilliseconds;
            enumerate.Pass = devices.Count > 0;
            enumerate.Data["devices"] = devices.Select(d => new { id = d.Id, name = d.Name }).ToArray();
            if (devices.Count == 0) enumerate.Detail = "no connected BLE devices";
        }
        catch (Exception ex)
        {
            enumerate.ElapsedMs = sw.ElapsedMilliseconds;
            enumerate.Pass = false;
            enumerate.Detail = ex.Message;
            report.Verdict = "FAIL";
            return report;
        }

        if (devices.Count == 0)
        {
            throw new PrerequisiteException("no connected BLE keyboard found");
        }

        // P4 — services + classify. (Done before P3 so we can pick a supported target.)
        var servicesCheck = new CheckResult();
        report.Checks["p4_services"] = servicesCheck;

        string targetId = _options.DeviceId ?? devices[0].Id;
        KbpCharacteristics? chars = null;
        sw.Restart();
        try
        {
            var services = await ble.GetServicesAsync(targetId, ct);
            servicesCheck.ElapsedMs = sw.ElapsedMilliseconds;

            var classification = KbpUuids.Classify(services.Select(s => s.Uuid));
            servicesCheck.Data["classify"] = classification.ToString();

            if (_options.DeviceId is null && classification != KbpClassification.Supported)
            {
                // Auto-pick the first supported device instead of devices[0].
                foreach (var candidate in devices)
                {
                    var candidateServices = await ble.GetServicesAsync(candidate.Id, ct);
                    if (KbpUuids.Classify(candidateServices.Select(s => s.Uuid)) == KbpClassification.Supported)
                    {
                        targetId = candidate.Id;
                        services = candidateServices;
                        classification = KbpClassification.Supported;
                        servicesCheck.Data["classify"] = classification.ToString();
                        break;
                    }
                }
            }

            servicesCheck.Data["device_id"] = targetId;

            if (classification == KbpClassification.Supported)
            {
                chars = await BleProbe.FindKbpCharacteristicsAsync(services, _options.Timeout, ct);
                servicesCheck.Data["chars"] = chars.PresentNames();
                servicesCheck.Pass = chars.HasStatus;
                if (!chars.HasStatus) servicesCheck.Detail = "AA1 (status) missing";
            }
            else
            {
                servicesCheck.Pass = false;
                servicesCheck.Detail = $"classification={classification}";
            }
        }
        catch (Exception ex)
        {
            servicesCheck.ElapsedMs = sw.ElapsedMilliseconds;
            servicesCheck.Pass = false;
            servicesCheck.Detail = ex.Message;
        }

        // P3 — GATT coexistence with HID. Operator-confirmed: keep the session open briefly.
        var coexist = new CheckResult
        {
            Pass = chars is not null,
            Detail = chars is null
                ? "skipped: no supported keyboard"
                : "GATT session established; confirm typing is uninterrupted (operator-confirmed)"
        };
        report.Checks["p3_hid_coexist"] = coexist;

        // P5 — read + subscribe.
        var readSub = new CheckResult();
        report.Checks["p5_read_subscribe"] = readSub;
        if (chars?.Status is { } statusChar)
        {
            sw.Restart();
            try
            {
                var initial = await ble.ReadAsync(statusChar, ct);
                var notify = await ble.SubscribeFirstNotifyAsync(statusChar, ct);
                readSub.ElapsedMs = sw.ElapsedMilliseconds;

                var payload = notify ?? initial;
                if (payload is not null)
                {
                    readSub.Data["first_notify_hex"] = Convert.ToHexString(payload);
                    var parsed = KeyboardStatus.Parse(payload);
                    readSub.Data["parsed_layer"] = parsed?.LayerName;
                    readSub.Data["mods"] = parsed is null ? null : FormatMods(parsed);
                    readSub.Pass = parsed is not null;
                    if (parsed is null) readSub.Detail = "payload did not parse";
                }
                else
                {
                    readSub.Pass = false;
                    readSub.Detail = "no value from read or notify within timeout";
                }
            }
            catch (Exception ex)
            {
                readSub.ElapsedMs = sw.ElapsedMilliseconds;
                readSub.Pass = false;
                readSub.Detail = ex.Message;
            }
        }
        else
        {
            readSub.Pass = false;
            readSub.Detail = "skipped: AA1 not available";
        }

        // P6 — stale-connection timeout observation (non-blocking).
        var observedMax = report.Checks.Values.Select(c => c.ElapsedMs ?? 0).DefaultIfEmpty(0).Max();
        report.Checks["p6_stale_timeout"] = new CheckResult
        {
            Pass = true,
            Detail = "non-blocking; records observed per-call latency",
            Data = { ["observed_max_ms"] = observedMax, ["timeout_ms"] = (long)_options.Timeout.TotalMilliseconds }
        };

        var blocking = new[] { "p1_mta", "p2_enumerate", "p3_hid_coexist", "p4_services", "p5_read_subscribe" };
        report.Verdict = blocking.All(k => report.Checks.TryGetValue(k, out var c) && c.Pass) ? "PASS" : "FAIL";
        return report;
    }

    private static string FormatMods(KeyboardStatus status)
    {
        var active = new List<string>(4);
        if (status.ShiftActive) active.Add("shift");
        if (status.ControlActive) active.Add("control");
        if (status.AltActive) active.Add("alt");
        if (status.GuiActive) active.Add("gui");
        return active.Count == 0 ? "none" : string.Join("+", active);
    }

    private void Trace(string message)
    {
        if (_options.Verbose) Console.Error.WriteLine($"[probe] {message}");
    }
}
