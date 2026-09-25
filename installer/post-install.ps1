# Runs after SchoolAttendance-Setup.exe installs files (Admin).
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "school-process-control.ps1")

$bridgeDir = Join-Path $InstallDir "K50Bridge"
$sdkX86 = Join-Path $bridgeDir "sdk\x86"
$bridgeExe = Join-Path $bridgeDir "K50Bridge.exe"
$registerTask = Join-Path $PSScriptRoot "register-k50-bridge-task.ps1"

function Ensure-ProgramDataLogDirs {
    $root = Join-Path $env:ProgramData "School Attendance Portal"
    foreach ($sub in @("K50Bridge\logs")) {
        $path = Join-Path $root $sub
        New-Item -ItemType Directory -Force -Path $path | Out-Null
        icacls $path /grant "Users:(OI)(CI)M" /T 2>$null | Out-Null
    }
}

Stop-SchoolProcesses -WaitSeconds 2
Ensure-ProgramDataLogDirs

try {
    Register-ZkComFromSdk -SdkFolder $sdkX86
} catch {
    Write-Warning "COM registration failed: $_"
    Write-Warning "Run 'Repair K50 Fingerprint' from Start Menu after install, or:"
    Write-Warning "  powershell -ExecutionPolicy Bypass -File `"$PSScriptRoot\repair-k50-com.ps1`""
}

if (Test-Path $bridgeExe) {
    & $registerTask -TaskName "SchoolAttendance-K50Bridge" -Exe $bridgeExe -WorkDir $bridgeDir
    Write-Host "School K50 Bridge registered and started on port 8787." -ForegroundColor Green
}

function Register-BridgeStartupShortcut {
    param([string]$InstallRoot)

    $allBridgesCmd = Join-Path $InstallRoot "start-all-k50-bridges.cmd"
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
    $sc.WorkingDirectory = $InstallRoot
    $sc.WindowStyle = 7
    $sc.Description = "Start School K50 fingerprint bridge in background"
    $sc.Save()
    Write-Host "Bridge startup shortcut created: $lnkPath" -ForegroundColor Green
}

Register-BridgeStartupShortcut -InstallRoot $InstallDir
