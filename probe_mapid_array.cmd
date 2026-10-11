@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0probe_mapid_array.ps1"
echo.
echo --- done ---
pause
