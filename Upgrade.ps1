# ==============================================================
# Upgrade.ps1 – Windows 10 → 11 Fully Silent In-Place Upgrade
# Reliable ISO mount and extraction method
# ==============================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root      = "C:\Win11Upgrade"
$LogFile   = Join-Path $Root "Upgrade.log"
$IsoUrl    = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoFile   = Join-Path $Root "Win11_24H2_English_x64.iso"
$SetupDir  = Join-Path $Root "SetupFiles"
$SetupCfg  = Join-Path $Root "setupconfig.ini"

# ------------------------
# Logging + helpers
# ------------------------
function Log {
    param([string]$Message)
    $msg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    try   { Add-Content -Path $LogFile -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue }
    catch { Start-Sleep -Milliseconds 150; Add-Content -Path $LogFile -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue }
}

function Fail { param($m); Log "ERROR: $m"; exit 1 }

function Ensure-Folder { param($Path) if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null } }

# ------------------------
# Begin
# ------------------------
Ensure-Folder $Root
Log "Upgrade.ps1 started."

# --- Locate repo (optional for cleanup) ---
try {
    $RepoDir = (Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^project-711-d' } | Select-Object -First 1).FullName
    if ($RepoDir) { Log "Repo detected: $RepoDir" } else { Log "Repo not found (continuing anyway)." }
} catch { Log "Repo detection failed: $($_.Exception.Message)" }

# --- Download ISO if missing ---
if (-not (Test-Path $IsoFile)) {
    Log "Downloading ISO from $IsoUrl..."
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($IsoUrl, $IsoFile)
        Log "ISO downloaded successfully."
    } catch {
        Fail "Download failed: $($_.Exception.Message)"
    }
} else {
    Log "ISO already present; skipping download."
}

# --- Extract setup files from ISO (robust mount version) ---
Ensure-Folder $SetupDir
$SetupExe = Join-Path $SetupDir "setup.exe"

if (-not (Test-Path $SetupExe)) {
    Log "Mounting ISO..."
    try {
        $disk = Mount-DiskImage -ImagePath $IsoFile -PassThru -ErrorAction Stop
        Log "ISO mounted successfully. Waiting for volume..."
        $driveLetter = $null

        # Retry loop to ensure the volume is ready
        for ($i = 1; $i -le 15; $i++) {
            $vol = $disk | Get-Volume -ErrorAction SilentlyContinue
            if ($vol -and $vol.DriveLetter) {
                $driveLetter = $vol.DriveLetter
                break
            }
            Start-Sleep -Seconds 2
        }

        if (-not $driveLetter) {
            Fail "Timeout waiting for ISO volume — could not detect drive letter."
        }

        $src = "$driveLetter`:"
        Log "Copying setup files from $src to $SetupDir..."
        Ensure-Folder $SetupDir
        robocopy $src $SetupDir /E /NFL /NDL /NJH /NJS /NP | Out-Null
        Log "Setup files copied successfully."

        Dismount-DiskImage -ImagePath $IsoFile -ErrorAction SilentlyContinue
        Log "ISO dismounted."
    } catch {
        Fail "ISO mount or copy failed: $($_.Exception.Message)"
    }
} else {
    Log "Setup files already available at $SetupDir."
}

# --- Validate setup.exe ---
if (-not (Test-Path $SetupExe)) {
    Fail "setup.exe still not found after extraction. Verify ISO integrity."
}
Log "setup.exe located at $SetupExe."

# --- Create setupconfig.ini (bypass checks) ---
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

# --- Build silent upgrade command ---
$Args = '/auto upgrade /quiet /noreboot /dynamicupdate disable /compat IgnoreWarning /Telemetry Disable /eula Accept /unattend "' + $SetupCfg + '"'

# --- Launch setup.exe silently ---
Log "Starting setup.exe silently..."
try {
    Log "Arguments: $Args"
    Start-Process -FilePath $SetupExe -ArgumentList $Args -WorkingDirectory $SetupDir
    Log "setup.exe launched (detached, fully silent)."
} catch {
    Fail "Failed to launch setup.exe: $($_.Exception.Message)"
}

# --- Optional cleanup scheduling ---
if ($RepoDir) {
    $CleanupBat = Join-Path $RepoDir "Cleanup.bat"
    if (Test-Path $CleanupBat) {
        try {
            if (-not (Get-ScheduledTask -TaskName "Win11_Cleanup" -ErrorAction SilentlyContinue)) {
                Log "Scheduling cleanup on startup..."
                $act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument ("/c start /min `"" + $CleanupBat + "`"")
                $trg = New-ScheduledTaskTrigger -AtStartup
                Register-ScheduledTask -TaskName "Win11_Cleanup" -Action $act -Trigger $trg -RunLevel Highest -Force | Out-Null
                Log "Cleanup scheduled."
            } else {
                Log "Cleanup task already exists."
            }
        } catch {
            Log "Failed to schedule cleanup: $($_.Exception.Message)"
        }
    } else {
        Log "Cleanup.bat not found — skipping cleanup task."
    }
}

Log "Upgrade.ps1 completed — Windows setup now running in background."
exit 0
