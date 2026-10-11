@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\generate_portable_tracker_log.txt"
if not exist "%OUT%" mkdir "%OUT%"
echo Regenerating tracker...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\generate_portable_tracker.ps1" > "%LOG%" 2>&1
if errorlevel 1 (
  echo FAILED - see %LOG%
  type "%LOG%"
  pause
  exit /b 1
)
type "%LOG%"
echo.
echo Verifying...
node "%OUT%\verify_after_build.js"
type "%OUT%\verify_result.txt"
echo.
echo Output: %OUT%\octopath_tracker_portable.html
if exist "%OUT%\octopath_tracker_portable.html" start "" "%OUT%\octopath_tracker_portable.html"
pause
