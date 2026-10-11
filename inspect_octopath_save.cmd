@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\save_probe_run_log.txt"

if not exist "%OUT%" mkdir "%OUT%"
if exist "%LOG%" del "%LOG%"

echo Inspecting SaveData1.sav...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\inspect_octopath_save.ps1" > "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
echo ExitCode: %RC%>>"%LOG%"

type "%LOG%"
echo.
echo Probe output:
echo "%OUT%\save_probe.txt"
pause
