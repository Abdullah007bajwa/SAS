# School Attendance Portal - full client delivery build (run on Windows build PC).
# Produces unified installer and packages in dist\client\ for client delivery.
#
# Usage:
#   .\scripts\build-client-delivery.ps1

param(
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$clientDist = Join-Path $root "dist\client"
$k50Dist = Join-Path $root "k50-bridge\dist"

function Stop-BuildMemoryHogs {
    Write-Host "Stopping running instances for build..." -ForegroundColor Yellow
    foreach ($name in @('school_attendance_portal', 'K50Bridge', 'K50BridgeSetup')) {
        Get-Process -Name $name -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

Write-Host "=== School Attendance Portal client delivery build ===" -ForegroundColor Cyan
Write-Host "Root: $root" -ForegroundColor DarkGray

Stop-BuildMemoryHogs

Write-Host ""
Write-Host "Cleaning old client dist..." -ForegroundColor Yellow
if (Test-Path $clientDist) {
    Remove-Item -Recurse -Force $clientDist
}
New-Item -ItemType Directory -Force -Path $clientDist | Out-Null

Write-Host ""
Write-Host "[1/3] Flutter Windows Release..." -ForegroundColor Cyan
Push-Location $root
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
} finally {
    Pop-Location
}

$winRelease = Join-Path $root "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $winRelease "school_attendance_portal.exe"))) {
    throw "Windows build missing: $winRelease\school_attendance_portal.exe"
}
Write-Host "  Flutter Windows build complete." -ForegroundColor Green

Write-Host ""
Write-Host "[2/3] K50 Bridge client package..." -ForegroundColor Cyan
Push-Location (Join-Path $root "k50-bridge")
try {
    & (Join-Path $root "k50-bridge\build-client-package.ps1")
    if ($LASTEXITCODE -ne 0) { throw "K50 bridge package failed" }
} finally {
    Pop-Location
}
Write-Host "  K50 Bridge build complete." -ForegroundColor Green

if (-not $SkipInstaller) {
    Write-Host ""
    Write-Host "[3/3] Compiling unified Inno Setup installer..." -ForegroundColor Cyan
    & (Join-Path $root "installer\build-installer.ps1")
}

Write-Host ""
Write-Host "=== Client build complete ===" -ForegroundColor Green
Get-ChildItem $clientDist -ErrorAction SilentlyContinue | ForEach-Object {
    $mb = [math]::Round($_.Length / 1MB, 1)
    Write-Host ("  {0,-40} {1,8} MB" -f $_.Name, $mb) -ForegroundColor White
}
Write-Host ""
Write-Host "Deliverable: $clientDist\SchoolAttendance-Setup.exe" -ForegroundColor Green
