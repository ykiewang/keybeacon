<#
KeyBeacon -- one-shot "I just want it to work" launcher.

Kills any running instance, syncs the repo, builds, clears the old crash log,
launches the client, waits, then tells you whether it stayed alive or crashed
(and dumps crash.log + the latest Serilog tail if it did).

USAGE (native Windows PowerShell 5.1 / 7 -- NOT WSL):

  irm https://raw.githubusercontent.com/ykiewang/keybeacon/feat/windows-ble-probe/app/windows/verify-app.ps1 -OutFile verify-app.ps1
  powershell -ExecutionPolicy Bypass -File .\verify-app.ps1

Re-run it anytime; it always pulls the latest fixes first.
#>

[CmdletBinding()]
param(
    [string]$RepoDir = 'C:\Users\adawy\Documents\kbd\keybeacon',
    [int]$WaitSeconds = 8,
    [switch]$NoPull
)

$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_UI_LANGUAGE     = 'en'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_NOLOGO              = '1'

$Branch  = 'feat/windows-ble-probe'
$AppProj = 'app/windows/src/KeyBeacon.App/KeyBeacon.App.csproj'
$LogDir  = Join-Path $env:LOCALAPPDATA 'KeyBeacon\logs'
$CrashLog = Join-Path $LogDir 'crash.log'
$Started = $false

function Say  { param($m) Write-Host "==> $m" -ForegroundColor Cyan }
function OkM  { param($m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function ErrM { param($m) Write-Host "  [FAIL] $m" -ForegroundColor Red }

function Invoke-Native {
    param([string]$Exe, [string[]]$ExeArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @ExeArgs 2>&1 | ForEach-Object { Write-Host $_ }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Get-NativeOutput {
    param([string]$Exe, [string[]]$ExeArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        return (& $Exe @ExeArgs 2>$null | Out-String).Trim()
    } finally {
        $ErrorActionPreference = $prev
    }
}

try {
    if ($env:WSL_DISTRO_NAME) {
        ErrM "This is WSL. Open a native Windows PowerShell window and run it there."
        exit 2
    }

    Say "Stopping any running KeyBeacon"
    Get-Process KeyBeacon -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 600
    OkM "old instances cleared"

    Say "Syncing repo at $RepoDir"
    if (-not (Test-Path $RepoDir)) {
        ErrM "Repo not found at $RepoDir. Clone it first (see dev-session.ps1), or pass -RepoDir."
        exit 1
    }
    Set-Location $RepoDir

    if (-not $NoPull) {
        $cur = Get-NativeOutput 'git' @('rev-parse', '--abbrev-ref', 'HEAD')
        if ($cur -ne $Branch) {
            [void](Invoke-Native 'git' @('checkout', $Branch))
        }
        [void](Invoke-Native 'git' @('fetch', 'origin'))
        $code = Invoke-Native 'git' @('pull', '--ff-only', 'origin', $Branch)
        if ($code -ne 0) { Warn "git pull failed; building current HEAD." }
    }
    $sha = Get-NativeOutput 'git' @('rev-parse', '--short', 'HEAD')
    OkM "on $Branch @ $sha"

    Say "Building the client (Release)"
    $code = Invoke-Native 'dotnet' @('build', $AppProj, '-c', 'Release')
    if ($code -ne 0) {
        ErrM "Build failed -- see the errors above."
        exit 1
    }
    OkM "build succeeded"

    Say "Clearing old crash log"
    if (Test-Path $CrashLog) { Remove-Item $CrashLog -Force -ErrorAction SilentlyContinue }
    OkM "crash.log reset"

    Say "Launching client (detached)"
    Start-Process -FilePath 'dotnet' -ArgumentList @('run','--project',$AppProj,'-c','Release','--no-build') | Out-Null
    $Started = $true

    Say "Waiting $WaitSeconds s for startup / BLE connect"
    Start-Sleep -Seconds $WaitSeconds

    $proc = Get-Process KeyBeacon -ErrorAction SilentlyContinue
    $crashed = Test-Path $CrashLog
    Write-Host ""
    Write-Host "==============================================" -ForegroundColor Cyan

    if ($proc -and -not $crashed) {
        OkM "KeyBeacon is RUNNING and crash.log is empty."
        Write-Host "  Look in the system tray for the 'K' icon, and check the floating panel for layer / battery rows." -ForegroundColor Green
    }
    elseif ($proc -and $crashed) {
        Warn "KeyBeacon is running BUT a crash was logged (likely a caught dispatcher/task exception)."
    }
    else {
        ErrM "KeyBeacon is NOT running -- it exited during startup."
    }

    if ($crashed) {
        Write-Host ""
        Write-Host "----- crash.log -----" -ForegroundColor Red
        Get-Content $CrashLog | Write-Host
        Write-Host "---------------------" -ForegroundColor Red
    }

    $today = Get-Date -Format 'yyyyMMdd'
    $slog = Join-Path $LogDir "keybeacon-$today.log"
    if (Test-Path $slog) {
        Write-Host ""
        Write-Host "----- latest Serilog (last 25 lines) -----" -ForegroundColor DarkGray
        Get-Content $slog -Tail 25 | Write-Host
        Write-Host "------------------------------------------" -ForegroundColor DarkGray
    }
    Write-Host "==============================================" -ForegroundColor Cyan

    if ($proc -and -not $crashed) { exit 0 } else { exit 1 }
}
catch {
    ErrM "Unhandled error: $_"
    exit 1
}
