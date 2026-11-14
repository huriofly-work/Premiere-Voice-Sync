@echo off
setlocal DisableDelayedExpansion
title Premiere Voice Sync - Setup panel
set "PVS_INSTALLER=%~dp0scripts\install.ps1"
if not exist "%PVS_INSTALLER%" set "PVS_INSTALLER=%~dp0installer\install.ps1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%PVS_INSTALLER%"
set "PVS_EXIT=%ERRORLEVEL%"
echo.
if not "%PVS_EXIT%"=="0" echo Thiet lap khong thanh cong. Hay doc thong bao phia tren.
pause
exit /b %PVS_EXIT%
