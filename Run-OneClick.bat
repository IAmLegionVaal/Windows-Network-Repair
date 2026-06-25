@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-WindowsNetwork.ps1"
set "RC=%ERRORLEVEL%"
echo.
echo Windows Network Diagnostics finished with exit code %RC%.
echo No repair action was performed by this launcher.
pause
exit /b %RC%
