@echo off
title Windows 11 In-Place Upgrade Handler
setlocal EnableDelayedExpansion

set "root=C:\Win11Upgrade"
set "zip=%root%\repo.zip"
set "log=%root%\RepoHandler.log"
set "repo=%root%\project-711-d"
set "urlzip=https://github.com/sctcoder1/project-711-d/archive/refs/heads/main.zip"

echo [%date% %time%] --- RepoHandler.bat starting --- >> "%log%"

:: Ensure root directory exists
if not exist "%root%" (
    mkdir "%root%"
    echo [%date% %time%] Created %root%. >> "%log%"
)

:: Ensure PowerShell exists
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] ERROR: PowerShell not found. >> "%log%"
    exit /b 1
)

:: --- Download repository ZIP ---
echo [%date% %time%] Downloading repository ZIP... >> "%log%"
powershell -ExecutionPolicy Bypass -NoProfile -Command ^
    "Invoke-WebRequest -Uri '%urlzip%' -OutFile '%zip%' -UseBasicParsing" >> "%log%" 2>&1

:: Verify ZIP size
for %%A in ("%zip%") do set "size=%%~zA"
if not defined size (
    echo [%date% %time%] ERROR: ZIP download failed (no file size). >> "%log%"
    exit /b 1
)
if %size% LSS 200000 (
    echo [%date% %time%] ERROR: ZIP too small (%size% bytes) — download may have failed. >> "%log%"
    exit /b 1
)

:: --- Extract ZIP ---
echo [%date% %time%] Extracting repository... >> "%log%"
powershell -ExecutionPolicy Bypass -NoProfile -Command ^
    "Expand-Archive -Path '%zip%' -DestinationPath '%root%' -Force" >> "%log%" 2>&1
del /f /q "%zip%" >nul 2>&1

:: Rename extracted folder (GitHub adds -main)
for /d %%F in ("%root%\project-711-d-*") do (
    ren "%%F" "project-711-d" >nul 2>&1
)

if not exist "%repo%" (
    echo [%date% %time%] ERROR: Repo folder not found after extraction. >> "%log%"
    exit /b 1
)

echo [%date% %time%] Repo extracted successfully to %repo%. >> "%log%"

:: --- Ensure Upgrade.ps1 exists ---
if not exist "%repo%\Upgrade.ps1" (
    echo [%date% %time%] Missing Upgrade.ps1, downloading... >> "%log%"
    powershell -ExecutionPolicy Bypass -NoProfile -Command ^
        "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/sctcoder1/project-711-d/main/Upgrade.ps1' -OutFile '%repo%\Upgrade.ps1' -UseBasicParsing"
    echo [%date% %time%] Upgrade.ps1 downloaded. >> "%log%"
)

if not exist "%repo%\Upgrade.ps1" (
    echo [%date% %time%] ERROR: Failed to download Upgrade.ps1 >> "%log%"
    exit /b 1
)

:: --- Launch Upgrade.ps1 (detached background) ---
echo [%date% %time%] Launching Upgrade.ps1 (detached)... >> "%log%"
start "" /min powershell -ExecutionPolicy Bypass -NoProfile -File "%repo%\Upgrade.ps1" >> "%log%" 2>&1

:: --- Add persistence (RunOnce) for safety ---
echo [%date% %time%] Adding RunOnce persistence for RepoHandler.bat... >> "%log%"
reg add HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce /v Win11RepoHandler /t REG_SZ /d "cmd.exe /c start /min C:\Win11Upgrade\RepoHandler.bat" /f >> "%log%" 2>&1

:: --- Optional cleanup ---
if exist "%repo%\Cleanup.ps1" (
    echo [%date% %time%] Scheduling Cleanup.ps1 for post-reboot. >> "%log%"
    reg add HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce /v Win11Cleanup /t REG_SZ /d "powershell -ExecutionPolicy Bypass -File \"%repo%\Cleanup.ps1\"" /f >> "%log%" 2>&1
)

echo [%date% %time%] --- RepoHandler.bat done --- >> "%log%"
exit /b 0
