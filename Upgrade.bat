@echo off
title Windows 11 In-Place Upgrade
color 0A

set "root=C:\Win11Upgrade"
set "ps1=%root%\Upgrade.ps1"
set "log=%root%\upgrade_runner.log"

echo [%date% %time%] Starting Upgrade Runner >> "%log%"
echo Running PowerShell script... >> "%log%"

:: Heartbeat (so Task Scheduler stays alive)
powershell -ExecutionPolicy Bypass -NoProfile -File "%ps1%" >> "%log%" 2>&1

echo [%date% %time%] Script completed. >> "%log%"
exit /b 0
