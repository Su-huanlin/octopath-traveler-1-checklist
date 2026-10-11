@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\treasure_blocks_probe_run_log.txt"
if not exist "%OUT%" mkdir "%OUT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\probe_treasure_blocks.ps1" > "%LOG%" 2>&1
type "%LOG%"
echo.
echo Output should be:
echo "%OUT%\treasure_blocks_probe.txt"
pause
