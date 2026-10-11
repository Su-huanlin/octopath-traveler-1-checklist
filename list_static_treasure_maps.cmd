@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\list_static_treasure_maps_log.txt"
if not exist "%OUT%" mkdir "%OUT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\list_static_treasure_maps.ps1" > "%LOG%" 2>&1
type "%LOG%"
echo.
echo Output:
echo "%OUT%\static_treasure_map_order.csv"
pause
