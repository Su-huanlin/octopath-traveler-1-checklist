@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\extract_treasure_arrays_log.txt"
if not exist "%OUT%" mkdir "%OUT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\extract_treasure_arrays.ps1" > "%LOG%" 2>&1
type "%LOG%"
echo.
echo Outputs:
echo "%OUT%\treasure_arrays_summary.csv"
echo "%OUT%\treasure_arrays_summary.txt"
pause
