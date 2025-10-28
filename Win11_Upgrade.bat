@echo off
title Windows 11 In-Place Upgrade (TempUser Safe Copy Mode)
color 0A
setlocal enableextensions

echo.
echo ============================================================
echo   Windows 11 Upgrade - Automated Installer (TempUser Mode)
echo ============================================================
echo.

:: --- Core paths ---
set "root=C:\Win11Upgrade"
set "repo=%root%\project-711-d"
set "backup=C:\project-711-d"
set "log=%root%\UpgradeLauncher.log"

:: --- Start logging ---
(
echo [INFO] ============================================================
echo [INFO] Starting Upgrade.bat at %date% %time%
echo [INFO] Root Folder: %root%
echo [INFO] Repo Folder: %repo%
echo [INFO] Backup Folder: %backup%
echo [INFO] ============================================================
echo.
) > "%log%"

:: --- Verify repo folder ---
if not exist "%repo%\" (
    echo [ERROR] Repo folder not found at "%repo%"
    echo [ERROR] Repo folder not found at "%repo%" >> "%log%"
    exit /b 1
)

echo [INFO] Found repo folder. >> "%log%"
echo [INFO] Found repo folder.

:: --- Ensure Win11Upgrade root exists ---
if not exist "%root%\" (
    echo [INFO] Creating %root%...
    mkdir "%root%" >> "%log%" 2>&1
)

:: --- Copy repo to root (safety fallback) ---
echo [INFO] Copying repo to "%backup%"...
echo [INFO] Copying repo to "%backup%"... >> "%log%"
robocopy "%repo%" "%backup%" /MIR /NFL /NDL /NJH /NJS /NP >> "%log%" 2>&1

if %errorlevel% GEQ 8 (
    echo [WARNING] robocopy returned errorlevel %errorlevel% (non-fatal)
    echo [WARNING] robocopy returned errorlevel %errorlevel% (non-fatal) >> "%log%"
) else (
    echo [INFO] Repo copy completed successfully.
    echo [INFO] Repo copy completed successfully. >> "%log%"
)

:: --- Launch PowerShell upgrade script directly ---
echo. >> "%log%"
echo [INFO] Launching PowerShell Upgrade.ps1... >> "%log%"
echo [INFO] Launching PowerShell Upgrade.ps1...
echo ------------------------------------------------------------ >> "%log%"

powershell -ExecutionPolicy Bypass -NoProfile -File "%repo%\Upgrade.ps1" >> "%log%" 2>&1

echo ------------------------------------------------------------ >> "%log%"
echo [INFO] PowerShell Upgrade.ps1 completed. >> "%log%"
echo [INFO] Logs available at %log% and %root%\Upgrade.log >> "%log%"

echo.
echo ============================================================
echo   Upgrade script complete. Check:
echo   %log%
echo   and %root%\Upgrade.log
echo ============================================================

endlocal
exit /b 0
