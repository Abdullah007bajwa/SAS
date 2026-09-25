# Repair ZKTeco COM + restart K50 bridge. Run as Administrator.
param(
    [string]$InstallDir = "$env:ProgramFiles\School Attendance Portal"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "school-process-control.ps1")

$bridgeDir = Join-Path $InstallDir "K50Bridge"
$sdkX86 = Join-Path $bridgeDir "sdk\x86"
$registerTask = Join-Path $PSScriptRoot "register-k50-bridge-task.ps1"

Write-Host "Repairing School K50 fingerprint COM registration..." -ForegroundColor Cyan
Register-ZkComFromSdk -SdkFolder $sdkX86

$bridgeExe = Join-Path $bridgeDir "K50Bridge.exe"

if (Test-Path $bridgeExe) {
    & $registerTask -TaskName "SchoolAttendance-K50Bridge" -Exe $bridgeExe -WorkDir $bridgeDir
}

$allBridgesCmd = Join-Path $InstallDir "start-all-k50-bridges.cmd"
if (-not (Test-Path $allBridgesCmd)) {
    @"
@echo off
if exist "%~dp0K50Bridge\start-k50-bridge.cmd" call "%~dp0K50Bridge\start-k50-bridge.cmd"
"@ | Set-Content -Path $allBridgesCmd -Encoding ASCII
}
$startup = [Environment]::GetFolderPath('CommonStartup')
$lnkPath = Join-Path $startup "School Attendance K50 Bridge.lnk"
$shell = New-Object -ComObject WScript.Shell
$sc = $shell.CreateShortcut($lnkPath)
$sc.TargetPath = $allBridgesCmd
$sc.WorkingDirectory = $InstallDir
$sc.WindowStyle = 7
$sc.Description = "Start School K50 fingerprint bridge in background"
$sc.Save()

Write-Host ""
Write-Host "Test connection:" -ForegroundColor Green
Write-Host "  curl.exe http://127.0.0.1:8787/device/status" -ForegroundColor White
