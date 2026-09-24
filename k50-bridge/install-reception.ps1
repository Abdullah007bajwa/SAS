# Master City Gym — K50Bridge production installer
# Bundles SDK, publishes exe, registers COM, starts on every boot.
#
# Usage (double-click or PowerShell):
#   .\install-reception.ps1
# Auto re-launches as Administrator if needed.

param(
    [string]$InstallDir = "$env:ProgramFiles\MasterGym\K50Bridge",
    [string]$BundledSdk = "",
    [string]$SystemSdk = "C:\ZKTecoSDK",
    [switch]$SkipStartupTask,
    [switch]$NoElevate
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($BundledSdk)) {
    $BundledSdk = Join-Path $root "sdk\x86"
}

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

function Register-ZkSdkCom {
    param([string]$SdkX86Folder)

    $sysWow = Join-Path $env:Windir "SysWOW64"
    $zkInSys = Join-Path $sysWow "zkemkeeper.dll"

    Write-Host "Installing ZKTeco SDK DLLs to SysWOW64 (required by ZKTeco)..." -ForegroundColor Cyan
    Get-ChildItem -Path $SdkX86Folder -Filter "*.dll" -File | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $sysWow -Force
    }

    Write-Host "Registering COM: $zkInSys" -ForegroundColor Cyan
    cmd /c "`"$sysWow\regsvr32.exe`" /s `"$zkInSys`""

    if (-not (Test-ComRegistered)) {
        throw @"
COM registration failed.
Run this manually in Admin CMD:
  C:\Windows\SysWOW64\regsvr32.exe "C:\Windows\SysWOW64\zkemkeeper.dll"
"@
    }
    Write-Host "COM registered OK." -ForegroundColor Green
}

function Ensure-InteropDll {
    param([string]$ZkDllPath)

    $libDir = Join-Path $root "K50Bridge\lib"
    $interopOut = Join-Path $libDir "Interop.zkemkeeper.dll"
    if (Test-Path $interopOut) {
        Write-Host "Interop already exists: $interopOut" -ForegroundColor DarkGray
        return
    }

    $tlbimpCandidates = @(
        "${env:ProgramFiles(x86)}\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\TlbImp.exe",
        "${env:ProgramFiles(x86)}\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\x86\TlbImp.exe"
    )
    $tlbimp = $tlbimpCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $tlbimp) {
        throw "TlbImp.exe not found. Install .NET Framework 4.8 Developer Pack (build machine only)."
    }

    New-Item -ItemType Directory -Force -Path $libDir | Out-Null
    Write-Host "Generating Interop.zkemkeeper.dll..." -ForegroundColor Cyan
    & $tlbimp $ZkDllPath /out:$interopOut /namespace:zkemkeeper
}

function Register-StartupTask {
    param([string]$ExePath, [string]$WorkDir)

    $xmlPath = Join-Path $env:TEMP "MasterGym-K50Bridge.xml"
    @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <BootTrigger>
      <Delay>PT30S</Delay>
      <Enabled>true</Enabled>
    </BootTrigger>
    <LogonTrigger>
      <Enabled>true</Enabled>
    </LogonTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>$ExePath</Command>
      <WorkingDirectory>$WorkDir</WorkingDirectory>
    </Exec>
  </Actions>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>3</Count>
    </RestartOnFailure>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
  </Settings>
  <Principals>
    <Principal id="Author">
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
</Task>
"@ | Set-Content -Path $xmlPath -Encoding Unicode

    schtasks /Create /TN "MasterGym-K50Bridge" /XML $xmlPath /F | Out-Null
    Remove-Item -Force $xmlPath -ErrorAction SilentlyContinue
    Write-Host "Startup task registered: MasterGym-K50Bridge (boot + logon)" -ForegroundColor Green
}

function Wait-BridgeHealth {
    param([int]$TimeoutSeconds = 45)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-WebRequest -Uri "http://127.0.0.1:8787/health" -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Seconds 1
    }
    return $false
}

# --- Auto elevate ---
if (-not $NoElevate -and -not (Test-IsAdmin)) {
    Write-Host "Requesting Administrator approval..." -ForegroundColor Yellow
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($SkipStartupTask) { $argList += " -SkipStartupTask" }
    if ($InstallDir -ne "$env:ProgramFiles\MasterGym\K50Bridge") {
        $argList += " -InstallDir `"$InstallDir`""
    }
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argList
    exit 0
}

if (-not (Test-IsAdmin)) {
    Write-Host "ERROR: Administrator required. Right-click PowerShell -> Run as administrator." -ForegroundColor Red
    exit 1
}

Write-Host "Running as Administrator - OK" -ForegroundColor Green

# --- Resolve SDK ---
$sdkSource = $null
if (Test-Path (Join-Path $BundledSdk "zkemkeeper.dll")) {
    $sdkSource = $BundledSdk
    Write-Host "Using bundled SDK: $sdkSource" -ForegroundColor Cyan
} elseif (Test-Path (Join-Path $SystemSdk "sdk\x86\zkemkeeper.dll")) {
    $sdkSource = Join-Path $SystemSdk "sdk\x86"
    Write-Host "Using system SDK: $sdkSource" -ForegroundColor Cyan
} else {
    Write-Host "ZKTeco SDK not found." -ForegroundColor Red
    Write-Host "Copy ALL files from C:\ZKTecoSDK\sdk\x86\ to:" -ForegroundColor Yellow
    Write-Host "  $BundledSdk" -ForegroundColor White
    exit 1
}

$zkDll = Join-Path $sdkSource "zkemkeeper.dll"

# --- COM + interop (build machine) ---
Register-ZkSdkCom -SdkX86Folder $sdkSource
Ensure-InteropDll -ZkDllPath $zkDll

# --- Publish ---
Write-Host "Publishing K50Bridge to $InstallDir ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Push-Location $root
try {
    dotnet publish "K50Bridge\K50Bridge.csproj" `
        -c Release `
        -p:Platform=x86 `
        -r win-x86 `
        --self-contained true `
        -o $InstallDir
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

# --- Copy SDK beside exe (portable backup) ---
$targetSdk = Join-Path $InstallDir "sdk\x86"
New-Item -ItemType Directory -Force -Path $targetSdk | Out-Null
Copy-Item -Path "$sdkSource\*" -Destination $targetSdk -Force -Recurse

# --- appsettings ---
$configPath = Join-Path $InstallDir "appsettings.json"
if (-not (Test-Path $configPath)) {
    @'
{
  "K50": {
    "DeviceIp": "192.168.100.18",
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

$exe = Join-Path $InstallDir "K50Bridge.exe"

if (-not $SkipStartupTask) {
    Register-StartupTask -ExePath $exe -WorkDir $InstallDir
}

# --- Start now ---
Write-Host "Starting K50Bridge..." -ForegroundColor Cyan
Start-Process -FilePath $exe -WorkingDirectory $InstallDir

if (Wait-BridgeHealth -TimeoutSeconds 45) {
    Write-Host "K50Bridge is listening on http://127.0.0.1:8787" -ForegroundColor Green
} else {
    Write-Host "WARNING: K50Bridge did not respond yet. Run manually to see errors:" -ForegroundColor Yellow
    Write-Host "  $exe" -ForegroundColor White
}

Write-Host ""
Write-Host "Build client zip (no source): .\build-client-package.ps1" -ForegroundColor Cyan
Write-Host "Done." -ForegroundColor Green
Write-Host "  Install folder: $InstallDir" -ForegroundColor White
Write-Host "  Edit appsettings.json -> set K50 DeviceIp" -ForegroundColor Yellow
Write-Host "  Flutter bridge URL: http://127.0.0.1:8787" -ForegroundColor Yellow
Write-Host "  Test: curl http://127.0.0.1:8787/device/status" -ForegroundColor Yellow
