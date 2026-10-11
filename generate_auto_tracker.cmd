@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\generate_auto_tracker_log.txt"
if not exist "%OUT%" mkdir "%OUT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\generate_auto_tracker.ps1" > "%LOG%" 2>&1
type "%LOG%"
if exist "%OUT%\octopath_collectibles_auto.html" start "" "%OUT%\octopath_collectibles_auto.html"
echo.
echo Outputs:
echo "%OUT%\octopath_collectibles_auto.html"
echo "%OUT%\octopath_collectibles_auto.csv"
pause
