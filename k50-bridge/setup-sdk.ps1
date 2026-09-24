# One-time ZKTeco SDK setup for k50-bridge — MUST run PowerShell as Administrator
param(
    [string]$SdkPath = "C:\ZKTecoSDK"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdkX86 = Join-Path $SdkPath "sdk\x86"
$zkDll = Join-Path $sdkX86 "zkemkeeper.dll"
$libDir = Join-Path $root "K50Bridge\lib"
$interopOut = Join-Path $libDir "Interop.zkemkeeper.dll"
$clsidPath = "HKCR\CLSID\{00853A19-BD51-419B-9269-2DABE57EB61F}\InprocServer32"

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

if (-not (Test-Path $zkDll)) {
    Write-Error "zkemkeeper.dll not found at $zkDll. Install Standalone SDK to C:\ZKTecoSDK first."
}

if (-not (Test-IsAdmin)) {
    Write-Host ""
    Write-Host "ERROR: This script must run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell or CMD -> Run as administrator, then:" -ForegroundColor Yellow
    Write-Host "  cd E:\GYM\Master-gym\k50-bridge" -ForegroundColor White
    Write-Host "  .\setup-sdk.ps1" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host "Running as Administrator - OK" -ForegroundColor Green

Write-Host "Registering zkemkeeper COM (ZKTeco official method: copy DLLs to SysWOW64 first)..." -ForegroundColor Cyan
$sysWow = Join-Path $env:Windir "SysWOW64"
Get-ChildItem -Path $sdkX86 -Filter "*.dll" -File | ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $sysWow -Force
}
$zkInSys = Join-Path $sysWow "zkemkeeper.dll"
cmd /c "`"$sysWow\regsvr32.exe`" /s `"$zkInSys`""
if (-not (Test-ComRegistered)) {
    Write-Host ""
    Write-Host "Automatic registration did not stick. Run this in Admin CMD:" -ForegroundColor Yellow
    Write-Host "  C:\Windows\SysWOW64\regsvr32.exe `"$zkInSys`"" -ForegroundColor White
    exit 1
}

Write-Host "COM registered OK." -ForegroundColor Green

$tlbimpCandidates = @(
    "${env:ProgramFiles(x86)}\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\TlbImp.exe",
    "${env:ProgramFiles(x86)}\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.8 Tools\x86\TlbImp.exe"
)
$tlbimp = $tlbimpCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $tlbimp) {
    Write-Error "TlbImp.exe not found. Install '.NET Framework 4.8 Developer Pack' or Windows SDK."
}

New-Item -ItemType Directory -Force -Path $libDir | Out-Null
Write-Host "Generating Interop assembly..." -ForegroundColor Cyan
& $tlbimp $zkDll /out:$interopOut /namespace:zkemkeeper

Write-Host ""
Write-Host "Verifying COM registration..." -ForegroundColor Cyan
cmd /c "reg query `"$clsidPath`""

Write-Host ""
Write-Host "Setup complete. Next (normal PowerShell):" -ForegroundColor Green
Write-Host "  cd E:\GYM\Master-gym\k50-bridge"
Write-Host "  dotnet build K50Bridge\K50Bridge.csproj -c Release -p:Platform=x86"
Write-Host '  .\run-probe.ps1 -Ip 192.168.100.18 -Port 4370 -User 1001'
