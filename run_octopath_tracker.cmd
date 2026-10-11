@echo off
setlocal
cd /d "%~dp0"
if exist "index.html" (
  start "" "%~dp0index.html"
) else (
  echo index.html missing. Run generate_portable_tracker.cmd first.
  pause
)
