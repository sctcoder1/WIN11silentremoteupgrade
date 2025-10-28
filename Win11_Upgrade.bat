@echo off
title Windows 11 In-Place Upgrade Launcher
color 0A
setlocal enableextensions

echo.
echo ============================================================
echo     Windows 11 Upgrade - Automated Installer (Safe Launch)
echo ============================================================
echo.

:: --- Core paths ---
set "root=C:\Win11Upgrade"
set "repo=%root%\project-711-d"
:: Safe fallback copy of repo in root directory
set "backup=C:\project-711-d"

:: --- Verify repo folder exists ---
if not exist "%repo%\" (
    echo [ERROR] Repo folder not found at "%repo%"
    echo Ensure project-711-d is extracted under C:\Win11Upgrade
    pause
    exit /b 1
)

echo [INFO] Found repo at "%repo%"
echo.

:: --- Make sure Win11Upgrade exists ---
if not exist "%root%\" (
    echo Creating folder: "%root%"
    mkdir "%root%"
)

:: --- Copy repo to root (safety fallback) ---
echo Copying repo to "%backup%" for redundancy...
robocopy "%repo%" "%backup%" /MIR /NFL /NDL /NJH /NJS /NP >nul

if %errorlevel% GEQ 8 (
    echo [WARNING] robocopy returned errorlevel %errorlevel% (non-fatal)
) else (
    echo [INFO] Copy complete or up-to-date.
)
echo.

:: --- Launch PowerShell upgrade orchestrator ---
echo Launching PowerShell upgrade script...
echo ------------------------------------------------------------
powershell -ExecutionPolicy Bypass -NoProfile -Command ^
    "Write-Host '[INFO] Starting Upgrade.ps1...';" ^
    "Start-Process -FilePath 'powershell.exe' -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%repo%\Upgrade.ps1\"' -Verb RunAs"

echo ------------------------------------------------------------
echo [INFO] PowerShell Upgrade.ps1 launched.
echo [INFO] Check C:\Win11Upgrade\Upgrade.log for progress.
echo ------------------------------------------------------------
echo.

pause
endlocal
exit /b 0
