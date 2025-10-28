@echo off
title Windows 11 Modular Upgrade Launcher (Inline Mode)
color 0A
setlocal enableextensions

set "root=C:\Win11Upgrade"
set "repo=%root%\project-711-d"
set "backup=C:\project-711-d"
set "log=%root%\UpgradeLauncher.log"

echo ============================================================ > "%log%"
echo [INFO] Starting Inline UpgradeLauncher at %date% %time% >> "%log%"
echo [INFO] Root Folder: %root% >> "%log%"
echo [INFO] Repo Folder: %repo% >> "%log%"
echo [INFO] Backup Folder: %backup% >> "%log%"
echo ============================================================ >> "%log%"
echo. >> "%log%"

:: --- Verify repo folder exists ---
if not exist "%repo%\" (
    echo [ERROR] Repo folder not found at "%repo%" >> "%log%"
    echo [ERROR] Repo folder not found at "%repo%"
    exit /b 1
)
echo [INFO] Repo found. >> "%log%"

:: --- Ensure backup path exists ---
if not exist "%backup%\" (
    echo [INFO] Creating backup folder %backup% >> "%log%"
    mkdir "%backup%" >> "%log%" 2>&1
)

:: --- Copy repo contents ---
echo [INFO] Copying repo to "%backup%" (mirroring) ... >> "%log%"
robocopy "%repo%" "%backup%" /MIR /NFL /NDL /NJH /NJS >> "%log%" 2>&1
set "rcode=%errorlevel%"
if %rcode% LSS 8 (
    echo [INFO] Repo copy succeeded (code %rcode%). >> "%log%"
) else (
    echo [ERROR] robocopy failed with code %rcode%. >> "%log%"
)
echo. >> "%log%"

:: --- Run Stage 1: Download-ISO.ps1 ---
echo [INFO] Running Stage 1: Download-ISO.ps1 >> "%log%"
powershell -ExecutionPolicy Bypass -NoProfile -Command ^
    "Write-Host 'Stage 1 starting'; & '%repo%\Download-ISO.ps1'; exit $LASTEXITCODE" >> "%log%" 2>&1
if %errorlevel% NEQ 0 (
    echo [ERROR] Stage 1 failed (%errorlevel%). >> "%log%"
    exit /b %errorlevel%
)
echo [INFO] Stage 1 completed. >> "%log%"

:: --- Run Stage 2: Extract-ISO.ps1 ---
echo [INFO] Running Stage 2: Extract-ISO.ps1 >> "%log%"
powershell -ExecutionPolicy Bypass -NoProfile -Command ^
    "Write-Host 'Stage 2 starting'; & '%repo%\Extract-ISO.ps1'; exit $LASTEXITCODE" >> "%log%" 2>&1
if %errorlevel% NEQ 0 (
    echo [ERROR] Stage 2 failed (%errorlevel%). >> "%log%"
    exit /b %errorlevel%
)
echo [INFO] Stage 2 completed. >> "%log%"

:: --- Run Stage 3: Launch-Upgrade.ps1 ---
echo [INFO] Running Stage 3: Launch-Upgrade.ps1 >> "%log%"
powershell -ExecutionPolicy Bypass -NoProfile -Command ^
    "Write-Host 'Stage 3 starting'; & '%repo%\Launch-Upgrade.ps1'; exit $LASTEXITCODE" >> "%log%" 2>&1
if %errorlevel% NEQ 0 (
    echo [ERROR] Stage 3 failed (%errorlevel%). >> "%log%"
    exit /b %errorlevel%
)
echo [INFO] Stage 3 completed. >> "%log%"

echo ============================================================ >> "%log%"
echo [INFO] All stages completed successfully. >> "%log%"
echo [INFO] Windows setup should now be running in the background. >> "%log%"
echo ============================================================ >> "%log%"

endlocal
exit /b 0
