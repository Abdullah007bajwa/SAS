@echo off
cd /d "%~dp0"
if exist "%~dp0start-k50-bridge.vbs" (
    wscript.exe "%~dp0start-k50-bridge.vbs"
) else (
    start "" /B "%~dp0K50Bridge.exe"
)
