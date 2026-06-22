@echo off
setlocal
fltmc >nul 2>&1
if errorlevel 1 (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-WindowsNetwork.ps1" -Repair
set "RC=%ERRORLEVEL%"
echo.
echo Windows Network Repair finished with exit code %RC%.
pause
exit /b %RC%
