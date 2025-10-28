@echo off
title Windows 11 Modular Upgrade Launcher
color 0A
setlocal enableextensions

set "root=C:\Win11Upgrade"
set "repo=%root%\project-711-d"
set "backup=C:\project-711-d"
set "log=%root%\UpgradeLauncher.log"

echo.
echo ============================================================
echo   Windows 11 Modular Upgrade Launcher
echo ============================================================
echo.

(
echo [INFO] ============================================================
echo [INFO] Starting UpgradeLauncher at %date% %time%
echo [INFO] Root Folder: %root%
echo [INFO] Repo Folder: %repo%
echo [INFO] Backup Folder: %backup%
echo [INFO] ============================================================
echo.
) > "%log%"

:: ---------------------------------------------------------------------
:: 1️⃣ Copy repo for safety
:: ---------------------------------------------------------------------
if exist "%repo%\" (
    echo [INFO] Copying repo to "%backup%"... | tee -a "%log%"
    robocopy "%repo%" "%backup%" /MIR /NFL /NDL /NJH /NJS /NP >> "%log%" 2>&1
    echo [INFO] Repo copy done (errorlevel %errorlevel%) >> "%log%"
) else (
    echo [ERROR] Repo folder missing at "%repo%" >> "%log%"
    echo [ERROR] Repo folder missing at "%repo%"
    exit /b 1
)

:: ---------------------------------------------------------------------
:: 2️⃣ Run Download-ISO.ps1
:: ---------------------------------------------------------------------
echo [INFO] Running Stage 1: Download-ISO.ps1 >> "%log%"
powershell -ExecutionPolicy Bypass -NoProfile -File "%repo%\Download-ISO.ps1" >> "%log%" 2>&1
if %errorlevel% NEQ 0 (
    echo [ERROR] Stage 1 (Download-ISO.ps1) failed. >> "%log%"
    exit /b %errorlevel%
)

:: ---------------------------------------------------------------------
:: 3️⃣ Run Extract-ISO.ps1
:: ---------------------------------------------------------------------
echo [INFO] Running Stage 2: Extract-ISO.ps1 >> "%log%"
powershell -ExecutionPolicy Bypass -NoProfile -File "%repo%\Extract-ISO.ps1" >> "%log%" 2>&1
if %errorlevel% NEQ 0 (
    echo [ERROR] Stage 2 (Extract-ISO.ps1) failed. >> "%log%"
    exit /b %errorlevel%
)

:: ---------------------------------------------------------------------
:: 4️⃣ Run Launch-Upgrade.ps1
:: ---------------------------------------------------------------------
echo [INFO] Running Stage 3: Launch-Upgrade.ps1 >> "%log%"
powershell -ExecutionPolicy Bypass -NoProfile -File "%repo%\Launch-Upgrade.ps1" >> "%log%" 2>&1
if %errorlevel% NEQ 0 (
    echo [ERROR] Stage 3 (Launch-Upgrade.ps1) failed. >> "%log%"
    exit /b %errorlevel%
)

:: ---------------------------------------------------------------------
:: ✅ Done
:: ---------------------------------------------------------------------
echo [INFO] ============================================================ >> "%log%"
echo [INFO] Upgrade process triggered successfully. >> "%log%"
echo [INFO] Windows setup should now be running silently. >> "%log%"
echo [INFO] ============================================================ >> "%log%"

echo.
echo ============================================================
echo   All stages executed.
echo   Check "%log%" for details.
echo ============================================================
echo.

endlocal
exit /b 0
