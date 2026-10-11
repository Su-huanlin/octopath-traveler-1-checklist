@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\generate_portable_tracker_log.txt"
if not exist "%OUT%" mkdir "%OUT%"

echo === Step 1: Regenerate HTML from game data ===
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\generate_portable_tracker.ps1" > "%LOG%" 2>&1
if errorlevel 1 (
  echo Generator FAILED. See log:
  type "%LOG%"
  pause
  exit /b 1
)
type "%LOG%"

echo.
echo === Step 2: Verify output ===
node "%OUT%\verify_after_build.js"
if errorlevel 1 (
  echo Verification FAILED. See %OUT%\verify_result.txt
  type "%OUT%\verify_result.txt"
  pause
  exit /b 1
)
type "%OUT%\verify_result.txt"

echo.
echo === Done ===
echo Open: %OUT%\octopath_tracker_portable.html
start "" "%OUT%\octopath_tracker_portable.html"
pause
