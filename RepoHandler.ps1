# RepoHandler.ps1
$Root = "C:\Win11Upgrade"
$RepoZipUrl = "https://api.github.com/repos/sctcoder1/project-711-d/zipball/main"
$Zip = Join-Path $Root "repo.zip"
$Log = Join-Path $Root "RepoHandler.log"
$User = "WinUpgTemp"

function Log { param($m) ("[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m") | Out-File $Log -Append }

Log "RepoHandler started."

# If repo already extracted, skip download
$Existing = Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'project-711-d' } | Select-Object -First 1
if ($Existing) {
    Log "Repo already extracted at $($Existing.FullName). Skipping download."
    $WorkDir = $Existing.FullName
} else {
    if (Test-Path $Zip) { Log "Removing stale zip..."; Remove-Item $Zip -Force -ErrorAction SilentlyContinue }
    Log "Downloading repo zip..."
    try {
        Invoke-WebRequest -Uri $RepoZipUrl -OutFile $Zip -UseBasicParsing -TimeoutSec 0
    } catch {
        Log "ERROR downloading repo: $_"
        exit 1
    }
    Log "Extracting zip..."
    try {
        Expand-Archive -Path $Zip -DestinationPath $Root -Force
        Remove-Item $Zip -Force -ErrorAction SilentlyContinue
        $WorkDir = Get-ChildItem -Path $Root -Directory | Where-Object { $_.Name -match 'project-711-d' } | Select-Object -First 1
        if (-not $WorkDir) { Log "ERROR: Extracted folder not found."; exit 1 }
        $WorkDir = $WorkDir.FullName
    } catch {
        Log "ERROR extracting repo: $_"
        exit 1
    }
    Log "Repo extracted to $WorkDir"
}

# Ensure expected files exist
$Bat = Join-Path $WorkDir "Win11_Upgrade.bat"
if (-not (Test-Path $Bat)) { Log "ERROR: Win11_Upgrade.bat not found in repo ($Bat)"; exit 1 }

# Schedule Win11_Upgrade task (only if not present)
if (-not (Get-ScheduledTask -TaskName "Win11_Upgrade" -ErrorAction SilentlyContinue)) {
    Log "Scheduling Win11_Upgrade to run as $User..."
    $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min `"$Bat`""
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(30))
    $principal = New-ScheduledTaskPrincipal -UserId $User -RunLevel Highest
    try {
        Register-ScheduledTask -TaskName "Win11_Upgrade" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        Start-ScheduledTask -TaskName "Win11_Upgrade"
        Log "Win11_Upgrade scheduled and started."
    } catch {
        Log "ERROR scheduling Win11_Upgrade: $_"
        exit 1
    }
} else {
    Log "Win11_Upgrade task already exists. Skipping."
}

# Schedule cleanup at startup (if not already)
$CleanupBat = Join-Path $WorkDir "Cleanup.bat"
if (Test-Path $CleanupBat) {
    if (-not (Get-ScheduledTask -TaskName "Win11_Cleanup" -ErrorAction SilentlyContinue)) {
        Log "Scheduling Win11_Cleanup at startup..."
        $action2 = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min `"$CleanupBat`""
        $trigger2 = New-ScheduledTaskTrigger -AtStartup
        try {
            Register-ScheduledTask -TaskName "Win11_Cleanup" -Action $action2 -Trigger $trigger2 -RunLevel Highest -Force | Out-Null
            Log "Win11_Cleanup scheduled."
        } catch {
            Log "ERROR scheduling Win11_Cleanup: $_"
        }
    } else {
        Log "Win11_Cleanup task already exists. Skipping."
    }
} else {
    Log "WARNING: Cleanup.bat not found in repo; skipping cleanup scheduling."
}

Log "RepoHandler complete."
exit 0
