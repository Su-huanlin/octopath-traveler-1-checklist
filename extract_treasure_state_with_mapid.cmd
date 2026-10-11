@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\extract_treasure_state_with_mapid_log.txt"
if not exist "%OUT%" mkdir "%OUT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\extract_treasure_state_with_mapid.ps1" > "%LOG%" 2>&1
type "%LOG%"
echo.
echo Output:
echo "%OUT%\treasure_state_with_mapid.csv"
pause
