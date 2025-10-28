@echo off
REM Run the PowerShell orchestrator (runs elevated if needed)
powershell -ExecutionPolicy Bypass -NoProfile -File "C:\Win11Upgrade\Upgrade.ps1"
exit /b %errorlevel%
