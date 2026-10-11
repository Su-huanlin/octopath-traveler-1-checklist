@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0probe_enemy_layout.ps1" > "%~dp0OctopathTrackerOutput\probe_enemy_layout_log.txt" 2>&1
echo Done. See OctopathTrackerOutput\probe_enemy_layout_log.txt and OctopathTrackerOutput\save_enemy_layout.txt
pause
