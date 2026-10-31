using System;
using System.Collections.Generic;
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

    // Cached so a language switch can re-render the panel and keybords menu
    // with the new culture without waiting for the next BLE notification.
    private KeyboardSnapshot? _lastSnapshot;
    private IReadOnlyList<CompatibleKeyboard> _lastKeyboards = Array.Empty<CompatibleKeyboard>();

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
            _viewModel.SetDisplayMode(_settings.DisplayMode);
            _panel = new FloatingPanel(_viewModel, _settings);
            if (_settings.PanelVisible)
            {
                _panel.Show();
                _panel.ApplyPlacement();
            }

            BuildTray();

            _monitor = new KeyboardMonitor(_logging.Factory, Post);
            _monitor.SnapshotChanged += (_, snapshot) => OnSnapshot(snapshot);
            _monitor.KeyboardsChanged += (_, list) =>
            {
                _lastKeyboards = list;
                _tray!.UpdateKeyboards(list);
            };

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
    /// Creates the tray controller and wires its events. Extracted so a language
    /// switch can rebuild the menu with the new culture's labels without
    /// touching the monitor/panel wiring.
    /// </summary>
    private void BuildTray()
    {
        _tray = new TrayController(_loc, _settings);
        _tray.TogglePanelRequested += (_, _) => TogglePanel();
        _tray.ReconnectRequested += (_, _) => _ = RunBleAsync(() => _monitor!.ReconnectAsync());
        _tray.QuitRequested += (_, _) => Shutdown();
        _tray.ExportDiagnosticsRequested += (_, _) => ExportDiagnostics();
        _tray.KeyboardSelected += (_, id) => OnKeyboardSelected(id);
        _tray.VerboseLoggingToggled += (_, enabled) => OnVerboseToggled(enabled);
        _tray.PinCornerSelected += (_, corner) => OnPinCorner(corner);
        _tray.DisplayModeSelected += (_, mode) => OnDisplayMode(mode);
        _tray.LanguageSelected += (_, pref) => OnLanguageSelected(pref);

        _tray.SetPanelVisible(_settings.PanelVisible);
        _tray.SetPinnedCorner(_settings.PinnedCorner);
        _tray.SetDisplayMode(_settings.DisplayMode);
        _tray.SetLanguage(_settings.UICulture);
        _tray.UpdateKeyboards(_lastKeyboards);
        if (_monitor?.Current.KeyboardDisplayName is { } name) _tray.SetTitle(name);
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
        _lastSnapshot = snapshot;
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

    private void TogglePanel()
    {
        if (_panel!.IsVisible)
        {
            _panel.Hide();
            _settings.PanelVisible = false;
        }
        else
        {
            _panel.Show();
            _panel.Activate();
            _panel.ApplyPlacement();
            _settings.PanelVisible = true;
        }

        _settings.Save();
        _tray!.SetPanelVisible(_settings.PanelVisible);
    }

    private void OnPinCorner(PinnedCorner? corner)
    {
        _settings.PinnedCorner = corner;
        _settings.Save();
        _tray!.SetPinnedCorner(corner);
        _panel!.ApplyPlacement();
    }

    private void OnDisplayMode(DisplayMode mode)
    {
        _settings.DisplayMode = mode;
        _settings.Save();
        _viewModel!.SetDisplayMode(mode);
        _tray!.SetDisplayMode(mode);
        _panel!.ApplyPlacement();
    }

    /// <summary>
    /// Apply a language change immediately (FR-003 / FR-004 / FR-011): persist
    /// the preference, rebuild the localisation service, re-render the panel via
    /// the cached snapshot, and rebuild the tray menu under the new culture. No
    /// restart, BLE monitoring untouched.
    /// </summary>
    private void OnLanguageSelected(UiCulturePreference preference)
    {
        if (_settings.UICulture == preference)
        {
            _tray!.SetLanguage(preference);
            return;
        }

        _settings.UICulture = preference;
        _settings.Save();

        _loc = LocalizationService.FromPreference(preference);
        _viewModel!.SetLocalization(_loc);
        if (_lastSnapshot is { } snapshot)
        {
            _viewModel.Apply(snapshot);
            _tray!.SetTitle(snapshot.KeyboardDisplayName ?? _loc.Get("AppName"));
        }

        // Rebuild the tray menu with the new culture's labels; the old icon is
        // disposed after the new menu is wired (deferred to avoid tearing down
        // the tray during this click callback).
        var oldTray = _tray;
        BuildTray();
        Dispatcher.BeginInvoke(new Action(() => oldTray?.Dispose()), DispatcherPriority.Background);
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
