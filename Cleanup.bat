@echo off
set "root=C:\Win11Upgrade"
set "ps1=%~dp0Cleanup.ps1"
powershell -ExecutionPolicy Bypass -NoProfile -File "%ps1%"
exit /b 0
