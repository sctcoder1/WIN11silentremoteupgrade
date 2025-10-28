# ==============================================================
# Upgrade.ps1 – Windows 10 → 11 In-Place Upgrade Orchestrator
# ==============================================================

$ErrorActionPreference = 'Continue'
$Root     = "C:\Win11Upgrade"
$LogFile  = Join-Path $Root "Upgrade.log"

function Log {
    param($m)
    $msg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m"
    try { Add-Content -Path $LogFile -Value $msg -ErrorAction SilentlyContinue }
    catch { Start-Sleep -Milliseconds 100; Add-Content -Path $LogFile -Value $msg -ErrorAction SilentlyContinue }
}

Log "Upgrade.ps1 started."

# --- Locate extracted repo ---
$RepoDir = (Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'project-711-d' } | Select-Object -First 1).FullName
if (-not $RepoDir) {
    Log "ERROR: Repo folder not found under $Root"
    exit 1
}

# --- ISO configuration ---
$IsoUrl    = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoFile   = Join-Path $Root "Win11_24H2_English_x64.iso"
$SetupDir  = Join-Path $Root "SetupFiles"
$SetupCfg  = Join-Path $Root "setupconfig.ini"

# --- Download ISO if missing ---
if (-not (Test-Path $IsoFile)) {
    Log "Downloading ISO from $IsoUrl..."
    try {
        Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoFile -UseBasicParsing -TimeoutSec 0
        Log "ISO downloaded successfully."
    } catch {
        Log "ERROR downloading ISO: $($_.Exception.Message)"
        exit 1
    }
} else {
    Log "ISO already present; skipping download."
}

# --- Extract setup files if needed ---
if (-not (Test-Path (Join-Path $SetupDir "setup.exe"))) {
    Log "Mounting ISO..."
    try {
        $disk = Mount-DiskImage -ImagePath $IsoFile -PassThru
        Start-Sleep -Seconds 3
        $drive = ($disk | Get-Volume).DriveLetter
        $src = "$drive`:"
        Log "Copying setup files from $src to $SetupDir..."
        robocopy $src $SetupDir /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
        Dismount-DiskImage -ImagePath $IsoFile
        Log "Setup files copied."
    } catch {
        Log "ERROR mounting/copying ISO: $($_.Exception.Message)"
        exit 1
    }
} else {
    Log "Setup files already available at $SetupDir."
}

# --- Create setupconfig.ini for bypass ---
@"
[SetupConfig]
BypassTPMCheck=1
BypassSecureBootCheck=1
BypassRAMCheck=1
BypassStorageCheck=1
BypassCPUCheck=1
DynamicUpdate=Disable
Telemetry=Disable
"@ | Out-File $SetupCfg -Encoding ascii -Force
Log "setupconfig.ini written."

# --- Determine if an interactive user is logged in ---
$active = (& quser 2>$null) -match "Active"
$NoUser = [string]::IsNullOrWhiteSpace(($active -join ''))

if ($NoUser) {
    Log "No active users detected — using auto reboot mode."
    $Arguments = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`""
} else {
    Log "Active user(s) detected — using /noreboot interactive mode."
    $Arguments = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`" /noreboot"
    try { & msg.exe * "A Windows 11 upgrade has been staged. Please reboot your PC to complete installation." } catch {}
}

# --- Locate setup.exe ---
$SetupExe = Join-Path $SetupDir "setup.exe"
if (-not (Test-Path $SetupExe)) {
    Log "ERROR: setup.exe not found at $SetupExe"
    exit 1
}

# --- Launch setup.exe safely (with ServiceUI support) ---
Log "Starting setup.exe..."
try {
    Log "Arguments: $Arguments"
    $ServiceUI = Join-Path $RepoDir "ServiceUI.exe"

    # Detect interactive user via explorer.exe
    $explorerProc = Get-WmiObject Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue
    $ActiveUser = if ($explorerProc) { ($explorerProc.GetOwner()).User } else { $null }

    if ((Test-Path $ServiceUI) -and $ActiveUser) {
        Log "Active user '$ActiveUser' detected — launching setup.exe via ServiceUI..."
        Start-Process -FilePath $ServiceUI -ArgumentList "-Process:explorer.exe `"$SetupExe`" $Arguments" -WorkingDirectory $SetupDir
    } elseif (-not $ActiveUser) {
        Log "No interactive user detected — running setup silently."
        Start-Process -FilePath $SetupExe -ArgumentList $Arguments -WorkingDirectory $SetupDir
    } elseif (-not (Test-Path $ServiceUI)) {
        Log "ServiceUI.exe not found — running setup normally."
        Start-Process -FilePath $SetupExe -ArgumentList $Arguments -WorkingDirectory $SetupDir
    }

    Log "setup.exe launched successfully (detached)."
}
catch {
    Log "ERROR running setup.exe: $($_.Exception.Message)"
    exit 1
}

# --- Register cleanup for next boot ---
$CleanupBat = Join-Path $RepoDir "Cleanup.bat"
if (Test-Path $CleanupBat) {
    try {
        if (-not (Get-ScheduledTask -TaskName "Win11_Cleanup" -ErrorAction SilentlyContinue)) {
            Log "Scheduling cleanup on startup..."
            $act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min `"$CleanupBat`""
            $trg = New-ScheduledTaskTrigger -AtStartup
            Register-ScheduledTask -TaskName "Win11_Cleanup" -Action $act -Trigger $trg -RunLevel Highest -Force | Out-Null
            Log "Cleanup scheduled."
        } else {
            Log "Cleanup task already exists — skipping."
        }
    } catch {
        Log "ERROR scheduling cleanup: $($_.Exception.Message)"
    }
} else {
    Log "WARNING: Cleanup.bat not found; skipping cleanup task."
}

Log "Upgrade.ps1 completed."
exit 0
