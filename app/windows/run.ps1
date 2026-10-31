<#
KeyBeacon one-click entry (Windows).

Every run: re-downloads the latest dev-session.ps1 from the feature branch,
then executes it against your local clone. Use this so you never have to
manually re-fetch the script after an update.

SETUP (once):
  cd C:\Users\adawy\Documents\kbd
  irm https://raw.githubusercontent.com/ykiewang/keybeacon/feat/windows-ble-probe/app/windows/run.ps1 -OutFile run.ps1

EVERY TIME AFTER:
  powershell -ExecutionPolicy Bypass -File .\run.ps1
  powershell -ExecutionPolicy Bypass -File .\run.ps1 -Mode probe
  powershell -ExecutionPolicy Bypass -File .\run.ps1 -Mode diag

PARAMS (passed through to dev-session.ps1):
  -RepoDir   local clone (default C:\Users\adawy\Documents\kbd\keybeacon)
  -Mode      all|build|test|probe|diag  (default all)
  -NoUpdate  skip git fetch/pull
  -Timeout   probe GATT timeout seconds (default 10)
  -Device    probe target device id
#>

[CmdletBinding()]
param(
    [string]$RepoDir = 'C:\Users\adawy\Documents\kbd\keybeacon',
    [ValidateSet('all','build','test','probe','diag')]
    [string]$Mode = 'all',
    [switch]$NoUpdate,
    [int]$Timeout = 10,
    [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$RawUrl = 'https://raw.githubusercontent.com/ykiewang/keybeacon/feat/windows-ble-probe/app/windows/dev-session.ps1'
$Self   = Join-Path $PSScriptRoot 'dev-session.ps1'

Write-Host "==> Updating dev-session.ps1 from GitHub" -ForegroundColor Cyan
try {
    $url = "$RawUrl`?v=$(Get-Random)"
    Invoke-WebRequest -Uri $url -OutFile $Self -UseBasicParsing
    Write-Host "  [OK]   dev-session.ps1 updated" -ForegroundColor Green
} catch {
    Write-Host "  [WARN] update download failed: $_" -ForegroundColor Yellow
    if (-not (Test-Path $Self)) {
        Write-Host "  [FAIL] no local copy and download failed; check proxy/network" -ForegroundColor Red
        exit 1
    }
    Write-Host "  [WARN] using existing local copy" -ForegroundColor Yellow
}

$childArgs = @('-ExecutionPolicy','Bypass','-File',$Self,'-RepoDir',$RepoDir,'-Mode',$Mode,'-Timeout',$Timeout)
if ($NoUpdate) { $childArgs += '-NoUpdate' }
if ($Device)   { $childArgs += @('-Device',$Device) }

& powershell @childArgs
exit $LASTEXITCODE
