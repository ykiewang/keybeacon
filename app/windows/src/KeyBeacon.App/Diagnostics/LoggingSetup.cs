using System;
using System.IO;
using Microsoft.Extensions.Logging;
using Serilog;
using Serilog.Events;
using Serilog.Extensions.Logging;

namespace KeyBeacon.App.Diagnostics;

/// <summary>
/// Rolling-file logging bootstrap (FR-022, FR-024).
/// Files live under <c>%LOCALAPPDATA%\KeyBeacon\logs</c>, one file per day,
/// capped by size and retained count so history survives restarts without
/// growing without bound.
/// </summary>
public sealed class LoggingSetup : IDisposable
{
    public const string LogFileName = "keybeacon-.log";
    private const long FileSizeLimitBytes = 10 * 1024 * 1024;
    private const int RetainedFileCount = 7;

    private readonly Serilog.Core.Logger _serilog;
    private readonly ILoggerFactory _factory;

    private LoggingSetup(Serilog.Core.Logger serilog, ILoggerFactory factory, string logDirectory)
    {
        _serilog = serilog;
        _factory = factory;
        LogDirectory = logDirectory;
    }

    public ILoggerFactory Factory => _factory;

    public string LogDirectory { get; }

    public static string DefaultLogDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "KeyBeacon",
        "logs");

    /// <param name="verbose">Verbose mode adds raw payload hex and successful parse paths (FR-024).</param>
    public static LoggingSetup Create(bool verbose, string? logDirectory = null)
    {
        var dir = logDirectory ?? DefaultLogDirectory;
        Directory.CreateDirectory(dir);

        var config = new LoggerConfiguration()
            .MinimumLevel.Is(verbose ? LogEventLevel.Debug : LogEventLevel.Information)
            .Enrich.WithProperty("subsystem", DiagnosticsLogger.Subsystem)
            .WriteTo.File(
                Path.Combine(dir, LogFileName),
                rollingInterval: RollingInterval.Day,
                fileSizeLimitBytes: FileSizeLimitBytes,
                rollOnFileSizeLimit: true,
                retainedFileCountLimit: RetainedFileCount,
                shared: false,
                outputTemplate:
                    "{Timestamp:yyyy-MM-ddTHH:mm:ss.fffzzz} [{Level:u3}] {subsystem}/{SourceContext} {Message:lj}{NewLine}{Exception}");

        var serilog = config.CreateLogger();
        var factory = new SerilogLoggerFactory(serilog, dispose: false);
        return new LoggingSetup(serilog, factory, dir);
    }

    public void Dispose()
    {
        _factory.Dispose();
        _serilog.Dispose();
    }
}
