using KeyBeacon.Core;
using Xunit;

namespace KeyBeacon.Core.Tests;

public class StalenessTrackerTests
{
    private static readonly TimeSpan Window = TimeSpan.FromSeconds(3);

    [Fact]
    public void NeverRecorded_IsStale()
    {
        var tracker = new StalenessTracker(Window);
        Assert.True(tracker.IsStale("layer", TimeSpan.Zero));
    }

    [Fact]
    public void WithinWindow_IsLive()
    {
        var tracker = new StalenessTracker(Window);
        tracker.RecordNotify("layer", TimeSpan.FromSeconds(10));

        Assert.False(tracker.IsStale("layer", TimeSpan.FromSeconds(12)));
    }

    [Theory]
    [InlineData(3.0)]
    [InlineData(3.5)]
    [InlineData(10.0)]
    public void AtOrBeyondWindow_IsStale(double elapsed)
    {
        var tracker = new StalenessTracker(Window);
        tracker.RecordNotify("layer", TimeSpan.FromSeconds(10));

        Assert.True(tracker.IsStale("layer", TimeSpan.FromSeconds(10 + elapsed)));
    }

    [Fact]
    public void ClockRegression_NeverRegressesTimestamp()
    {
        var tracker = new StalenessTracker(Window);
        tracker.RecordNotify("layer", TimeSpan.FromSeconds(10));
        tracker.RecordNotify("layer", TimeSpan.FromSeconds(5));

        Assert.Equal(TimeSpan.FromSeconds(10), tracker.LastNotifyAt("layer"));
    }

    [Fact]
    public void ForceStaleAll_MarksEveryTrackedField()
    {
        var tracker = new StalenessTracker(Window);
        tracker.RecordNotify("layer", TimeSpan.FromSeconds(1));
        tracker.RecordNotify("battery", TimeSpan.FromSeconds(1));

        tracker.ForceStaleAll();

        Assert.True(tracker.IsStale("layer", TimeSpan.FromSeconds(1)));
        Assert.True(tracker.IsStale("battery", TimeSpan.FromSeconds(1)));
    }

    [Fact]
    public void RecordNotify_ClearsForcedStale()
    {
        var tracker = new StalenessTracker(Window);
        tracker.RecordNotify("layer", TimeSpan.Zero);
        tracker.ForceStaleAll();

        tracker.RecordNotify("layer", TimeSpan.FromSeconds(1));

        Assert.False(tracker.IsStale("layer", TimeSpan.FromSeconds(1)));
    }

    [Fact]
    public void DefaultWindow_IsThreeSeconds()
    {
        Assert.Equal(TimeSpan.FromSeconds(3), new StalenessTracker().StalenessWindow);
    }
}
