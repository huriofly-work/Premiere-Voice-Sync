@echo off
setlocal DisableDelayedExpansion
title Premiere Voice Sync - Remove panel
echo Dong Premiere Pro truoc khi go panel.
echo Thao tac se xoa panel, cache, model, backend GPU va log cua ban ZIP.
choice /C YN /N /M "Ban muon go sach ban ZIP panel? [Y/N]: "
if errorlevel 2 exit /b 0
if errorlevel 1 goto remove
exit /b 1
:remove
set "PVS_UNINSTALLER=%~dp0scripts\uninstall.ps1"
if not exist "%PVS_UNINSTALLER%" set "PVS_UNINSTALLER=%~dp0installer\uninstall.ps1"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%PVS_UNINSTALLER%"
set "PVS_EXIT=%ERRORLEVEL%"
echo.
if not "%PVS_EXIT%"=="0" echo Go panel khong thanh cong. Hay doc thong bao phia tren.
pause
exit /b %PVS_EXIT%
