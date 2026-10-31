<#
KeyBeacon Windows dev-session script.

One entry point to: check prerequisites, clone/update the repo on the
feat/windows-ble-probe branch, build, run Core tests, run the Phase 0
BLE probe, and -- on any failure -- collect a diagnostic bundle to email back.

USAGE (Windows PowerShell 5.1 or PowerShell 7, native Windows terminal):

  # first time: fetch the script, then run it
  irm https://raw.githubusercontent.com/ykiewang/keybeacon/feat/windows-ble-probe/app/windows/dev-session.ps1 -OutFile dev-session.ps1
  powershell -ExecutionPolicy Bypass -File .\dev-session.ps1

  # subsequent runs (script self-updates with the repo)
  powershell -ExecutionPolicy Bypass -File .\dev-session.ps1

MODES:
  -Mode all    (default) update -> build -> test -> collect-on-failure
  -Mode build  update -> build solution only
  -Mode test   update -> build + Core tests
  -Mode probe  update -> build -> run Phase 0 probe (needs connected keyboard)
  -Mode diag   collect diagnostics only (no build); useful to ship environment info

PARAMS:
  -RepoDir   target clone directory (default $HOME\kbd\keybeacon)
  -NoUpdate  skip git fetch/pull (use code already on disk)
  -Timeout   probe per-op GATT timeout seconds (default 10)
  -Device    probe target DeviceInformation.Id (default: enumerate + pick first)

NOTES:
  - Do NOT run this from inside WSL. Run in a native Windows PowerShell/cmd window.
  - Git proxy must already work (git config --global http.proxy). Script only reports it.
#>

[CmdletBinding()]
param(
    [ValidateSet('all','build','test','probe','diag')]
    [string]$Mode = 'all',
    [string]$RepoDir = (Join-Path $HOME 'kbd\keybeacon'),
    [switch]$NoUpdate,
    [int]$Timeout = 10,
    [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE   = 'en'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO            = '1'
$RepoUrl  = 'https://github.com/ykiewang/keybeacon.git'
$Branch   = 'feat/windows-ble-probe'
$SlnPath  = 'app/windows/KeyBeacon.sln'
$TestProj = 'app/windows/tests/KeyBeacon.Core.Tests/KeyBeacon.Core.Tests.csproj'
$ProbeProj= 'app/windows/tools/KeyBeacon.Probe/KeyBeacon.Probe.csproj'

$Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$DiagDir  = Join-Path $env:TEMP "keybeacon-diag-$Stamp"
$DiagOn   = $true
$Failed   = $false
$Steps    = New-Object System.Collections.ArrayList

function Say  { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function OkM  { param($m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function ErrM { param($m) Write-Host "  [FAIL] $m" -ForegroundColor Red }

function Record {
    param($Name, $Code, $LogPath)
    [void]$Steps.Add([pscustomobject]@{
        step = $Name; exitCode = $Code; pass = ($Code -eq 0); log = $LogPath
    })
}

function Ensure-DiagDir {
    if (-not (Test-Path $DiagDir)) { New-Item -ItemType Directory -Path $DiagDir | Out-Null }
}

function Invoke-Native {
    param(
        [string]$Exe,
        [string[]]$ExeArgs,
        [string]$LogPath
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $all = & $Exe @ExeArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
    if ($LogPath) {
        $all | ForEach-Object { $_.ToString() } | Add-Content -Path $LogPath -Encoding UTF8
    }
    $all | ForEach-Object { Write-Host $_ }
    return $code
}

function Get-NativeOutput {
    param([string]$Exe, [string[]]$ExeArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = (& $Exe @ExeArgs 2>$null | Out-String).Trim()
    } finally {
        $ErrorActionPreference = $prev
    }
    return $out
}

function Collect-Diagnostics {
    Say "Collecting diagnostics -> $DiagDir"
    Ensure-DiagDir
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $envInfo = [ordered]@{
            timestamp     = (Get-Date).ToString('o')
            mode          = $Mode
            psVersion     = $PSVersionTable.PSVersion.ToString()
            computerName  = $env:COMPUTERNAME
            osCaption     = $os.Caption
            osVersion     = $os.Version
            osBuild       = $os.BuildNumber
            arch          = $env:PROCESSOR_ARCHITECTURE
            isWsl         = [bool]$env:WSL_DISTRO_NAME
        }
        ($envInfo | ConvertTo-Json -Depth 4) | Set-Content -Path (Join-Path $DiagDir 'environment.json') -Encoding UTF8
    } catch { Warn "environment.json failed: $_" }

    try { (& dotnet --info *>&1) | Set-Content -Path (Join-Path $DiagDir 'dotnet-info.txt') -Encoding UTF8 } catch { Warn "dotnet --info failed: $_" }
    try { (& dotnet --list-sdks *>&1) | Set-Content -Path (Join-Path $DiagDir 'dotnet-sdks.txt') -Encoding UTF8 } catch {}
    try { (& git --version *>&1)   | Set-Content -Path (Join-Path $DiagDir 'git-version.txt') -Encoding UTF8 } catch {}
    try {
        $proxy = (& git config --global --get http.proxy *>&1)
        $proxy | Set-Content -Path (Join-Path $DiagDir 'git-proxy.txt') -Encoding UTF8
    } catch {}

    if (Test-Path $RepoDir) {
        try { Set-Location $RepoDir } catch {}
        try { (& git rev-parse --abbrev-ref HEAD *>&1) | Set-Content (Join-Path $DiagDir 'git-branch.txt') -Encoding UTF8 } catch {}
        try { (& git log --oneline -10 *>&1) | Set-Content (Join-Path $DiagDir 'git-log.txt') -Encoding UTF8 } catch {}
        try { (& git status -sb *>&1) | Set-Content (Join-Path $DiagDir 'git-status.txt') -Encoding UTF8 } catch {}
    }

    # step summary
    ($Steps | ConvertTo-Json -Depth 4) | Set-Content -Path (Join-Path $DiagDir 'steps.json') -Encoding UTF8

    $outDir = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($outDir) -or -not (Test-Path $outDir)) { $outDir = $env:TEMP }
    $zipPath = Join-Path $outDir "keybeacon-diag-$Stamp.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    try {
        Compress-Archive -Path (Join-Path $DiagDir '*') -DestinationPath $zipPath -Force
        OkM "Diagnostic bundle: $zipPath"
        Write-Host ""
        Write-Host "Please send this file back for triage:" -ForegroundColor Yellow
        Write-Host "  $zipPath" -ForegroundColor Yellow
    } catch {
        Warn "zip failed ($_); raw diag dir: $DiagDir"
    }
    $ErrorActionPreference = $prev
    return $zipPath
}

function Check-Prereqs {
    Say "Checking prerequisites"
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $gate = $true

    $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $dotnet) {
        ErrM "dotnet not found. Install .NET 8 SDK: https://dotnet.microsoft.com/download"
        $gate = $false
    } else {
        $ver = (& dotnet --version *>&1)
        if ($ver -match '^8\.') { OkM ".NET SDK $ver" }
        else { Warn ".NET SDK is $ver (expected 8.x). Build may fail." ; $gate = $false }
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        ErrM "git not found. Install: https://git-scm.com/download/win"
        $gate = $false
    } else { OkM ("git " + ((Get-NativeOutput 'git' @('--version')) -replace '^git version ', '')) }

    if ($env:WSL_DISTRO_NAME) {
        ErrM "You are inside WSL ($env:WSL_DISTRO_NAME). Run this in NATIVE Windows PowerShell, not WSL."
        $gate = $false
    }

    $ErrorActionPreference = $prev
    return $gate
}

function Sync-Repo {
    Say "Syncing repo at $RepoDir"
    Ensure-DiagDir

    if (-not (Test-Path $RepoDir)) {
        Say "Cloning $RepoUrl"
        $code = Invoke-Native 'git' @('clone', $RepoUrl, $RepoDir) (Join-Path $DiagDir 'clone.log')
        if ($code -ne 0) { ErrM "git clone failed (proxy/network?)."; Record 'clone' $code (Join-Path $DiagDir 'clone.log'); return $false }
    }

    Set-Location $RepoDir
    if (-not $NoUpdate) {
        $code = Invoke-Native 'git' @('fetch', 'origin') (Join-Path $DiagDir 'fetch.log')
        if ($code -ne 0) { ErrM "git fetch failed."; Record 'fetch' $code (Join-Path $DiagDir 'fetch.log'); return $false }
    }

    $cur = Get-NativeOutput 'git' @('rev-parse', '--abbrev-ref', 'HEAD')
    if ($cur -ne $Branch) {
        $code = Invoke-Native 'git' @('checkout', $Branch) (Join-Path $DiagDir 'checkout.log')
        if ($code -ne 0) {
            $code = Invoke-Native 'git' @('checkout', '-b', $Branch, "origin/$Branch") (Join-Path $DiagDir 'checkout.log')
            if ($code -ne 0) { ErrM "Cannot switch to $Branch."; Record 'checkout' $code (Join-Path $DiagDir 'checkout.log'); return $false }
        }
    }

    if (-not $NoUpdate) {
        $code = Invoke-Native 'git' @('pull', '--ff-only', 'origin', $Branch) (Join-Path $DiagDir 'pull.log')
        if ($code -ne 0) { Warn "git pull --ff-only failed; continuing with local HEAD." }
    }

    $sha = Get-NativeOutput 'git' @('rev-parse', '--short', 'HEAD')
    OkM "On $Branch @ $sha"
    return $true
}

function Do-Build {
    Say "dotnet restore + build (Release)"
    $log = Join-Path $DiagDir 'build.log'
    $code = Invoke-Native 'dotnet' @('restore', $SlnPath) $log
    if ($code -ne 0) { Record 'restore' $code $log; return $false }

    $code = Invoke-Native 'dotnet' @('build', $SlnPath, '-c', 'Release', '--no-restore') $log
    if ($code -ne 0) { Record 'build' $code $log; return $false }
    Record 'build' 0 $log
    OkM "Build succeeded"
    return $true
}

function Do-Tests {
    Say "dotnet test (KeyBeacon.Core.Tests)"
    $log = Join-Path $DiagDir 'test.log'
    $code = Invoke-Native 'dotnet' @('test', $TestProj, '-c', 'Release', '--no-build') $log
    if ($code -ne 0) { Record 'test' $code $log; return $false }
    Record 'test' 0 $log
    OkM "All Core tests passed"
    return $true
}

function Do-Probe {
    Say "Running Phase 0 BLE probe (needs a connected KBP keyboard)"
    $log   = Join-Path $DiagDir 'probe.log'
    $json  = Join-Path $DiagDir 'probe-run.json'
    $probeArgs = @('run','--project', $ProbeProj, '-c','Release','--no-build','--','--verbose','--json', $json,'--timeout',$Timeout)
    if ($Device) { $probeArgs += @('--device', $Device) }

    $code = Invoke-Native 'dotnet' $probeArgs $log
    Record 'probe' $code $log

    if (Test-Path $json) {
        OkM "probe-run.json captured ($json)"
    }

    switch ($code) {
        0 { OkM "Probe PASS - gate open" }
        1 { ErrM "Probe FAIL - a blocking check (P1-P5) failed; see research.md section 3" }
        2 { Warn "Probe environment error (no adapter / no connected keyboard / permission)" }
        3 { Warn "Probe argument error" }
        default { Warn "Probe exit code $code" }
    }
    return ($code -eq 0)
}

# ---------------------------------------------------------------------------

try {
    if ($Mode -eq 'diag') {
        Collect-Diagnostics | Out-Null
        exit 0
    }

    if (-not (Check-Prereqs)) {
        $Failed = $true
        Collect-Diagnostics | Out-Null
        exit 2
    }

    if (-not (Sync-Repo)) { $Failed = $true; Collect-Diagnostics | Out-Null; exit 1 }

    if (-not (Do-Build)) { $Failed = $true; Collect-Diagnostics | Out-Null; exit 1 }

    if ($Mode -in @('test','all','probe')) {
        if (-not (Do-Tests)) { $Failed = $true }
    }

    if ($Mode -eq 'probe' -and -not $Failed) {
        if (-not (Do-Probe)) { $Failed = $true }
    }

    if ($Failed) {
        Collect-Diagnostics | Out-Null
        exit 1
    }

    Say "Done: all steps passed."
    if ($Mode -ne 'probe') {
        Write-Host "Next: run '.\dev-session.ps1 -Mode probe' with the keyboard connected." -ForegroundColor Yellow
    }
    exit 0
}
catch {
    ErrM "Unhandled error: $_"
    try { Collect-Diagnostics | Out-Null } catch {}
    exit 1
}
