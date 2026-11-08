using System;
using System.Linq;
using KeyBeacon.Core;
using Xunit;

namespace KeyBeacon.Core.Tests;

/// <summary>
/// US1 (spec 005) pure-function tests: <see cref="LinkSlot.Parse"/> (T012) and
/// <see cref="HostContextStatus.DeriveLocalHostStatus"/> five-state derivation
/// (T013). Case-for-case parity with the macOS
/// <c>HostLinkProfileAwarenessTests</c> (constitution §III).
/// </summary>
public class HostContextStatusTests
{
    private static byte[] Payload(params byte[] bytes) => bytes;

    // --- T012: LinkSlot.Parse ---

    [Fact]
    public void LinkSlot_NotDetermined_Zero()
    {
        var s = LinkSlot.Parse(Payload(0x00));
        Assert.Equal(new LinkSlot(0, false, 0), s);
        Assert.False(s!.IsDetermined);
    }

    [Fact]
    public void LinkSlot_OneBasedSlot()
    {
        var s = LinkSlot.Parse(Payload(0x01))!;
        Assert.Equal(1, s.Slot);
        Assert.True(s.IsDetermined);
        Assert.False(s.ReservedBit7);
    }

    [Fact]
    public void LinkSlot_Exhaustive_0_To_127()
    {
        for (byte raw = 0; raw <= 127; raw++)
        {
            var s = LinkSlot.Parse(Payload(raw))!;
            Assert.Equal(raw, s.Slot);
            Assert.False(s.ReservedBit7);
            Assert.Equal(raw >= 1, s.IsDetermined);
        }
    }

    [Fact]
    public void LinkSlot_Bit7_IgnoredForSlotValue()
    {
        for (byte slot = 0; slot <= 127; slot++)
        {
            byte raw = (byte)(slot | 0x80);
            var s = LinkSlot.Parse(Payload(raw))!;
            Assert.Equal(slot, s.Slot);
            Assert.True(s.ReservedBit7);
        }
    }

    [Fact]
    public void LinkSlot_EmptyPayload_ReturnsNull()
    {
        Assert.Null(LinkSlot.Parse(ReadOnlySpan<byte>.Empty));
    }

    [Fact]
    public void LinkSlot_TrailingBytesIgnored()
    {
        var s = LinkSlot.Parse(Payload(0x02, 0xAA, 0xBB, 0xCC))!;
        Assert.Equal(2, s.Slot);
        Assert.Equal(3, s.TrailingBytesIgnored);
    }

    [Fact]
    public void LinkSlot_IsWithinRange()
    {
        Assert.True(new LinkSlot(3, false, 0).IsWithinRange(5));
        Assert.True(new LinkSlot(5, false, 0).IsWithinRange(5));
        Assert.False(new LinkSlot(6, false, 0).IsWithinRange(5));
        Assert.False(new LinkSlot(0, false, 0).IsWithinRange(5));
        Assert.True(new LinkSlot(9, false, 0).IsWithinRange(0));
        Assert.False(new LinkSlot(0, false, 0).IsWithinRange(0));
    }

    // --- T013: DeriveLocalHostStatus helpers ---

    private static CapabilityMatrix Cap(bool hasProfile = true, bool hasOutputEndpoint = false) => new(
        IsSplit: false,
        HasHostConnection: true,
        HasProfile: hasProfile,
        HasSplitLink: false,
        HasOutputEndpoint: hasOutputEndpoint,
        HasLeftCharging: false,
        HasRightCharging: false,
        Reserved7: false);

    private static ConnectivityStatus.ProfileData Profile(byte index, bool isOpen = false, byte maxSlots = 5)
        => new(index, isOpen, maxSlots);

    private static readonly ConnectivityStatus.OutputEndpoint Usb = ConnectivityStatus.OutputEndpoint.FromByte(1);
    private static readonly ConnectivityStatus.OutputEndpoint Ble = ConnectivityStatus.OutputEndpoint.FromByte(2);

    // --- T013: disconnected (highest priority) ---

    [Fact]
    public void Derive_Disconnected_WhenNotConnected_RegardlessOfOtherInputs()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: true, connected: false,
            capability: Cap(hasOutputEndpoint: true),
            activeProfile: Profile(2), localSlot: new LinkSlot(2, false, 0), output: Usb);
        Assert.Equal(LocalHostStatus.Disconnected, status);
    }

    // --- T013: onUsb (before in-use over BLE) ---

    [Fact]
    public void Derive_OnUsb_WhenOutputUsbAndCapable()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: true, connected: true,
            capability: Cap(hasOutputEndpoint: true),
            activeProfile: Profile(2), localSlot: new LinkSlot(2, false, 0), output: Usb);
        Assert.Equal(LocalHostStatus.OnUsb, status);
    }

    [Fact]
    public void Derive_OnUsb_TakesPrecedenceOverInUseHere()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: true, connected: true,
            capability: Cap(hasOutputEndpoint: true),
            activeProfile: Profile(3), localSlot: new LinkSlot(3, false, 0), output: Usb);
        Assert.Equal(LocalHostStatus.OnUsb, status);
    }

    [Fact]
    public void Derive_NotOnUsb_WhenOutputUsbButCapabilityOff()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: true, connected: true,
            capability: Cap(hasOutputEndpoint: false),
            activeProfile: Profile(2), localSlot: new LinkSlot(2, false, 0), output: Usb);
        Assert.Equal(LocalHostStatus.InUseHere, status);
    }

    // --- T013: cannotDetermine ---

    [Fact]
    public void Derive_CannotDetermine_WhenNoAA4()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: false, connected: true,
            capability: Cap(), activeProfile: Profile(2),
            localSlot: new LinkSlot(2, false, 0), output: Ble);
        Assert.Equal(LocalHostStatus.CannotDetermine, status);
    }

    [Fact]
    public void Derive_CannotDetermine_WhenNoProfileCapability()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: true, connected: true,
            capability: Cap(hasProfile: false), activeProfile: Profile(2),
            localSlot: new LinkSlot(2, false, 0), output: Ble);
        Assert.Equal(LocalHostStatus.CannotDetermine, status);
    }

    [Fact]
    public void Derive_CannotDetermine_WhenActiveIndexZero()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: true, connected: true,
            capability: Cap(), activeProfile: Profile(0),
            localSlot: new LinkSlot(2, false, 0), output: Ble);
        Assert.Equal(LocalHostStatus.CannotDetermine, status);
    }

    [Fact]
    public void Derive_CannotDetermine_WhenProfileOpen()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: true, connected: true,
            capability: Cap(), activeProfile: Profile(2, isOpen: true),
            localSlot: new LinkSlot(2, false, 0), output: Ble);
        Assert.Equal(LocalHostStatus.CannotDetermine, status);
    }

    [Fact]
    public void Derive_CannotDetermine_WhenLocalSlotNull()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: true, connected: true,
            capability: Cap(), activeProfile: Profile(2),
            localSlot: null, output: Ble);
        Assert.Equal(LocalHostStatus.CannotDetermine, status);
    }

    [Fact]
    public void Derive_CannotDetermine_WhenLocalSlotZero()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: true, connected: true,
            capability: Cap(), activeProfile: Profile(2),
            localSlot: new LinkSlot(0, false, 0), output: Ble);
        Assert.Equal(LocalHostStatus.CannotDetermine, status);
    }

    [Fact]
    public void Derive_CannotDetermine_WhenCapabilityNull()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: true, connected: true,
            capability: null, activeProfile: Profile(2),
            localSlot: new LinkSlot(2, false, 0), output: Ble);
        Assert.Equal(LocalHostStatus.CannotDetermine, status);
    }

    // --- T013: inUseHere / activeElsewhere ---

    [Fact]
    public void Derive_InUseHere_WhenActiveEqualsLocal()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: true, connected: true,
            capability: Cap(), activeProfile: Profile(3),
            localSlot: new LinkSlot(3, false, 0), output: Ble);
        Assert.Equal(LocalHostStatus.InUseHere, status);
    }

    [Fact]
    public void Derive_ActiveElsewhere_WhenActiveDiffersFromLocal()
    {
        var status = HostContextStatus.DeriveLocalHostStatus(
            hasAA4: true, connected: true,
            capability: Cap(), activeProfile: Profile(1),
            localSlot: new LinkSlot(2, false, 0), output: Ble);
        Assert.Equal(LocalHostStatus.ActiveElsewhere(1), status);
    }

    // --- T013: exhaustive active × local matrix (the in-use/elsewhere core) ---

    [Fact]
    public void Derive_Exhaustive_ActiveVsLocal_Matrix()
    {
        const byte maxSlots = 4;
        for (byte active = 1; active <= maxSlots; active++)
        {
            for (byte local = 1; local <= maxSlots; local++)
            {
                var status = HostContextStatus.DeriveLocalHostStatus(
                    hasAA4: true, connected: true,
                    capability: Cap(), activeProfile: Profile(active, maxSlots: maxSlots),
                    localSlot: new LinkSlot(local, false, 0), output: Ble);
                if (active == local)
                    Assert.Equal(LocalHostStatus.InUseHere, status);
                else
                    Assert.Equal(LocalHostStatus.ActiveElsewhere(active), status);
            }
        }
    }

    // --- T029 [US2]: LinkSlotCache re-read / re-learn (parity with macOS) ---

    private static readonly DateTimeOffset T0 = DateTimeOffset.FromUnixTimeSeconds(1_000);
    private static readonly DateTimeOffset T1 = DateTimeOffset.FromUnixTimeSeconds(2_000);

    [Fact]
    public void Cache_InitialLearn_SetsSlotAndLearnedAt_NoReadBack()
    {
        var cache = new LinkSlotCache();
        Assert.Null(cache.Slot);
        Assert.Null(cache.LearnedAt);

        var readBack = cache.Learn(new LinkSlot(1, false, 0), T0);

        Assert.False(readBack); // first learn is not a read-back change
        Assert.Equal(1, cache.Slot!.Slot);
        Assert.Equal(T0, cache.LearnedAt);
    }

    [Fact]
    public void Cache_ReReadDifferentSlot_N_To_M_RefreshesAndSignalsReadBack()
    {
        var cache = new LinkSlotCache();
        cache.Learn(new LinkSlot(2, false, 0), T0); // N = 2
        var readBack = cache.Learn(new LinkSlot(5, false, 0), T1); // M = 5

        Assert.True(readBack); // slot N→M reports a read-back change (T034)
        Assert.Equal(5, cache.Slot!.Slot);
        Assert.Equal(T1, cache.LearnedAt); // learnedAt advances on re-read
    }

    [Fact]
    public void Cache_ReReadSameSlot_RefreshesLearnedAt_NoReadBack()
    {
        var cache = new LinkSlotCache();
        cache.Learn(new LinkSlot(3, false, 0), T0);
        var readBack = cache.Learn(new LinkSlot(3, false, 0), T1);

        Assert.False(readBack);
        Assert.Equal(3, cache.Slot!.Slot);
        Assert.Equal(T1, cache.LearnedAt);
    }

    [Fact]
    public void Cache_UnresolvedThenResolved_ZeroToSlot_SignalsReadBack()
    {
        // slot=0 at connect time (peer not yet matched to a bond), resolves
        // later on a fallback re-read.
        var cache = new LinkSlotCache();
        cache.Learn(new LinkSlot(0, false, 0), T0);
        var readBack = cache.Learn(new LinkSlot(1, false, 0), T1);

        Assert.True(readBack);
        Assert.Equal(1, cache.Slot!.Slot);
    }

    [Fact]
    public void Cache_NullRead_RetainsPreviousSlot_NoReadBack()
    {
        var cache = new LinkSlotCache();
        cache.Learn(new LinkSlot(4, false, 0), T0);

        var readBack = cache.Learn(null, T1); // empty/failed read

        Assert.False(readBack);
        Assert.Equal(4, cache.Slot!.Slot);
        Assert.Equal(T0, cache.LearnedAt); // unchanged when read yields null
    }

    [Fact]
    public void Cache_Reset_ClearsSlotAndLearnedAt()
    {
        var cache = new LinkSlotCache();
        cache.Learn(new LinkSlot(2, false, 0), T0);
        cache.Reset();

        Assert.Null(cache.Slot);
        Assert.Null(cache.LearnedAt);

        var readBack = cache.Learn(new LinkSlot(2, false, 0), T1);
        Assert.False(readBack); // initial learn again after reset
    }

    // --- T035 [US3]: old firmware (no AA4) never fabricates (parity with macOS) ---

    [Fact]
    public void Derive_NoAA4_NeverFabricates_Exhaustive()
    {
        // A new app against old firmware (AA4 absent) MUST degrade to
        // CannotDetermine for every active/local/output combination — never
        // InUseHere / ActiveElsewhere without AA4 (FR-008, C-L2).
        for (byte active = 0; active <= 4; active++)
        {
            for (byte local = 0; local <= 4; local++)
            {
                var status = HostContextStatus.DeriveLocalHostStatus(
                    hasAA4: false, connected: true,
                    capability: Cap(hasOutputEndpoint: false),
                    activeProfile: Profile(active),
                    localSlot: new LinkSlot(local, false, 0), output: Ble);
                Assert.Equal(LocalHostStatus.CannotDetermine, status);
            }
        }
    }

    [Fact]
    public void Derive_NoAA4_StillHonoursDisconnectedAndUsb()
    {
        Assert.Equal(LocalHostStatus.Disconnected,
            HostContextStatus.DeriveLocalHostStatus(
                hasAA4: false, connected: false, capability: Cap(),
                activeProfile: Profile(1), localSlot: null, output: Ble));
        Assert.Equal(LocalHostStatus.OnUsb,
            HostContextStatus.DeriveLocalHostStatus(
                hasAA4: false, connected: true, capability: Cap(hasOutputEndpoint: true),
                activeProfile: Profile(1), localSlot: null, output: Usb));
    }

    // --- T045 [Phase 7]: HostStatusVisual five-state encoding (V-1/V-4) ---

    [Fact]
    public void Visual_Exhaustive_FiveStates()
    {
        // Colour + symbol single source of truth (host-status-visual.md V-1).
        // Parity with macOS testVisual_exhaustive_fiveStates.
        Assert.Equal(new HostStatusVisual(HostStatusColor.Green, "●"),
            HostStatusVisual.For(LocalHostStatus.InUseHere));
        Assert.Equal(new HostStatusVisual(HostStatusColor.Orange, "◐"),
            HostStatusVisual.For(LocalHostStatus.ActiveElsewhere(3)));
        Assert.Equal(new HostStatusVisual(HostStatusColor.Blue, "◆"),
            HostStatusVisual.For(LocalHostStatus.OnUsb));
        Assert.Equal(new HostStatusVisual(HostStatusColor.Gray, "○"),
            HostStatusVisual.For(LocalHostStatus.CannotDetermine));
        Assert.Equal(new HostStatusVisual(HostStatusColor.Red, "✕"),
            HostStatusVisual.For(LocalHostStatus.Disconnected));
    }

    [Fact]
    public void Visual_DisconnectedIsRed_NotGray_DistinctFromCannotDetermine()
    {
        // V-2.3: "not connected" reads as an alarm (red), never the grey unknown.
        Assert.Equal(HostStatusColor.Red, HostStatusVisual.For(LocalHostStatus.Disconnected).Color);
        Assert.NotEqual(HostStatusVisual.For(LocalHostStatus.Disconnected),
            HostStatusVisual.For(LocalHostStatus.CannotDetermine));
    }

    [Fact]
    public void Visual_ColoursAreUniquePerState()
    {
        var all = new[]
        {
            LocalHostStatus.InUseHere, LocalHostStatus.ActiveElsewhere(2),
            LocalHostStatus.OnUsb, LocalHostStatus.CannotDetermine, LocalHostStatus.Disconnected,
        };
        var colors = all.Select(s => HostStatusVisual.For(s).Color).ToList();
        Assert.Equal(all.Length, colors.Distinct().Count());
        Assert.Equal(HostStatusColor.Blue, HostStatusVisual.For(LocalHostStatus.OnUsb).Color);
        Assert.Equal(HostStatusColor.Orange, HostStatusVisual.For(LocalHostStatus.ActiveElsewhere(1)).Color);
    }
}
