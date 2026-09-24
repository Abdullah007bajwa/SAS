# DEPRECATED — use Install.exe from MasterGym-K50Bridge-Client.zip instead.
# Kept for developers only.

param(
    [string]$InstallDir = "$env:ProgramFiles\MasterGym\K50Bridge"
)

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-ComRegistered {
    $clsid = "{00853A19-BD51-419B-9269-2DABE57EB61F}"
    $paths = @(
        "HKLM\SOFTWARE\WOW6432Node\Classes\CLSID\$clsid\InprocServer32",
        "HKCR\CLSID\$clsid\InprocServer32"
    )
    foreach ($p in $paths) {
        cmd /c "reg query `"$p`" >nul 2>&1"
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    return $false
}

if (-not (Test-IsAdmin)) {
    Write-Host "Requesting Administrator approval..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -InstallDir `"$InstallDir`""
    exit 0
}

$sdkX86 = Join-Path $InstallDir "sdk\x86"
$exe = Join-Path $InstallDir "K50Bridge.exe"

if (-not (Test-Path $exe)) {
    Write-Host "K50Bridge.exe not found at $InstallDir" -ForegroundColor Red
    Write-Host "Extract the zip to that folder first." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path (Join-Path $sdkX86 "zkemkeeper.dll"))) {
    Write-Host "sdk\x86\zkemkeeper.dll missing in $InstallDir" -ForegroundColor Red
    exit 1
}

$sysWow = Join-Path $env:Windir "SysWOW64"
Write-Host "Copying SDK DLLs to SysWOW64..." -ForegroundColor Cyan
Get-ChildItem -Path $sdkX86 -Filter "*.dll" -File | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $sysWow -Force
}
cmd /c "`"$sysWow\regsvr32.exe`" /s `"$sysWow\zkemkeeper.dll`""

if (-not (Test-ComRegistered)) {
    Write-Host "COM registration failed." -ForegroundColor Red
    exit 1
}

$action = New-ScheduledTaskAction -Execute $exe -WorkingDirectory $InstallDir
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName "MasterGym-K50Bridge" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null

Start-Process -FilePath $exe -WorkingDirectory $InstallDir

Write-Host "K50Bridge installed. Runs on every startup." -ForegroundColor Green
Write-Host "Edit $InstallDir\appsettings.json for K50 IP." -ForegroundColor Yellow
