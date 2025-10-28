@echo off
title Windows 11 In-Place Upgrade Handler
setlocal EnableDelayedExpansion

set "root=C:\Win11Upgrade"
set "log=%root%\RepoHandler.log"

echo [%date% %time%] --- RepoHandler.bat starting --- >> "%log%"

:: Ensure PowerShell exists
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] ERROR: PowerShell not found. >> "%log%"
    exit /b 1
)

:: Download Upgrade.ps1 if missing
if not exist "%root%\Upgrade.ps1" (
    echo [%date% %time%] Missing Upgrade.ps1, downloading... >> "%log%"
    powershell -ExecutionPolicy Bypass -NoProfile -Command ^
        "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/sctcoder1/project-711-d/main/Upgrade.ps1' -OutFile '%root%\Upgrade.ps1' -UseBasicParsing"
    echo [%date% %time%] Upgrade.ps1 downloaded. >> "%log%"
)

:: Verify file downloaded
if not exist "%root%\Upgrade.ps1" (
    echo [%date% %time%] ERROR: Failed to download Upgrade.ps1 >> "%log%"
    exit /b 1
)

:: Launch Upgrade.ps1 in detached background so it survives session exit
echo [%date% %time%] Launching Upgrade.ps1 (detached)... >> "%log%"
start "" /min powershell -ExecutionPolicy Bypass -NoProfile -File "%root%\Upgrade.ps1" >> "%log%" 2>&1

:: Add persistence in case Sophos kills session before upgrade completes
echo [%date% %time%] Adding RunOnce persistence for RepoHandler.bat... >> "%log%"
reg add HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce /v Win11RepoHandler /t REG_SZ /d "cmd.exe /c start /min C:\Win11Upgrade\RepoHandler.bat" /f >> "%log%" 2>&1

:: Optional cleanup trigger for post-upgrade
if exist "%root%\Cleanup.ps1" (
    echo [%date% %time%] Scheduling Cleanup.ps1 for post-reboot. >> "%log%"
    reg add HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce /v Win11Cleanup /t REG_SZ /d "powershell -ExecutionPolicy Bypass -File \"%root%\Cleanup.ps1\"" /f >> "%log%" 2>&1
)

echo [%date% %time%] --- RepoHandler.bat done --- >> "%log%"
exit /b 0
