using System;
using System.Collections.Generic;
using System.Threading;
using KeyBeacon.Core;

namespace KeyBeacon.App.Ble;

/// <summary>
/// Drives the <see cref="StalenessTracker"/> on a 1 Hz tick and raises an event
/// when any tracked field crosses the live↔stale boundary (FR-007a).
///
/// On a live→stale transition (connection still up) the UI keeps the last-known
/// value with an "updated hh:mm:ss" timestamp, visually de-emphasised — it does
/// NOT blank or fabricate the value. A transport disconnect is handled
/// separately by <see cref="KeyboardMonitor"/> via <see cref="StalenessTracker.ForceStaleAll"/>.
/// </summary>
public sealed class StalenessCoordinator : IDisposable
{
    private readonly StalenessTracker _tracker;
    private readonly Func<TimeSpan> _clock;
    private readonly Dictionary<string, bool> _lastStale = new(StringComparer.Ordinal);
    private Timer? _timer;

    public StalenessCoordinator(StalenessTracker tracker, Func<TimeSpan>? clock = null)
    {
        _tracker = tracker;
        _clock = clock ?? (() => TimeSpan.FromTicks(Environment.TickCount64 * TimeSpan.TicksPerMillisecond));
        foreach (var key in FieldKeys.All) _lastStale[key] = true;
    }

    /// <summary>Raised when a field transitions. <c>true</c> = became stale, <c>false</c> = became live.</summary>
    public event EventHandler<StalenessChange>? FieldTransitioned;

    public void Start(TimeSpan? period = null)
    {
        var p = period ?? TimeSpan.FromSeconds(1);
        _timer = new Timer(_ => Tick(), null, p, p);
    }

    public void RecordNotify(string fieldKey)
    {
        _tracker.RecordNotify(fieldKey, _clock());
        Evaluate(fieldKey);
    }

    /// <summary>Evaluates all fields once (call after a forced-stale-all on disconnect).</summary>
    public void EvaluateAll()
    {
        foreach (var key in FieldKeys.All) Evaluate(key);
    }

    private void Tick() => EvaluateAll();

    private void Evaluate(string fieldKey)
    {
        var isStale = _tracker.IsStale(fieldKey, _clock());
        if (_lastStale.TryGetValue(fieldKey, out var prev) && prev == isStale) return;

        _lastStale[fieldKey] = isStale;
        FieldTransitioned?.Invoke(this, new StalenessChange(fieldKey, isStale, _tracker.LastNotifyAt(fieldKey)));
    }

    public void Dispose()
    {
        _timer?.Dispose();
        _timer = null;
    }
}

public readonly record struct StalenessChange(string FieldKey, bool BecameStale, TimeSpan? LastNotifyAt);
