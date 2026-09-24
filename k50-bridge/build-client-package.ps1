# Build client delivery package — NO source code, NO dotnet on client PC.
# Run on YOUR build machine (needs .NET 8 SDK + Interop in K50Bridge\lib).
#
# Output:
#   dist\MasterGym-K50Bridge-Client.zip
#     K50Bridge.exe + runtime DLLs
#     sdk\x86\  (ZKTeco DLLs)
#     appsettings.json
#     Install.exe  (double-click as Admin — registers COM, startup task, starts bridge)
#
# Client steps:
#   1. Extract zip to C:\Program Files\MasterGym\K50Bridge  (or any folder)
#   2. Double-click Install.exe (approve Admin)
#   3. Edit appsettings.json -> K50 DeviceIp

param(
    [string]$OutDir = "",
    [string]$BundledSdk = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $root "dist\K50Bridge-Client"
}
if ([string]::IsNullOrWhiteSpace($BundledSdk)) {
    $BundledSdk = Join-Path $root "sdk\x86"
}

function Stop-K50BridgeBuildLock {
    foreach ($name in @('K50Bridge', 'K50BridgeSetup')) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($procs) {
            Write-Host "Stopping $($procs.Count) $name process(es)..." -ForegroundColor Yellow
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }

    # Also stop bridges launched from this repo's dist folder (dev runs).
    Get-CimInstance Win32_Process -Filter "Name='K50Bridge.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object {
            $path = $_.ExecutablePath
            if ($path -and ($path -like "*\k50-bridge\dist\*" -or $path -like "*\Master-gym\k50-bridge\*")) {
                Write-Host "Stopping K50Bridge from dist: $path" -ForegroundColor Yellow
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }

    Start-Sleep -Seconds 3

    $remaining = Get-Process -Name 'K50Bridge' -ErrorAction SilentlyContinue
    if ($remaining) {
        Write-Host "Force-stopping $($remaining.Count) remaining K50Bridge process(es)..." -ForegroundColor Yellow
        $remaining | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

function Copy-DirForArchive {
    param(
        [string]$SourceDir,
        [string]$StagingDir
    )

    if (Test-Path $StagingDir) {
        Remove-Item -Recurse -Force $StagingDir
    }
    New-Item -ItemType Directory -Force -Path $StagingDir | Out-Null

    # robocopy: exit codes 0-7 mean success
    & robocopy $SourceDir $StagingDir /E /R:2 /W:2 /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ge 8) {
        throw "Failed to stage K50Bridge output for zip (robocopy exit $rc)"
    }
    $global:LASTEXITCODE = 0
}

function Compress-DirZip {
    param(
        [string]$SourceDir,
        [string]$ZipPath
    )

    $staging = Join-Path $env:TEMP ("k50bridge-pack-" + [guid]::NewGuid().ToString("n"))
    try {
        Copy-DirForArchive -SourceDir $SourceDir -StagingDir $staging
        if (Test-Path $ZipPath) {
            Remove-Item -Force $ZipPath
        }
        Compress-Archive -Path "$staging\*" -DestinationPath $ZipPath -Force
    } finally {
        Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
    }
}

Stop-K50BridgeBuildLock

$interop = Join-Path $root "K50Bridge\lib\Interop.zkemkeeper.dll"
if (-not (Test-Path $interop)) {
    Write-Host "Interop.zkemkeeper.dll missing. Run install-reception.ps1 once on this PC first." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path (Join-Path $BundledSdk "zkemkeeper.dll"))) {
    Write-Host "Bundled SDK missing: $BundledSdk\zkemkeeper.dll" -ForegroundColor Red
    exit 1
}

Write-Host "Publishing K50Bridge (self-contained x86)..." -ForegroundColor Cyan
Stop-K50BridgeBuildLock
if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Push-Location $root
try {
    dotnet publish "K50Bridge\K50Bridge.csproj" `
        -c Release `
        -p:Platform=x86 `
        -r win-x86 `
        --self-contained true `
        -o $OutDir
    if ($LASTEXITCODE -ne 0) { throw "K50Bridge publish failed" }

    Write-Host "Publishing Install.exe (client installer)..." -ForegroundColor Cyan
    dotnet publish "K50BridgeSetup\K50BridgeSetup.csproj" `
        -c Release `
        -p:Platform=x86 `
        -r win-x86 `
        --self-contained true `
        -p:PublishSingleFile=true `
        -o $OutDir
    if ($LASTEXITCODE -ne 0) { throw "Install.exe publish failed" }
} finally {
    Pop-Location
}

# SDK beside exe (Install.exe copies to SysWOW64)
$targetSdk = Join-Path $OutDir "sdk\x86"
New-Item -ItemType Directory -Force -Path $targetSdk | Out-Null
Copy-Item -Path "$BundledSdk\*" -Destination $targetSdk -Force -Recurse

# Remove dev-only artifacts from client package
Get-ChildItem -Path $OutDir -Filter "*.pdb" -Recurse -File | Remove-Item -Force
Remove-Item -Force (Join-Path $OutDir "appsettings.Development.json") -ErrorAction SilentlyContinue

$configPath = Join-Path $OutDir "appsettings.json"
if (-not (Test-Path $configPath)) {
@'
{
  "K50": {
    "DeviceIp": "192.168.100.18",
    "FallbackDeviceIps": [],
    "DevicePort": 4370,
    "ApiPort": 8787
  },
  "Logging": {
    "LogLevel": {
      "Default": "Information"
    }
  }
}
'@ | Set-Content -Path $configPath -Encoding UTF8
}

@'
Master City Gym — K50 Bridge (client package)
============================================

This folder contains compiled binaries only. No source code. No Visual Studio required.

Install:
  1. Copy this entire folder to: C:\Program Files\MasterGym\K50Bridge
  2. Right-click Install.exe -> Run as administrator
  3. Edit appsettings.json and set K50 DeviceIp to your device IP

Flutter app bridge URL: http://127.0.0.1:8787

Test after install:
  curl http://127.0.0.1:8787/device/status

Support: Neural Nest
'@ | Set-Content -Path (Join-Path $OutDir "README-CLIENT.txt") -Encoding UTF8

$zipPath = Join-Path (Split-Path $OutDir -Parent) "MasterGym-K50Bridge-Client.zip"
Stop-K50BridgeBuildLock
Write-Host "Creating zip (via temp copy to avoid file locks)..." -ForegroundColor Cyan
Compress-DirZip -SourceDir $OutDir -ZipPath $zipPath

Write-Host ""
Write-Host "Client package ready:" -ForegroundColor Green
Write-Host "  Folder: $OutDir" -ForegroundColor White
Write-Host "  Zip:    $zipPath" -ForegroundColor White
Write-Host ""
Write-Host "Give the client ONLY the zip. They run Install.exe (not PowerShell scripts)." -ForegroundColor Yellow
