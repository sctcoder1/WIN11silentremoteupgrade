@echo off
setlocal enableextensions
set "root=C:\Win11Upgrade"
set "repo=%root%\project-711-d"
set "backup=C:\project-711-d"
set "log=%root%\UpgradeLauncher.log"

echo ============================================================ > "%log%"
echo [INFO] Starting UpgradeLauncher at %date% %time% >> "%log%"

:: Mirror repo
robocopy "%repo%" "%backup%" /MIR /NFL /NDL /NJH /NJS >> "%log%" 2>&1

:: Stage 1 – Download ISO
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -NoProfile -File "%repo%\Download-ISO.ps1" >> "%log%" 2>&1
if %errorlevel% neq 0 exit /b %errorlevel%

:: Stage 2 – Extract ISO
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -NoProfile -File "%repo%\Extract-ISO.ps1" >> "%log%" 2>&1
if %errorlevel% neq 0 exit /b %errorlevel%

:: Stage 3 – Launch Upgrade
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -NoProfile -File "%repo%\Launch-Upgrade.ps1" >> "%log%" 2>&1
if %errorlevel% neq 0 exit /b %errorlevel%

echo [INFO] All stages complete. >> "%log%"
endlocal
exit /b 0
