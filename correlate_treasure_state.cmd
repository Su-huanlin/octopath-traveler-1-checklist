@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\correlate_treasure_state_log.txt"
if not exist "%OUT%" mkdir "%OUT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\correlate_treasure_state.ps1" > "%LOG%" 2>&1
type "%LOG%"
echo.
echo Outputs:
echo "%OUT%\treasure_state_map_guess.csv"
echo "%OUT%\treasure_state_map_guess_summary.txt"
pause
