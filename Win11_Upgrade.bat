@echo off
title Windows 11 In-Place Upgrade (3-Stage)
color 0A

set "root=C:\Win11Upgrade"
set "log=%root%\upgrade_runner.log"

echo ========================================================= >> "%log%"
echo [%date% %time%] Starting 3-Stage Windows 11 Upgrade >> "%log%"
echo ========================================================= >> "%log%"

:: Stage 1 - Download ISO
if exist "%root%\Download-ISO.ps1" (
    echo [%date% %time%] Running Stage 1 - Download-ISO.ps1 >> "%log%"
    powershell -ExecutionPolicy Bypass -NoProfile -File "%root%\Download-ISO.ps1" >> "%log%" 2>&1
) else (
    echo [%date% %time%] ERROR: Download-ISO.ps1 not found. >> "%log%"
    exit /b 1
)

:: Stage 2 - Extract ISO
if exist "%root%\Extract-ISO.ps1" (
    echo [%date% %time%] Running Stage 2 - Extract-ISO.ps1 >> "%log%"
    powershell -ExecutionPolicy Bypass -NoProfile -File "%root%\Extract-ISO.ps1" >> "%log%" 2>&1
) else (
    echo [%date% %time%] ERROR: Extract-ISO.ps1 not found. >> "%log%"
    exit /b 1
)

:: Stage 3 - Launch Upgrade
if exist "%root%\Launch-Upgrade.ps1" (
    echo [%date% %time%] Running Stage 3 - Launch-Upgrade.ps1 >> "%log%"
    powershell -ExecutionPolicy Bypass -NoProfile -File "%root%\Launch-Upgrade.ps1" >> "%log%" 2>&1
) else (
    echo [%date% %time%] ERROR: Launch-Upgrade.ps1 not found. >> "%log%"
    exit /b 1
)

echo [%date% %time%] All stages executed. Upgrade may now proceed in background. >> "%log%"
echo ========================================================= >> "%log%"
exit /b 0
