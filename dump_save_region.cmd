@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\dump_region_log.txt"
if not exist "%OUT%" mkdir "%OUT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\dump_save_region.ps1" > "%LOG%" 2>&1
type "%LOG%"
echo.
echo Output should be:
echo "%OUT%\treasure_region_hex.txt"
pause
