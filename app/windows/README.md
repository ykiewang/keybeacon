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

## Quick start (on Windows)

The repo ships `app/windows/dev-session.ps1` — a single entry point that
updates the repo, builds, runs Core tests, and on any failure collects a
diagnostic bundle to the desktop.

### First time

Open a **native Windows PowerShell** (not WSL). Confirm you have the right
environment:

```powershell
$env:WSL_DISTRO_NAME   # must be empty
where.exe dotnet       # must point to C:\Program Files\dotnet\dotnet.exe
```

If `dotnet` is missing, install .NET 8 SDK first:
https://dotnet.microsoft.com/download

Then fetch the script and run it:

```powershell
# download the script (proxy must already be configured if needed)
irm https://raw.githubusercontent.com/ykiewang/keybeacon/feat/windows-ble-probe/app/windows/dev-session.ps1 -OutFile dev-session.ps1
powershell -ExecutionPolicy Bypass -File .\dev-session.ps1
```

### Subsequent runs

```powershell
# update repo + build + Core tests
powershell -ExecutionPolicy Bypass -File .\dev-session.ps1

# build only (skip tests)
powershell -ExecutionPolicy Bypass -File .\dev-session.ps1 -Mode build

# Phase 0 BLE probe (keyboard must be connected)
powershell -ExecutionPolicy Bypass -File .\dev-session.ps1 -Mode probe

# collect diagnostics only (no build)
powershell -ExecutionPolicy Bypass -File .\dev-session.ps1 -Mode diag
```

On any failure the script writes `keybeacon-diag-<timestamp>.zip` to the
desktop. Send that file back for triage.

### Manual commands (without the script)

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

## Releasing (downloadable .exe)

Releases are built by GitHub Actions on a Windows runner — nothing is built or
copied from a local machine. The [`windows-release`](../../.github/workflows/windows-release.yml)
workflow produces a **self-contained single-file** `KeyBeacon.exe` (no .NET
runtime install required) for both **win-x64** and **win-arm64**, zips each with
a `.sha256`, and attaches them to the GitHub Release.

It rides the same `app-v*` tag as the macOS [`release`](../../.github/workflows/release.yml)
workflow, so one tag publishes a single Release carrying both platforms:

```bash
# cut a release (from any machine): tag a commit that contains the workflow
git tag app-v1.1.0
git push origin app-v1.1.0
```

Downloads land on the repo's **Releases** page as
`KeyBeacon-win-x64-<ver>.zip` / `KeyBeacon-win-arm64-<ver>.zip`. The Windows job
waits for the macOS job to create the Release, then uploads its assets to it
(`--clobber`), so there is no create-race; if no macOS release appears it creates
the Release itself.

**Dry run (no Release published):** Actions tab → *windows-release* → *Run
workflow* → optional version. The build runs and the `.exe` is attached to that
run as a downloadable **artifact**, so you can smoke-test a build before tagging.

> The tag's commit must contain `windows-release.yml`. Until it reaches `main`,
> tag a commit on the feature branch; afterwards tag `main` as usual.

## Build constraint

> This repository is developed on macOS. The Windows sources here are
> **Windows-compilable but cannot be built, run, or BLE-tested on macOS**
> (WPF + WinRT require a Windows toolchain). The `KeyBeacon.Probe` gate and the
> end-to-end quickstart scenarios must be executed on a real Windows 10 (2004 /
> build 19041) or Windows 11 host with a reference KBP keyboard (Corne).

## Protocol

Wire behaviour is owned by [`protocol/README.md`](../../protocol/README.md). This
client is a consumer only — it never changes the wire contract (FR-012).
