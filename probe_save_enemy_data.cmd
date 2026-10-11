@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0probe_save_enemy_data.ps1" > "%~dp0OctopathTrackerOutput\probe_save_enemy_data_log.txt" 2>&1
echo Done. See OctopathTrackerOutput\probe_save_enemy_data_log.txt and enemy_save_probe.csv
pause
