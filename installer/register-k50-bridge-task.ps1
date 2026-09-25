# Register a K50 Bridge scheduled task: boot, logon, resume from sleep, session unlock.
param(
    [Parameter(Mandatory = $true)]
    [string]$TaskName,
    [Parameter(Mandatory = $true)]
    [string]$Exe,
    [Parameter(Mandatory = $true)]
    [string]$WorkDir
)

$ErrorActionPreference = "Stop"

$launcher = Join-Path $WorkDir "start-k50-bridge.cmd"
if (-not (Test-Path $launcher)) {
    @"
@echo off
cd /d "%~dp0"
start "" /B "%~dp0K50Bridge.exe"
"@ | Set-Content -Path $launcher -Encoding ASCII
}

# Task Scheduler: cmd /c "path with spaces\launcher.cmd"
$cmdArgs = '/c "' + $launcher + '"'

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <BootTrigger>
      <Delay>PT45S</Delay>
      <Enabled>true</Enabled>
    </BootTrigger>
    <LogonTrigger>
      <Delay>PT15S</Delay>
      <Enabled>true</Enabled>
    </LogonTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and (EventID=107)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
    <SessionStateChangeTrigger>
      <Enabled>true</Enabled>
      <StateChange>SessionUnlock</StateChange>
    </SessionStateChangeTrigger>
  </Triggers>
  <Actions Context="Author">
    <Exec>
      <Command>cmd.exe</Command>
      <Arguments>$cmdArgs</Arguments>
      <WorkingDirectory>$WorkDir</WorkingDirectory>
    </Exec>
  </Actions>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <RestartOnFailure>
      <Interval>PT1M</Interval>
      <Count>999</Count>
    </RestartOnFailure>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
  </Settings>
  <Principals>
    <Principal id="Author">
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
</Task>
"@

$path = Join-Path $env:TEMP "$TaskName.xml"
$xml | Set-Content -Path $path -Encoding Unicode
schtasks /Create /TN $TaskName /XML $path /F | Out-Null
Remove-Item -Force $path -ErrorAction SilentlyContinue

function Start-BridgeProcess {
    param([string]$BridgeExe, [string]$BridgeWorkDir, [int]$Port)

    if (-not (Test-Path $BridgeExe)) { return $false }

    $running = Get-Process -Name "K50Bridge" -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -eq $BridgeExe } catch { $false }
    }
    if ($running) { return $true }

    Start-Process -FilePath $BridgeExe -WorkingDirectory $BridgeWorkDir -WindowStyle Hidden
    Start-Sleep -Seconds 3

    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 8
        return $r.StatusCode -eq 200
    } catch {
        return $false
    }
}

Start-BridgeProcess -BridgeExe $Exe -BridgeWorkDir $WorkDir -Port $(if ($WorkDir -match 'K50Bridge2') { 8788 } else { 8787 }) | Out-Null
