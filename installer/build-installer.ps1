# Build SchoolAttendance-Setup.exe (Inno Setup wizard — app + K50 in one installer)
# Requires Inno Setup 6: https://jrsoftware.org/isdl.php

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$isccCandidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $iscc) {
    Write-Host "Inno Setup 6 not found." -ForegroundColor Red
    Write-Host "Install from: https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
    Write-Host "Then re-run: .\installer\build-installer.ps1" -ForegroundColor Yellow
    exit 1
}

$appExe = Join-Path $root "build\windows\x64\runner\Release\school_attendance_portal.exe"
$bridgeExe = Join-Path $root "k50-bridge\dist\K50Bridge-Client\K50Bridge.exe"

if (-not (Test-Path $appExe)) {
    Write-Host "Missing Windows build. Run: .\scripts\build-client-delivery.ps1" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $bridgeExe)) {
    Write-Host "Missing K50 package. Run: .\k50-bridge\build-client-package.ps1" -ForegroundColor Red
    exit 1
}

Write-Host "Compiling SchoolAttendance-Setup.exe ..." -ForegroundColor Cyan
& $iscc (Join-Path $PSScriptRoot "SchoolAttendance-Setup.iss")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$out = Join-Path $root "dist\client\SchoolAttendance-Setup.exe"
if (Test-Path $out) {
    $mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
    Write-Host "Ready: $out ($mb MB)" -ForegroundColor Green
    Write-Host "Complete all-in-one client installer created!" -ForegroundColor Green
}
