@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0probe_map_ordering.ps1"
echo.
echo --- done ---
pause
