@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\diff_treasure_saves_log.txt"
if not exist "%OUT%" mkdir "%OUT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\diff_treasure_saves.ps1" > "%LOG%" 2>&1
type "%LOG%"
echo.
echo Outputs:
echo "%OUT%\treasure_save_diff.csv"
echo "%OUT%\treasure_save_diff.txt"
pause
