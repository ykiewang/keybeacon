using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using KeyBeacon.Core;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;

namespace KeyBeacon.Probe;

public sealed record DiscoveredDevice(string Id, string Name);

/// <summary>
/// Thin WinRT BLE wrapper: enumerate already-connected peripherals, open a
/// GATT session, discover KeyBeacon characteristics, read and subscribe.
///
/// Discovery MUST enumerate connected devices rather than scan advertisements:
/// a paired BLE HID keyboard that is in use stops advertising (FR-001).
/// All WinRT calls are bounded by <see cref="Timeout"/> so a stale "connected"
/// device cannot hang the probe (C-2).
/// </summary>
public sealed class BleProbe : IAsyncDisposable
{
    private readonly TimeSpan _timeout;
    private readonly Action<string>? _trace;

    private BluetoothLEDevice? _device;

    public BleProbe(TimeSpan timeout, Action<string>? trace = null)
    {
        _timeout = timeout;
        _trace = trace;
    }

    /// <summary>
    /// Enumerates BLE devices the OS currently reports as connected.
    /// This is the selector that matters — advertisement scanning finds nothing.
    /// </summary>
    public async Task<IReadOnlyList<DiscoveredDevice>> EnumerateConnectedAsync(CancellationToken ct = default)
    {
        var selector = BluetoothLEDevice.GetDeviceSelectorFromConnectionStatus(
            BluetoothConnectionStatus.Connected);

        var infos = await DeviceInformation.FindAllAsync(selector).AsTask(ct).WaitAsync(_timeout, ct);

        var devices = new List<DiscoveredDevice>(infos.Count);
        foreach (var info in infos)
        {
            devices.Add(new DiscoveredDevice(info.Id, info.Name));
        }

        _trace?.Invoke($"enumerated {devices.Count} connected BLE device(s)");
        return devices;
    }

    /// <summary>
    /// Opens the GATT session for a device id and returns the discovered
    /// services. Uses cached==Uncached so a stale cache cannot mask a failure.
    /// </summary>
    public async Task<IReadOnlyList<GattDeviceService>> GetServicesAsync(
        string deviceId, CancellationToken ct = default)
    {
        _device = await BluetoothLEDevice.FromIdAsync(deviceId).AsTask(ct).WaitAsync(_timeout, ct)
            ?? throw new PrerequisiteException($"could not open device '{deviceId}'");

        var result = await _device
            .GetGattServicesAsync(BluetoothCacheMode.Uncached)
            .AsTask(ct)
            .WaitAsync(_timeout, ct);

        if (result.Status != GattCommunicationStatus.Success)
        {
            throw new PrerequisiteException($"GATT service discovery failed: {result.Status}");
        }

        return result.Services;
    }

    /// <summary>Finds the KeyBeacon service and its AA1/AA2/AA3 characteristics.</summary>
    public static async Task<KbpCharacteristics> FindKbpCharacteristicsAsync(
        IReadOnlyList<GattDeviceService> services, TimeSpan timeout, CancellationToken ct = default)
    {
        var service = services.FirstOrDefault(s => s.Uuid == KbpUuids.Service);
        if (service is null) throw new PrerequisiteException("KeyBeacon service AA0 not found");

        var result = await service
            .GetCharacteristicsAsync(BluetoothCacheMode.Uncached)
            .AsTask(ct)
            .WaitAsync(timeout, ct);

        if (result.Status != GattCommunicationStatus.Success)
        {
            throw new PrerequisiteException($"GATT characteristic discovery failed: {result.Status}");
        }

        var chars = result.Characteristics;
        return new KbpCharacteristics(
            Status: chars.FirstOrDefault(c => c.Uuid == KbpUuids.Status),
            Connectivity: chars.FirstOrDefault(c => c.Uuid == KbpUuids.Connectivity),
            Battery: chars.FirstOrDefault(c => c.Uuid == KbpUuids.Battery));
    }

    /// <summary>Reads the current value of a characteristic, or null when the read fails.</summary>
    public async Task<byte[]?> ReadAsync(GattCharacteristic characteristic, CancellationToken ct = default)
    {
        var result = await characteristic
            .ReadValueAsync(BluetoothCacheMode.Uncached)
            .AsTask(ct)
            .WaitAsync(_timeout, ct);

        if (result.Status != GattCommunicationStatus.Success) return null;

        return ReadBuffer(result.Value);
    }

    /// <summary>Enables notify and awaits the first value arriving within the timeout.</summary>
    public async Task<byte[]?> SubscribeFirstNotifyAsync(
        GattCharacteristic characteristic, CancellationToken ct = default)
    {
        var cccdResult = await characteristic
            .WriteClientCharacteristicConfigurationDescriptorAsync(
                GattClientCharacteristicConfigurationDescriptorValue.Notify)
            .AsTask(ct)
            .WaitAsync(_timeout, ct);

        if (cccdResult != GattCommunicationStatus.Success)
        {
            throw new PrerequisiteException($"could not enable notifications: {cccdResult}");
        }

        var tcs = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);

        void OnValueChanged(GattCharacteristic sender, GattValueChangedEventArgs args) =>
            tcs.TrySetResult(ReadBuffer(args.CharacteristicValue));

        characteristic.ValueChanged += OnValueChanged;
        try
        {
            return await tcs.Task.WaitAsync(_timeout, ct);
        }
        catch (TimeoutException)
        {
            return null;
        }
        finally
        {
            characteristic.ValueChanged -= OnValueChanged;
        }
    }

    private static byte[] ReadBuffer(Windows.Storage.Streams.IBuffer buffer)
    {
        var reader = Windows.Storage.Streams.DataReader.FromBuffer(buffer);
        var bytes = new byte[reader.UnconsumedBufferLength];
        reader.ReadBytes(bytes);
        return bytes;
    }

    public ValueTask DisposeAsync()
    {
        _device?.Dispose();
        _device = null;
        return ValueTask.CompletedTask;
    }
}

/// <summary>KeyBeacon characteristics located on the selected keyboard.</summary>
public sealed record KbpCharacteristics(
    GattCharacteristic? Status,
    GattCharacteristic? Connectivity,
    GattCharacteristic? Battery)
{
    public bool HasStatus => Status is not null;
    public bool HasConnectivity => Connectivity is not null;
    public bool HasBattery => Battery is not null;

    /// <summary>Comma-separated short names of the characteristics present.</summary>
    public string PresentNames()
    {
        var names = new List<string>(3);
        if (HasStatus) names.Add("AA1");
        if (HasConnectivity) names.Add("AA2");
        if (HasBattery) names.Add("AA3");
        return names.Count == 0 ? "none" : string.Join(",", names);
    }
}
