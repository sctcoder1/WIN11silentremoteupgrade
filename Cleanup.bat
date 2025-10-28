@echo off
set "root=C:\Win11Upgrade"
set "ps1=%root%\Cleanup.ps1"
powershell -ExecutionPolicy Bypass -NoProfile -File "%ps1%"
exit /b 0
