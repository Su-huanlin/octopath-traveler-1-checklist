@echo off
setlocal
set "BASE=D:\Unpacking game"
set "LOG=%BASE%\OctopathTrackerOutput\probe_save_for_enemies_log.txt"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\probe_save_for_enemies.ps1" > "%LOG%" 2>&1
type "%LOG%"
echo.
echo Output: %BASE%\OctopathTrackerOutput\save_enemy_probe.txt
pause
