using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using KeyBeacon.App.Ble;
using KeyBeacon.App.Diagnostics;
using KeyBeacon.App.Localization;
using KeyBeacon.App.Settings;
using KeyBeacon.App.Ui;
using KeyBeacon.Core;
using Microsoft.Extensions.Logging;

namespace KeyBeacon.App;

public partial class App : Application
{
    private LoggingSetup? _logging;
    private AppSettings _settings = new();
    private LocalizationService _loc = LocalizationService.FromPreference(UiCulturePreference.System);
    private KeyboardMonitor? _monitor;
    private TrayController? _tray;
    private FloatingPanel? _panel;
    private MainViewModel? _viewModel;
    private ILogger? _lifecycleLog;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            WriteFatal("appdomain", args.ExceptionObject as Exception);
        DispatcherUnhandledException += (_, args) =>
        {
            WriteFatal("dispatcher", args.Exception);
            args.Handled = true; // tray app: survive transient UI/BLE faults
        };
        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            WriteFatal("task", args.Exception);
            args.SetObserved();
        };

        try
        {
            _settings = AppSettings.Load();
            _loc = LocalizationService.FromPreference(_settings.UICulture);
            _logging = LoggingSetup.Create(_settings.VerboseLogging);
            _lifecycleLog = DiagnosticsLogger.For(_logging.Factory, DiagnosticsLogger.Categories.Connection);

            _viewModel = new MainViewModel(_loc);
            _panel = new FloatingPanel(_viewModel, _settings);
            _panel.Show();
            _panel.ApplyPlacement();

            _tray = new TrayController(_loc, _settings);
            _tray.ShowPanelRequested += (_, _) => ShowPanel();
            _tray.ReconnectRequested += (_, _) => _ = RunBleAsync(() => _monitor!.ReconnectAsync());
            _tray.QuitRequested += (_, _) => Shutdown();
            _tray.ExportDiagnosticsRequested += (_, _) => ExportDiagnostics();
            _tray.KeyboardSelected += (_, id) => OnKeyboardSelected(id);
            _tray.VerboseLoggingToggled += (_, enabled) => OnVerboseToggled(enabled);

            _monitor = new KeyboardMonitor(_logging.Factory, Post);
            _monitor.SnapshotChanged += (_, snapshot) => OnSnapshot(snapshot);
            _monitor.KeyboardsChanged += (_, list) => _tray!.UpdateKeyboards(list);

            _ = RunBleAsync(() => _monitor.StartAsync(_settings.SelectedKeyboardId));
        }
        catch (Exception ex)
        {
            WriteFatal("startup", ex);
            MessageBox.Show(
                $"KeyBeacon failed to start:\n\n{ex}",
                "KeyBeacon",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    /// <summary>
    /// Last-resort crash capture. Writes to the Serilog pipeline when available
    /// and always appends to a plain <c>crash.log</c> next to the rolling logs,
    /// so a startup/native failure can never vanish silently.
    /// </summary>
    private void WriteFatal(string phase, Exception? ex)
    {
        try { _lifecycleLog?.LogCritical(ex, "fatal phase={Phase}", phase); }
        catch { /* logging must never mask the original fault */ }

        try
        {
            var dir = LoggingSetup.DefaultLogDirectory;
            Directory.CreateDirectory(dir);
            File.AppendAllText(
                Path.Combine(dir, "crash.log"),
                $"{DateTimeOffset.Now:o} [{phase}] {ex}{Environment.NewLine}{Environment.NewLine}");
        }
        catch { /* nothing more we can do */ }
    }

    private void OnSnapshot(KeyboardSnapshot snapshot)
    {
        _viewModel!.Apply(snapshot);
        _tray!.SetTitle(snapshot.KeyboardDisplayName ?? _loc.Get("AppName"));

        // Re-anchor only when corner-pinned: content growth (e.g. battery rows
        // appearing) shifts a right/bottom-anchored panel. A free panel keeps the
        // user's dragged position.
        if (_settings.PinnedCorner is not null) _panel!.ApplyPlacement();
    }

    private void OnKeyboardSelected(string id)
    {
        _settings.SelectedKeyboardId = id;
        _settings.Save();
        _ = RunBleAsync(() => _monitor!.SelectKeyboardAsync(id));
    }

    private void OnVerboseToggled(bool enabled)
    {
        _settings.VerboseLogging = enabled;
        _settings.Save();

        // Rebuild the logging pipeline at the new level; the monitor keeps its
        // factory reference, so swap by restarting the sink.
        var old = _logging;
        _logging = LoggingSetup.Create(enabled);
        old?.Dispose();
        _lifecycleLog = DiagnosticsLogger.For(_logging.Factory, DiagnosticsLogger.Categories.Connection);
    }

    private void ExportDiagnostics()
    {
        var dialog = new ExportReviewWindow(_loc) { Owner = _panel };
        if (dialog.ShowDialog() != true) return;

        try
        {
            var exporter = new DiagnosticsExporter(_logging!.LogDirectory);
            var context = BuildDiagnosticsContext();
            var target = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            var path = exporter.Export(target, context, dialog.IncludeFullNames);

            _lifecycleLog?.LogInformation("{Event} path={Path}", DiagnosticEvents.DiagnosticsExported, path);
            MessageBox.Show(_loc.Format("Dialog_ExportDone", path).Replace("\\n", Environment.NewLine),
                _loc.Get("Dialog_ExportTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            _lifecycleLog?.LogWarning("{Event} error={Error}", DiagnosticEvents.DiagnosticsExportFailed, ex.Message);
            MessageBox.Show(_loc.Format("Dialog_ExportFailed", ex.Message),
                _loc.Get("Dialog_ExportTitle"), MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private DiagnosticsContext BuildDiagnosticsContext()
    {
        var snapshot = _monitor!.Current;
        var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "unknown";
        var kbpVersion = snapshot switch
        {
            { Capability: not null, Battery: not null } => "1.1(hasBattery)",
            { Capability: not null } => "1.1",
            { Status: not null } => "1.0",
            _ => "none"
        };

        var keyboards = snapshot.KeyboardDisplayName is null
            ? Array.Empty<DiagnosticsKeyboard>()
            : new[]
            {
                new DiagnosticsKeyboard(
                    _settings.SelectedKeyboardId ?? "",
                    snapshot.KeyboardDisplayName,
                    snapshot.Capability?.IsSplit == true ? "split" : "unibody",
                    snapshot.State.ToString(),
                    snapshot.Capability?.ToByte())
            };

        return new DiagnosticsContext(version, kbpVersion, DescribeAdapter(), keyboards);
    }

    private static string? DescribeAdapter() => "see logs"; // populated from Radio enumeration in the monitor if needed

    private void ShowPanel()
    {
        _panel!.Show();
        _panel.Activate();
    }

    private void Post(Action action) => Dispatcher.BeginInvoke(action, DispatcherPriority.Normal);

    private static Task RunBleAsync(Func<Task> work) => Task.Run(work);

    protected override void OnExit(ExitEventArgs e)
    {
        _lifecycleLog?.LogInformation(DiagnosticEvents.AppStopping);
        _tray?.Dispose();
        if (_monitor is not null) _monitor.DisposeAsync().AsTask().GetAwaiter().GetResult();
        _logging?.Dispose();
        base.OnExit(e);
    }
}
