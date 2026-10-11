@echo off
setlocal
set "BASE=D:\Unpacking game"
set "OUT=%BASE%\OctopathTrackerOutput"
set "LOG=%OUT%\run_log.txt"
set "HTML=%OUT%\octopath_collectibles.html"

if not exist "%OUT%" mkdir "%OUT%"
if exist "%LOG%" del "%LOG%"

echo Running Octopath tracker...
echo Running Octopath tracker...>"%LOG%"
echo Script: "%BASE%\octopath_tracker_generate.ps1">>"%LOG%"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BASE%\octopath_tracker_generate.ps1" >> "%LOG%" 2>&1
set "RC=%ERRORLEVEL%"
echo ExitCode: %RC%>>"%LOG%"

if exist "%HTML%" (
  echo Generated: "%HTML%"
  start "" "%HTML%"
) else (
  echo HTML was not generated. Log:
  type "%LOG%"
)

echo.
echo Log file: "%LOG%"
pause
