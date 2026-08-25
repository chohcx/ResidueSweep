@echo off
setlocal
cd /d "%~dp0"
title ResidueSweep
powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0ResidueSweep.ps1"
if not errorlevel 1 exit /b 0
echo.
echo ResidueSweep exited with an error.
pause
exit /b 1
