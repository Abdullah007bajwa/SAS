# Start K50 Bridge HTTP API (run from k50-bridge folder)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

Write-Host "Starting K50 Bridge API on http://0.0.0.0:8787" -ForegroundColor Cyan
dotnet run --project "K50Bridge\K50Bridge.csproj" -c Release -p:Platform=x86
