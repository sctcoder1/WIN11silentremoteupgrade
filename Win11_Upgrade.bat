@echo off
title Windows 11 In-Place Upgrade
color 0A
set "root=C:\Win11Upgrade"
:: locate extracted repo dir
for /f "delims=" %%D in ('dir "%root%" /b /ad ^| findstr /i "project-711-d"') do set "work=%root%\%%D"
set "ps1=%work%\Upgrade.ps1"
echo [%date% %time%] Starting Upgrade.ps1 >> "%root%\upgrade_runner.log"
powershell -ExecutionPolicy Bypass -NoProfile -File "%ps1%" >> "%root%\upgrade_runner.log" 2>&1
echo [%date% %time%] Upgrade.ps1 finished. >> "%root%\upgrade_runner.log"
exit /b 0
