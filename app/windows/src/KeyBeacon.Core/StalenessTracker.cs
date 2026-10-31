using System;
using System.Collections.Generic;

namespace KeyBeacon.Core;

/// <summary>
/// Per-field staleness bookkeeping for KBP live values (FR-007/FR-007a).
/// A field is live while its last notify is within <see cref="StalenessWindow"/>;
/// older than that it is stale, and the UI MUST render the last-known value
/// plus an "updated hh:mm:ss" timestamp, visually de-emphasised — never a
/// fabricated or blanked value.
/// Plain class with injected monotonic timestamps: no timer of its own, so it
/// stays trivially unit-testable. Callers MUST serialise access.
/// </summary>
public sealed class StalenessTracker
{
    private readonly Dictionary<string, TimeSpan> _lastNotify = new(StringComparer.Ordinal);
    private readonly HashSet<string> _forcedStale = new(StringComparer.Ordinal);

    public StalenessTracker(TimeSpan? stalenessWindow = null)
    {
        StalenessWindow = stalenessWindow ?? TimeSpan.FromSeconds(3);
    }

    public TimeSpan StalenessWindow { get; }

    /// <summary>Records a fresh notify. Clock regressions never move a timestamp back.</summary>
    public void RecordNotify(string fieldKey, TimeSpan at)
    {
        if (!_lastNotify.TryGetValue(fieldKey, out var existing) || existing <= at)
        {
            _lastNotify[fieldKey] = at;
        }

        _forcedStale.Remove(fieldKey);
    }

    /// <summary>Never-recorded fields count as stale (there is no live reading yet).</summary>
    public bool IsStale(string fieldKey, TimeSpan now)
    {
        if (_forcedStale.Contains(fieldKey)) return true;
        if (!_lastNotify.TryGetValue(fieldKey, out var last)) return true;
        return now - last >= StalenessWindow;
    }

    /// <summary>Marks every tracked field stale immediately (transport disconnect).</summary>
    public void ForceStaleAll() => _forcedStale.UnionWith(_lastNotify.Keys);

    public void ForceStale(string fieldKey) => _forcedStale.Add(fieldKey);

    public TimeSpan? LastNotifyAt(string fieldKey) =>
        _lastNotify.TryGetValue(fieldKey, out var last) ? last : null;

    public IReadOnlyList<string> TrackedFieldKeys
    {
        get
        {
            var keys = new List<string>(_lastNotify.Keys);
            keys.Sort(StringComparer.Ordinal);
            return keys;
        }
    }

    public void Reset()
    {
        _lastNotify.Clear();
        _forcedStale.Clear();
    }
}
