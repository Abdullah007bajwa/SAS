# K50 SDK connectivity probe (run from k50-bridge folder)
param(
    [string]$Ip = "192.168.100.18",
    [int]$Port = 4370,
    [string]$User = "1001"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "Running K50 probe against ${Ip}:${Port} user=$User" -ForegroundColor Cyan
dotnet run --project "K50Bridge\K50Bridge.csproj" -c Release -p:Platform=x86 -- `
    --probe --ip $Ip --port $Port --user $User

exit $LASTEXITCODE
