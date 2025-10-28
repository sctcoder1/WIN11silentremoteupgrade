@echo off
title Windows 11 Repo Handler
color 0A
set "root=C:\Win11Upgrade"
set "ps1=%root%\RepoHandler.ps1"
echo [%date% %time%] Starting RepoHandler.ps1 >> "%root%\RepoHandler.log"
powershell -ExecutionPolicy Bypass -NoProfile -File "%ps1%" >> "%root%\RepoHandler.log" 2>&1
exit /b 0
