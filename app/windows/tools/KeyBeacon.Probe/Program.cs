using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;

namespace KeyBeacon.Probe;

/// <summary>
/// CLI entry point.
/// A hard WinRT requirement: the process must run in the multi-threaded
/// apartment or every GATT async call hangs forever (research.md D2).
/// </summary>
public static class Program
{
    [MTAThread]
    public static int Main(string[] args)
    {
        ProbeOptions options;
        try
        {
            options = ProbeOptions.Parse(args);
        }
        catch (ArgumentException ex)
        {
            Console.Error.WriteLine($"error: {ex.Message}");
            Console.Error.WriteLine(ProbeOptions.Usage);
            return ExitCodes.BadArguments;
        }

        if (options.ShowHelp)
        {
            Console.WriteLine(ProbeOptions.Usage);
            return ExitCodes.Ok;
        }

        try
        {
            var runner = new ProbeRunner(options);
            var report = runner.RunAsync().GetAwaiter().GetResult();
            var json = JsonSerializer.Serialize(report, JsonOptions);

            if (options.JsonPath is { Length: > 0 } path)
            {
                File.WriteAllText(path, json);
                Console.WriteLine($"run log written to {path}");
            }
            else
            {
                Console.WriteLine(json);
            }

            return report.Verdict == "PASS" ? ExitCodes.Ok : ExitCodes.BlockedCheckFailed;
        }
        catch (PrerequisiteException ex)
        {
            Console.Error.WriteLine($"environment error: {ex.Message}");
            return ExitCodes.EnvironmentError;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"unexpected error: {ex.GetType().Name}: {ex.Message}");
            return ExitCodes.EnvironmentError;
        }
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower
    };
}

public static class ExitCodes
{
    /// <summary>All blocking checks (P1–P5) passed; the gate is open.</summary>
    public const int Ok = 0;

    /// <summary>A blocking check failed; consult research.md §3 for the fallback path.</summary>
    public const int BlockedCheckFailed = 1;

    /// <summary>No adapter, no connected keyboard, or insufficient permissions.</summary>
    public const int EnvironmentError = 2;

    public const int BadArguments = 3;
}

public sealed class PrerequisiteException : Exception
{
    public PrerequisiteException(string message) : base(message) { }
}

/// <summary>Parsed command line (contracts/probe-cli.md CLI-1).</summary>
public sealed class ProbeOptions
{
    public const string Usage = """
        KeyBeacon.Probe — Phase 0 WinRT feasibility probe

        Usage:
          KeyBeacon.Probe [--device <DeviceInformation.Id>] [--timeout <seconds>]
                          [--json <path>] [--verbose] [--help]

        Options:
          --device    Target device id; defaults to the first supported keyboard found.
          --timeout   Per-call GATT timeout in seconds (default 10). Used to measure P6.
          --json      Write the run log to this path instead of stdout.
          --verbose   Print per-call timings and raw payload hex.
          --help      Show this text.
        """;

    public string? DeviceId { get; private set; }
    public TimeSpan Timeout { get; private set; } = TimeSpan.FromSeconds(10);
    public string? JsonPath { get; private set; }
    public bool Verbose { get; private set; }
    public bool ShowHelp { get; private set; }

    public static ProbeOptions Parse(IReadOnlyList<string> args)
    {
        var options = new ProbeOptions();

        for (var i = 0; i < args.Count; i++)
        {
            switch (args[i])
            {
                case "--help" or "-h":
                    options.ShowHelp = true;
                    return options;

                case "--verbose":
                    options.Verbose = true;
                    break;

                case "--device":
                    options.DeviceId = RequireValue(args, ref i, "--device");
                    break;

                case "--timeout":
                    var raw = RequireValue(args, ref i, "--timeout");
                    if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds)
                        || seconds <= 0)
                    {
                        throw new ArgumentException($"invalid --timeout value '{raw}'");
                    }
                    options.Timeout = TimeSpan.FromSeconds(seconds);
                    break;

                case "--json":
                    options.JsonPath = RequireValue(args, ref i, "--json");
                    break;

                default:
                    throw new ArgumentException($"unknown argument '{args[i]}'");
            }
        }

        return options;
    }

    private static string RequireValue(IReadOnlyList<string> args, ref int index, string name)
    {
        if (index + 1 >= args.Count) throw new ArgumentException($"{name} requires a value");
        var value = args[++index];
        if (value.StartsWith("--", StringComparison.Ordinal))
        {
            throw new ArgumentException($"{name} requires a value");
        }
        return value;
    }
}
