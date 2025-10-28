# ==============================================================
# Upgrade.ps1 – Windows 10 → 11 Fully Silent In-Place Upgrade
# Safe extraction (no Mount-DiskImage required)
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

# --- Locate repo (for optional cleanup later) ---
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

# --- Extract setup files safely ---
Ensure-Folder $SetupDir
$SetupExe = Join-Path $SetupDir "setup.exe"

if (-not (Test-Path $SetupExe)) {
    Log "Extracting ISO contents without mounting..."
    try {
        Expand-Archive -Path $IsoFile -DestinationPath $SetupDir -Force -ErrorAction Stop
        Log "ISO extracted successfully using Expand-Archive."
    } catch {
        Log "Expand-Archive failed: $($_.Exception.Message)"
        Log "Attempting DISM or 7-Zip fallback..."

        # DISM fallback (if ISO is a real WIM image)
        try {
            dism /Mount-Image /ImageFile:$IsoFile /MountDir:$SetupDir /ReadOnly | Out-Null
            Log "DISM mount successful (read-only)."
        } catch {
            # Optional 7-Zip fallback if installed
            $SevenZip = "C:\Program Files\7-Zip\7z.exe"
            if (Test-Path $SevenZip) {
                try {
                    & $SevenZip x $IsoFile "-o$SetupDir" -y | Out-Null
                    Log "ISO extracted successfully using 7-Zip fallback."
                } catch {
                    Fail "7-Zip extraction failed: $($_.Exception.Message)"
                }
            } else {
                Fail "No valid extraction method available (Expand-Archive, DISM, 7-Zip all failed)."
            }
        }
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
