using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using KeyBeacon.App.Diagnostics;
using KeyBeacon.App.Settings;
using KeyBeacon.Core;
using Microsoft.Extensions.Logging;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;
using Windows.Devices.Radios;

namespace KeyBeacon.App.Ble;

/// <summary>
/// Central BLE orchestrator (US1/US2/US3/US5). Enumerates connected keyboards
/// via <see cref="DeviceWatcher"/>, connects the selected one, discovers the
/// KeyBeacon characteristics, subscribes, parses with <see cref="KeyBeacon.Core"/>,
/// and publishes an immutable <see cref="KeyboardSnapshot"/>.
///
/// All WinRT calls run on the thread pool (MTA); <see cref="SnapshotChanged"/>
/// and <see cref="KeyboardsChanged"/> are marshalled back via the supplied post
/// delegate so WPF handlers touch UI state on the dispatcher thread.
/// </summary>
public sealed class KeyboardMonitor : IAsyncDisposable
{
    private readonly ILoggerFactory _loggerFactory;
    private readonly ILogger _connLog;
    private readonly ILogger _capLog;
    private readonly ILogger _batLog;
    private readonly Action<Action> _post;
    private readonly StalenessTracker _tracker = new();
    private readonly StalenessCoordinator _staleness;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly TimeSpan _timeout;

    private DeviceWatcher? _watcher;
    private readonly Dictionary<string, string> _knownDevices = new(StringComparer.Ordinal); // id -> name
    private readonly HashSet<string> _supportedIds = new(StringComparer.Ordinal);

    private string? _selectedId;
    private BluetoothLEDevice? _device;
    private GattCharacteristic? _statusChar;
    private GattCharacteristic? _connChar;
    private GattCharacteristic? _batteryChar;

    private KeyboardStatus? _lastStatus;
    private ConnectivityStatus? _lastConnectivity;
    private BatteryStatus? _lastBattery;
    private CapabilityMatrix? _capability;
    private byte[]? _pendingBattery; // cached until capability (isSplit) is known
    private byte _lastCapabilityByte;

    public KeyboardMonitor(ILoggerFactory loggerFactory, Action<Action> post, TimeSpan? timeout = null)
    {
        _loggerFactory = loggerFactory;
        _post = post;
        _timeout = timeout ?? TimeSpan.FromSeconds(10);
        _connLog = DiagnosticsLogger.For(loggerFactory, DiagnosticsLogger.Categories.Connection);
        _capLog = DiagnosticsLogger.For(loggerFactory, DiagnosticsLogger.Categories.Capability);
        _batLog = DiagnosticsLogger.For(loggerFactory, DiagnosticsLogger.Categories.Battery);

        _staleness = new StalenessCoordinator(_tracker);
        _staleness.FieldTransitioned += OnFieldTransitioned;
        _staleness.Start();
    }

    public event EventHandler<KeyboardSnapshot>? SnapshotChanged;

    /// <summary>Supported keyboards currently visible, for the tray selection menu.</summary>
    public event EventHandler<IReadOnlyList<CompatibleKeyboard>>? KeyboardsChanged;

    public KeyboardSnapshot Current { get; private set; } = KeyboardSnapshot.ForState(MonitorState.NoKeyboard);

    /// <summary>Starts adapter monitoring and device discovery (FR-001).</summary>
    public async Task StartAsync(string? rememberedId)
    {
        _selectedId = rememberedId;
        DiagnosticsLogger.For(_loggerFactory, DiagnosticsLogger.Categories.Connection)
            .LogInformation(DiagnosticEvents.AppStarted);

        if (!await IsBluetoothAvailableAsync())
        {
            Publish(KeyboardSnapshot.ForState(MonitorState.BluetoothUnavailable));
            _connLog.LogWarning(DiagnosticEvents.AdapterUnavailable);
        }

        StartWatcher();
    }

    /// <summary>User picked a keyboard from the tray; rebuild the subscription (FR-010).</summary>
    public async Task SelectKeyboardAsync(string deviceId)
    {
        _selectedId = deviceId;
        await ConnectSelectedAsync();
    }

    public async Task ReconnectAsync()
    {
        await DisconnectInternalAsync();
        await ConnectSelectedAsync();
    }

    private void StartWatcher()
    {
        if (_watcher is not null) return;

        var selector = BluetoothLEDevice.GetDeviceSelectorFromConnectionStatus(BluetoothConnectionStatus.Connected);
        _watcher = DeviceInformation.CreateWatcher(selector, null, DeviceInformationKind.AssociationEndpoint);
        _watcher.Added += (_, info) => _ = OnDeviceAddedAsync(info);
        _watcher.Removed += (_, update) => _ = OnDeviceRemovedAsync(update.Id);
        _watcher.Updated += (_, _) => { };
        _watcher.Start();
    }

    private async Task OnDeviceAddedAsync(DeviceInformation info)
    {
        try
        {
            var classification = await ClassifyAsync(info.Id);
            _knownDevices[info.Id] = info.Name;

            if (classification == KbpClassification.Supported)
            {
                _supportedIds.Add(info.Id);
                PublishKeyboards();

                var resolved = CompatibleKeyboard.ResolveSelection(_supportedIds.ToList(), _selectedId);
                if (resolved is not null && (_device is null || resolved == _selectedId))
                {
                    _selectedId = resolved;
                    await ConnectSelectedAsync();
                }
            }
            else if (classification == KbpClassification.UnsupportedVersion && _device is null)
            {
                Publish(KeyboardSnapshot.ForState(MonitorState.UnsupportedVersion, info.Name));
            }
        }
        catch (Exception ex)
        {
            _connLog.LogWarning("{Event} id={Id} error={Error}", DiagnosticEvents.DiscoveryAnomaly, Mask(info.Id), ex.Message);
        }
    }

    private async Task OnDeviceRemovedAsync(string id)
    {
        _knownDevices.Remove(id);
        if (_supportedIds.Remove(id)) PublishKeyboards();

        if (id == _selectedId)
        {
            await DisconnectInternalAsync();
            PublishDisconnected();
        }
    }

    private async Task<KbpClassification> ClassifyAsync(string deviceId)
    {
        using var device = await BluetoothLEDevice.FromIdAsync(deviceId).AsTask().WaitAsync(_timeout);
        if (device is null) return KbpClassification.NotAKeyboard;

        var result = await device.GetGattServicesAsync(BluetoothCacheMode.Uncached).AsTask().WaitAsync(_timeout);
        if (result.Status != GattCommunicationStatus.Success) return KbpClassification.NotAKeyboard;

        return KbpUuids.Classify(result.Services.Select(s => s.Uuid));
    }

    private async Task ConnectSelectedAsync()
    {
        if (_selectedId is null) return;

        await _gate.WaitAsync();
        try
        {
            await DisconnectInternalAsync(takeGate: false);
            Publish(Current with { State = MonitorState.Connecting });

            _device = await BluetoothLEDevice.FromIdAsync(_selectedId).AsTask().WaitAsync(_timeout);
            if (_device is null)
            {
                PublishDisconnected();
                return;
            }

            _device.ConnectionStatusChanged += OnConnectionStatusChanged;

            var services = await _device.GetGattServicesAsync(BluetoothCacheMode.Uncached).AsTask().WaitAsync(_timeout);
            if (services.Status != GattCommunicationStatus.Success)
            {
                PublishDisconnected();
                return;
            }

            var service = services.Services.FirstOrDefault(s => s.Uuid == KbpUuids.Service);
            if (service is null)
            {
                PublishDisconnected();
                return;
            }

            var chars = await service.GetCharacteristicsAsync(BluetoothCacheMode.Uncached).AsTask().WaitAsync(_timeout);
            if (chars.Status != GattCommunicationStatus.Success)
            {
                PublishDisconnected();
                return;
            }

            _statusChar = chars.Characteristics.FirstOrDefault(c => c.Uuid == KbpUuids.Status);
            _connChar = chars.Characteristics.FirstOrDefault(c => c.Uuid == KbpUuids.Connectivity);
            _batteryChar = chars.Characteristics.FirstOrDefault(c => c.Uuid == KbpUuids.Battery);

            if (_statusChar is null)
            {
                if (_connChar is not null)
                {
                    _connLog.LogWarning("{Event} reason={Reason}", DiagnosticEvents.DiscoveryAnomaly, "AA2 present but AA1 missing");
                }
                PublishDisconnected();
                return;
            }

            await SubscribeAsync(_statusChar, FieldKeys.Status, OnStatusChanged);
            if (_connChar is not null) await SubscribeAsync(_connChar, FieldKeys.Connectivity, OnConnectivityChanged);
            if (_batteryChar is not null) await SubscribeAsync(_batteryChar, FieldKeys.Battery, OnBatteryChanged);

            _connLog.LogInformation("{Event} connected={Connected} reason_raw=0x00",
                DiagnosticEvents.ConnectionStateChanged, true);

            PublishConnected();
        }
        catch (Exception ex)
        {
            _connLog.LogWarning("{Event} error={Error}", DiagnosticEvents.ConnectionStateChanged, ex.Message);
            PublishDisconnected();
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task SubscribeAsync(GattCharacteristic ch, string fieldKey,
        Windows.Foundation.TypedEventHandler<GattCharacteristic, GattValueChangedEventArgs> handler)
    {
        var initial = await ReadAsync(ch);
        if (initial is not null) DispatchValue(fieldKey, initial);

        var status = await ch.WriteClientCharacteristicConfigurationDescriptorAsync(
            GattClientCharacteristicConfigurationDescriptorValue.Notify).AsTask().WaitAsync(_timeout);

        if (status == GattCommunicationStatus.Success)
        {
            ch.ValueChanged += handler;
        }
    }

    private void DispatchValue(string fieldKey, byte[] value)
    {
        switch (fieldKey)
        {
            case FieldKeys.Status: HandleStatus(value); break;
            case FieldKeys.Connectivity: HandleConnectivity(value); break;
            case FieldKeys.Battery: HandleBattery(value); break;
        }
    }

    private async Task<byte[]?> ReadAsync(GattCharacteristic ch)
    {
        try
        {
            var result = await ch.ReadValueAsync(BluetoothCacheMode.Uncached).AsTask().WaitAsync(_timeout);
            return result.Status == GattCommunicationStatus.Success ? ToBytes(result.Value) : null;
        }
        catch (TimeoutException)
        {
            return null;
        }
    }

    // ---- notify handlers (BLE thread) ----

    private void OnStatusChanged(GattCharacteristic s, GattValueChangedEventArgs e) => HandleStatus(ToBytes(e.CharacteristicValue));
    private void OnConnectivityChanged(GattCharacteristic s, GattValueChangedEventArgs e) => HandleConnectivity(ToBytes(e.CharacteristicValue));
    private void OnBatteryChanged(GattCharacteristic s, GattValueChangedEventArgs e) => HandleBattery(ToBytes(e.CharacteristicValue));

    private void HandleStatus(byte[] value)
    {
        var parsed = KeyboardStatus.Parse(value);
        if (parsed is null) return;
        _lastStatus = parsed;
        _staleness.RecordNotify(FieldKeys.Status);
        PublishConnected();
    }

    private void HandleConnectivity(byte[] value)
    {
        var parsed = ConnectivityStatus.Parse(value);
        if (parsed is null)
        {
            _connLog.LogWarning("{Event} length={Length}", DiagnosticEvents.ConnectivityShortPayload, value.Length);
            return;
        }

        var cap = parsed.Capability;
        if (!cap.IsConsistent)
        {
            _capLog.LogWarning("{Event} raw=0x{Raw:X2} reason={Reason}",
                DiagnosticEvents.CapabilityInconsistent, cap.ToByte(), cap.InconsistencyReason());
            cap = cap.Normalized();
            parsed = parsed with { Capability = cap };
        }

        if (_capability is null)
        {
            _capLog.LogInformation("{Event} raw=0x{Raw:X2} is_split={Split}",
                DiagnosticEvents.CapabilityDiscovered, cap.ToByte(), cap.IsSplit);
        }
        else if (_lastCapabilityByte != cap.ToByte())
        {
            _capLog.LogInformation("{Event} from=0x{From:X2} to=0x{To:X2}",
                DiagnosticEvents.CapabilityMutated, _lastCapabilityByte, cap.ToByte());
        }

        if (parsed.Profile.OutOfRange)
        {
            DiagnosticsLogger.For(_loggerFactory, DiagnosticsLogger.Categories.Profile)
                .LogWarning("{Event} raw_index={Index} max_slots={Max}",
                    DiagnosticEvents.ProfileOutOfRange, parsed.Profile.Index, parsed.Profile.MaxSlots);
        }

        _capability = cap;
        _lastCapabilityByte = cap.ToByte();
        _lastConnectivity = parsed;
        _staleness.RecordNotify(FieldKeys.Connectivity);

        if (_pendingBattery is not null)
        {
            HandleBattery(_pendingBattery);
            _pendingBattery = null;
        }

        PublishConnected();
    }

    private void HandleBattery(byte[] value)
    {
        if (_capability is null)
        {
            _pendingBattery = value; // decode once isSplit is known (C-3)
            return;
        }

        var parsed = BatteryStatus.Parse(value, _capability.IsSplit);
        if (parsed is null)
        {
            _batLog.LogWarning("{Event} expected={Expected} got={Got} is_split={Split}",
                DiagnosticEvents.BatteryLengthMismatch, _capability.IsSplit ? 2 : 1, value.Length, _capability.IsSplit);
            return;
        }

        LogBatteryOutOfRange(parsed);
        _lastBattery = parsed;
        _staleness.RecordNotify(FieldKeys.Battery);
        PublishConnected();
    }

    private void LogBatteryOutOfRange(BatteryStatus battery)
    {
        switch (battery.Shape)
        {
            case BatteryStatus.Kind.Overall o when o.Reading.OutOfRange:
                _batLog.LogWarning("{Event} raw=0x{Raw:X2} side={Side}", DiagnosticEvents.BatteryOutOfRange, o.Reading.RawByte, "overall");
                break;
            case BatteryStatus.Kind.Split s:
                if (s.Left.OutOfRange) _batLog.LogWarning("{Event} raw=0x{Raw:X2} side={Side}", DiagnosticEvents.BatteryOutOfRange, s.Left.RawByte, "left");
                if (s.Right.OutOfRange) _batLog.LogWarning("{Event} raw=0x{Raw:X2} side={Side}", DiagnosticEvents.BatteryOutOfRange, s.Right.RawByte, "right");
                break;
        }
    }

    // ---- connection / staleness ----

    private void OnConnectionStatusChanged(BluetoothLEDevice sender, object args)
    {
        if (sender.ConnectionStatus == BluetoothConnectionStatus.Disconnected)
        {
            _tracker.ForceStaleAll();
            _staleness.EvaluateAll();
            _connLog.LogInformation("{Event} connected={Connected} reason_raw=0x00",
                DiagnosticEvents.ConnectionStateChanged, false);
            PublishDisconnected();
        }
    }

    private void OnFieldTransitioned(object? sender, StalenessChange change)
    {
        var staleLog = DiagnosticsLogger.For(_loggerFactory, DiagnosticsLogger.Categories.Staleness);
        if (change.BecameStale)
            staleLog.LogInformation("{Event} field={Field} reason={Reason}", DiagnosticEvents.StalenessFieldStale, change.FieldKey, "window_elapsed");
        else
            staleLog.LogInformation("{Event} field={Field}", DiagnosticEvents.StalenessFieldLive, change.FieldKey);

        PublishConnected();
    }

    // ---- publishing ----

    private void PublishConnected()
    {
        if (_device is null) return;
        var name = _selectedId is not null && _knownDevices.TryGetValue(_selectedId, out var n) ? n : null;

        var snapshot = new KeyboardSnapshot
        {
            State = MonitorState.Connected,
            KeyboardDisplayName = new CompatibleKeyboard(_selectedId ?? string.Empty, name, BleConnectionState.Connected, true).DisplayName,
            Status = _lastStatus,
            StatusFreshness = Freshness(FieldKeys.Status),
            Capability = _capability,
            Connectivity = _lastConnectivity,
            ConnectivityFreshness = Freshness(FieldKeys.Connectivity),
            Battery = _lastBattery,
            BatteryFreshness = Freshness(FieldKeys.Battery)
        };
        Publish(snapshot);
    }

    private FieldFreshness Freshness(string key)
    {
        var now = TimeSpan.FromTicks(Environment.TickCount64 * TimeSpan.TicksPerMillisecond);
        var last = _tracker.LastNotifyAt(key);
        return new FieldFreshness(
            _tracker.IsStale(key, now),
            last is null ? null : DateTimeOffset.Now); // UI only needs a wall-clock stamp for display
    }

    private void PublishDisconnected() => Publish(KeyboardSnapshot.ForState(MonitorState.Disconnected, Current.KeyboardDisplayName));

    private void Publish(KeyboardSnapshot snapshot)
    {
        Current = snapshot;
        _post(() => SnapshotChanged?.Invoke(this, snapshot));
    }

    private void PublishKeyboards()
    {
        var list = _supportedIds
            .Select(id => new CompatibleKeyboard(id, _knownDevices.GetValueOrDefault(id), BleConnectionState.Connected, true))
            .ToList();
        _post(() => KeyboardsChanged?.Invoke(this, list));
    }

    private static async Task<bool> IsBluetoothAvailableAsync()
    {
        try
        {
            var radios = await Radio.GetRadiosAsync();
            return radios.Any(r => r.Kind == RadioKind.Bluetooth && r.State == RadioState.On);
        }
        catch (Exception)
        {
            return false;
        }
    }

    private async Task DisconnectInternalAsync(bool takeGate = true)
    {
        if (takeGate) await _gate.WaitAsync();
        try
        {
            if (_statusChar is not null) _statusChar.ValueChanged -= OnStatusChanged;
            if (_connChar is not null) _connChar.ValueChanged -= OnConnectivityChanged;
            if (_batteryChar is not null) _batteryChar.ValueChanged -= OnBatteryChanged;
            _statusChar = _connChar = _batteryChar = null;

            if (_device is not null)
            {
                _device.ConnectionStatusChanged -= OnConnectionStatusChanged;
                _device.Dispose();
                _device = null;
            }

            _lastStatus = null;
            _lastConnectivity = null;
            _lastBattery = null;
            _capability = null;
            _pendingBattery = null;
            _tracker.Reset();
        }
        finally
        {
            if (takeGate) _gate.Release();
        }
    }

    private static byte[] ToBytes(Windows.Storage.Streams.IBuffer buffer)
    {
        var reader = Windows.Storage.Streams.DataReader.FromBuffer(buffer);
        var bytes = new byte[reader.UnconsumedBufferLength];
        reader.ReadBytes(bytes);
        return bytes;
    }

    private static string Mask(string id) => id.Length <= 8 ? id : id[..8] + "…";

    public async ValueTask DisposeAsync()
    {
        _watcher?.Stop();
        _staleness.Dispose();
        await DisconnectInternalAsync();
        _gate.Dispose();
    }
}
