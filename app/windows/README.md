# KeyBeacon Windows Client

Windows desktop client for KeyBeacon (KBP), mirroring the macOS app: a system
tray presence plus an always-on-top floating panel that shows the connected
keyboard's current layer, modifiers, and — for KBP 1.1 — connectivity and
battery.

Spec: [`specs/003-windows-desktop-client`](../../specs/003-windows-desktop-client).

## Layout

```
app/windows/
├── KeyBeacon.sln
├── src/
│   ├── KeyBeacon.Core/     net8.0 — pure KBP parsing, no platform deps, unit-tested
│   └── KeyBeacon.App/      net8.0-windows — WPF + WinRT BLE (tray, panel, diagnostics, i18n)
├── tests/
│   └── KeyBeacon.Core.Tests/   net8.0 — xUnit over the shared payload layouts
└── tools/
    └── KeyBeacon.Probe/    net8.0-windows — Phase 0 WinRT feasibility probe
```

`KeyBeacon.Core` re-implements the KBP parser (ported from the macOS
`BleWidgetCore`) with zero platform coupling, so it is testable without any
Bluetooth hardware. Only the BLE/UI layer needs Windows.

## Build & test (on Windows)

```powershell
cd app/windows
dotnet restore KeyBeacon.sln
dotnet build KeyBeacon.sln -c Release

# Pure-logic tests — no Bluetooth hardware required (SC-005):
dotnet test tests/KeyBeacon.Core.Tests/KeyBeacon.Core.Tests.csproj -c Release
```

### Phase 0 gate (run before shipping the client)

```powershell
dotnet run --project tools/KeyBeacon.Probe -c Release -- --json probe-run.json --verbose
```

Exit code `0` means P1–P5 passed and the implementation gate is open; `1` means
a blocking check failed — follow the fallback in
[`research.md §3`](../../specs/003-windows-desktop-client/research.md). Record the
verdict in `research.md §5`.

### Run the client

```powershell
dotnet run --project src/KeyBeacon.App -c Release
```

## Build constraint

> This repository is developed on macOS. The Windows sources here are
> **Windows-compilable but cannot be built, run, or BLE-tested on macOS**
> (WPF + WinRT require a Windows toolchain). The `KeyBeacon.Probe` gate and the
> end-to-end quickstart scenarios must be executed on a real Windows 10 (2004 /
> build 19041) or Windows 11 host with a reference KBP keyboard (Corne).

## Protocol

Wire behaviour is owned by [`protocol/README.md`](../../protocol/README.md). This
client is a consumer only — it never changes the wire contract (FR-012).
