@echo off
title Windows 11 In-Place Upgrade Handler
setlocal EnableDelayedExpansion

set "root=C:\Win11Upgrade"
set "log=%root%\RepoHandler.log"

echo [%date% %time%] --- RepoHandler.bat starting --- >> "%log%"

:: Ensure PowerShell is ready
if not exist "%root%\Upgrade.ps1" (
    echo [%date% %time%] Missing Upgrade.ps1, downloading... >> "%log%"
    powershell -ExecutionPolicy Bypass -NoProfile -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/sctcoder1/project-711-d/main/Upgrade.ps1' -OutFile '%root%\Upgrade.ps1' -UseBasicParsing"
)

:: Run the main upgrade script
echo [%date% %time%] Launching Upgrade.ps1... >> "%log%"
powershell -ExecutionPolicy Bypass -NoProfile -File "%root%\Upgrade.ps1" >> "%log%" 2>&1

echo [%date% %time%] Upgrade.ps1 complete. >> "%log%"

:: Optional cleanup trigger
if exist "%root%\Cleanup.ps1" (
    echo [%date% %time%] Scheduling Cleanup.ps1 for post-reboot. >> "%log%"
    reg add HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce /v Win11Cleanup /t REG_SZ /d "powershell -ExecutionPolicy Bypass -File \"%root%\Cleanup.ps1\"" /f
)

echo [%date% %time%] --- RepoHandler.bat done --- >> "%log%"
exit /b 0
