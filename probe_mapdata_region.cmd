@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\probe_mapdata_region_log.txt"
if not exist "%OUT%" mkdir "%OUT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\probe_mapdata_region.ps1" > "%LOG%" 2>&1
type "%LOG%"
echo.
echo Output:
echo "%OUT%\mapdata_region_probe.txt"
pause
