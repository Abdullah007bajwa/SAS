# Stop school app + K50 bridges so installer/COM registration can update locked files.
function Stop-SchoolScheduledTasks {
    foreach ($task in @(
            'SchoolAttendance-K50Bridge',
            'SchoolAttendance-K50Bridge2',
            'SchoolAttendance-App'
        )) {
        schtasks /End /TN $task /F 2>$null | Out-Null
        schtasks /Change /TN $task /DISABLE 2>$null | Out-Null
    }
}

function Stop-SchoolProcesses {
    param(
        [int]$WaitSeconds = 3,
        [switch]$Quick
    )

    Stop-SchoolScheduledTasks
    Start-Sleep -Seconds 1

    foreach ($name in @('K50Bridge', 'school_attendance_portal')) {
        & taskkill /F /IM "$name.exe" /T 2>$null | Out-Null
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($procs) {
            Write-Host "Stopping $name ($($procs.Count) process(es))..." -ForegroundColor Yellow
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $Quick) {
        $pathPatterns = @(
            '*\Program Files\School Attendance Portal\*',
            '*\Program Files (x86)\School Attendance Portal\*'
        )
        Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                if ($_.ProcessName -match '^(setup|setup64|unins\d+|SchoolAttendance-Setup)$') { return }
                $path = $_.Path
                if (-not $path) { return }
                foreach ($pattern in $pathPatterns) {
                    if ($path -like $pattern) {
                        Write-Host "Stopping locked process: $path" -ForegroundColor Yellow
                        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                        break
                    }
                }
            } catch {
                # Access denied for some system processes — ignore.
            }
        }

        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $cmd = $_.CommandLine
                if (-not $cmd) { return $false }
                return ($cmd -like '*\School Attendance Portal\*' -and
                    ($cmd -like '*start-all-k50-bridges*' -or $cmd -like '*start-k50-bridge*'))
            } |
            ForEach-Object {
                Write-Host "Stopping cmd child PID $($_.ProcessId)..." -ForegroundColor Yellow
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            }
    }

    if ($WaitSeconds -gt 0) {
        Start-Sleep -Seconds $WaitSeconds
    }
}

function Test-ZkComRegistered {
    $clsid = "{00853A19-BD51-419B-9269-2DABE57EB61F}"
    foreach ($p in @(
        "HKLM:\SOFTWARE\WOW6432Node\Classes\CLSID\$clsid\InprocServer32",
        "HKLM:\SOFTWARE\Classes\CLSID\$clsid\InprocServer32"
    )) {
        if (Test-Path $p) { return $true }
    }
    return $false
}

function Register-ZkComFromSdk {
    param([string]$SdkFolder)

    $zkSource = Join-Path $SdkFolder "zkemkeeper.dll"
    if (-not (Test-Path $zkSource)) {
        throw "ZKTeco SDK missing: $zkSource"
    }

    Stop-SchoolProcesses -WaitSeconds 2

    $sysWow = Join-Path $env:Windir "SysWOW64"
    $regsvr = Join-Path $sysWow "regsvr32.exe"
    $zkTarget = Join-Path $sysWow "zkemkeeper.dll"

    if (Test-Path $zkTarget) {
        cmd /c "`"$regsvr`" /u /s `"$zkTarget`"" 2>$null | Out-Null
        Start-Sleep -Seconds 1
    }

    Copy-Item -Path (Join-Path $SdkFolder "*") -Destination $sysWow -Force

    $out = cmd /c "`"$regsvr`" /s `"$zkTarget`"" 2>&1
    Start-Sleep -Seconds 1

    if (-not (Test-ZkComRegistered)) {
        throw "COM registration of zkemkeeper.dll failed in SysWOW64: $out"
    }
    Write-Host "ZKTeco COM registered successfully." -ForegroundColor Green
}
