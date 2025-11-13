# === SETUP ===
$root = "C:\Win11Upgrade"
New-Item -ItemType Directory -Force -Path $root | Out-Null

$upgradePs1 = "$root\Win11Upgrade.ps1"
$launcherBat = "$root\Win11Launcher.bat"

# === DOWNLOAD PAYLOADS ===
Invoke-WebRequest "https://raw.githubusercontent.com/sctcoder1/sctwin11/refs/heads/main/Win11Upgrade.ps1" -OutFile $upgradePs1
Invoke-WebRequest "https://raw.githubusercontent.com/sctcoder1/project-711-d/refs/heads/main/Win11Launcher.bat" -OutFile $launcherBat

# === CREATE TASK ===
$taskName = "Win11Upgrade"
schtasks /delete /tn $taskName /f 2>$null | Out-Null

# Important: correct quoting so Task Scheduler parses properly
$action = """cmd.exe"" /c ""$launcherBat"""

schtasks /create `
    /tn $taskName `
    /tr $action `
    /sc once `
    /st 23:59 `
    /RL HIGHEST `
    /RU SYSTEM `
    /F | Out-Null

# === RUN TASK IMMEDIATELY ===
schtasks /run /tn $taskName | Out-Null

# === IMPORTANT: WAIT BEFORE EXITING ===
Start-Sleep -Seconds 10

# === LOG DONE ===
"Bootstrap completed at $(Get-Date)" | Out-File "$root\bootstrap.log"
