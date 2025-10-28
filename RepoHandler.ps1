# ==============================================================
# RepoHandler.ps1 - Windows 10 → 11 Upgrade Orchestrator
# ==============================================================

$ErrorActionPreference = 'Continue'
$Root = "C:\Win11Upgrade"

# ✅ Use the correct direct-download ZIP (not GitHub API)
$RepoZipUrl = "https://github.com/sctcoder1/project-711-d/archive/refs/heads/main.zip"

$Zip  = Join-Path $Root "repo.zip"
$Log  = Join-Path $Root "RepoHandler.log"
$User = "WinUpgTemp"

# --- Logging helper (non-locking, safe under multiple handles) ---
function Log {
    param($m)
    $t = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m"
    try { Add-Content -Path $Log -Value $t -ErrorAction SilentlyContinue }
    catch { Start-Sleep -Milliseconds 200; Add-Content -Path $Log -Value $t -ErrorAction SilentlyContinue }
}

Log "RepoHandler started under user: $env:USERNAME"

# --- Ensure working directory exists ---
if (-not (Test-Path $Root)) {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Log "Created working directory $Root"
}

# --- Reuse or download repository ---
$Existing = Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'project-711-d' } | Select-Object -First 1

if ($Existing) {
    $WorkDir = $Existing.FullName
    Log "Repo already extracted at $WorkDir. Skipping download."
}
else {
    if (Test-Path $Zip) { Remove-Item $Zip -Force -ErrorAction SilentlyContinue; Log "Removed stale zip." }

    Log "Downloading repo zip from $RepoZipUrl..."
    try {
        Invoke-WebRequest -Uri $RepoZipUrl -OutFile $Zip -UseBasicParsing -TimeoutSec 0
        Log "Download complete."
    } catch {
        Log "ERROR downloading repo: $($_.Exception.Message)"
        exit 1
    }

    # --- Verify file size to avoid GitHub HTML error ---
    $zipSize = (Get-Item $Zip).Length
    if ($zipSize -lt 200000) {
        Log "ERROR: Downloaded file too small ($zipSize bytes) — possible HTML error."
        exit 1
    }

    Log "Extracting zip..."
    try {
        Expand-Archive -Path $Zip -DestinationPath $Root -Force
        Remove-Item $Zip -Force -ErrorAction SilentlyContinue

        # Normalize extracted folder name (GitHub adds -main)
        $Extracted = Get-ChildItem -Path $Root -Directory | Where-Object { $_.Name -match 'project-711-d' } | Select-Object -First 1
        if ($Extracted) {
            $Normalized = Join-Path $Root "project-711-d"
            if (Test-Path $Normalized) { Remove-Item $Normalized -Recurse -Force -ErrorAction SilentlyContinue }
            Rename-Item -Path $Extracted.FullName -NewName "project-711-d" -ErrorAction SilentlyContinue
            $WorkDir = $Normalized
            Log "Repo folder renamed to consistent path: $WorkDir"
        } else {
            Log "ERROR: Could not locate extracted folder after Expand-Archive."
            exit 1
        }

        Start-Sleep -Seconds 20
        Log "Waiting 20s to ensure repo files are ready before scheduling."
    }
    catch {
        Log "ERROR extracting repo: $($_.Exception.Message)"
        exit 1
    }
}

# --- Ensure Win11_Upgrade.bat exists ---
$Bat = Join-Path $WorkDir "Win11_Upgrade.bat"
if (-not (Test-Path $Bat)) { Log "ERROR: Win11_Upgrade.bat missing ($Bat)"; exit 1 }

# --- Delete any stale Win11_Upgrade task first ---
try {
    Unregister-ScheduledTask -TaskName "Win11_Upgrade" -Confirm:$false -ErrorAction SilentlyContinue
    Log "Removed any existing Win11_Upgrade task."
} catch {}

# --- Schedule Win11_Upgrade to run as temp user ---
try {
    Log "Scheduling Win11_Upgrade to run as $User..."
    $Action   = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min `"$Bat`""
    $Trigger  = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(20))
    $Principal = New-ScheduledTaskPrincipal -UserId $User -RunLevel Highest
    Register-ScheduledTask -TaskName "Win11_Upgrade" -Action $Action -Trigger $Trigger -Principal $Principal -Force | Out-Null
    Start-ScheduledTask -TaskName "Win11_Upgrade"
    Log "Win11_Upgrade scheduled and started."
}
catch {
    Log "ERROR scheduling Win11_Upgrade: $($_.Exception.Message)"
    exit 1
}

# --- Schedule cleanup at startup (if found) ---
$CleanupBat = Join-Path $WorkDir "Cleanup.bat"
if (Test-Path $CleanupBat) {
    try {
        Unregister-ScheduledTask -TaskName "Win11_Cleanup" -Confirm:$false -ErrorAction SilentlyContinue
        $Action2  = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min `"$CleanupBat`""
        $Trigger2 = New-ScheduledTaskTrigger -AtStartup
        Register-ScheduledTask -TaskName "Win11_Cleanup" -Action $Action2 -Trigger $Trigger2 -RunLevel Highest -Force | Out-Null
        Log "Win11_Cleanup scheduled."
    } catch {
        Log "ERROR scheduling Win11_Cleanup: $($_.Exception.Message)"
    }
} else {
    Log "WARNING: Cleanup.bat not found in repo."
}

# --- Optional heartbeat flag for monitoring ---
"running" | Out-File (Join-Path $Root "Running.flag") -Force
Log "RepoHandler complete. Awaiting upgrade execution."
exit 0
