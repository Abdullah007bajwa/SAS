# Stop school app, bridges, and scheduled tasks before Setup replaces Program Files.
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$control = Join-Path $here "school-process-control.ps1"
if (Test-Path $control) {
    . $control
    Stop-SchoolProcesses -WaitSeconds 2 -Quick
} else {
    foreach ($name in @('K50Bridge', 'school_attendance_portal')) {
        & taskkill /F /IM "$name.exe" /T 2>$null | Out-Null
    }
    Start-Sleep -Seconds 2
}
