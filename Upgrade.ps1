# ==============================================================
# Upgrade.ps1 – Windows 10 → 11 In-Place Upgrade Orchestrator
# Hardened edition (ServiceUI-first with safe fallback)
# ==============================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$Root      = "C:\Win11Upgrade"
$LogFile   = Join-Path $Root "Upgrade.log"
$IsoUrl    = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoFile   = Join-Path $Root "Win11_24H2_English_x64.iso"
$SetupDir  = Join-Path $Root "SetupFiles"
$SetupCfg  = Join-Path $Root "setupconfig.ini"
$RepoDir   = $null

# ------------------------
# Utilities
# ------------------------
function Log {
    param([string]$m)
    $msg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m"
    try { Add-Content -Path $LogFile -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue }
    catch { Start-Sleep -Milliseconds 150; Add-Content -Path $LogFile -Value $msg -Encoding UTF8 -ErrorAction SilentlyContinue }
}

function Fail {
    param([string]$m)
    Log "ERROR: $m"
    exit 1
}

function Ensure-Folder {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        try { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
        catch { Fail "Unable to create folder: $Path ($($_.Exception.Message))" }
    }
}

function Download-File {
    param(
        [string]$Uri,
        [string]$OutFile
    )
    try {
        # More compatible than Invoke-WebRequest in restricted envs; no TimeoutSec misuse.
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Uri, $OutFile)
        return $true
    } catch {
        Log "Download via WebClient failed: $($_.Exception.Message). Trying Invoke-WebRequest..."
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
            return $true
        } catch {
            Log "Invoke-WebRequest failed: $($_.Exception.Message)"
            return $false
        }
    }
}

function Get-ActiveUserNames {
    # Prefer explorer.exe ownership (works when quser is unavailable under SYSTEM)
    try {
        $procs = Get-WmiObject Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue
        if ($procs) {
            return ($procs | ForEach-Object { $_.GetOwner().User } | Where-Object { $_ } | Select-Object -Unique)
        }
    } catch {
        Log "Active user detection via WMI failed: $($_.Exception.Message)"
    }
    # Fallback to 'quser'
    try {
        $lines = & quser 2>$null
        if ($lines) {
            return ($lines | Where-Object { $_ -match 'Active' } | ForEach-Object {
                ($_ -split '\s+')[0]
            } | Where-Object { $_ } | Select-Object -Unique)
        }
    } catch {}
    return @()
}

function Wait-For-Condition {
    param(
        [scriptblock]$Condition,
        [int]$TimeoutSec = 30,
        [int]$IntervalSec = 2
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        try {
            if (& $Condition) { return $true }
        } catch {}
        Start-Sleep -Seconds $IntervalSec
    }
    return $false
}

# ------------------------
# Begin
# ------------------------
Ensure-Folder $Root
Log "Upgrade.ps1 started."

# Single-instance guard (best effort)
$LockFile = Join-Path $Root "upgrade.lock"
try {
    if (Test-Path $LockFile) {
        Log "Lockfile exists ($LockFile). Another run may be in progress."
    } else {
        New-Item -ItemType File -Path $LockFile -Force | Out-Null
    }
} catch { Log "Lockfile warning: $($_.Exception.Message)" }

# Locate extracted repo (project-711-d*)
try {
    $RepoDir = (Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^project-711-d' } | Select-Object -First 1).FullName
} catch {}
if (-not $RepoDir) { Fail "Repo folder not found under $Root" }
Log "Repo detected: $RepoDir"

# Basic OS sanity: if already Win11, continue (in-place is still allowed) but log
try {
    $osV = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
    Log "Current OS DisplayVersion: $osV"
} catch { Log "Could not read current OS version: $($_.Exception.Message)" }

# ISO presence / download
if (-not (Test-Path -LiteralPath $IsoFile)) {
    Log "Downloading ISO from $IsoUrl..."
    if (-not (Download-File -Uri $IsoUrl -OutFile $IsoFile)) {
        Fail "Failed to download ISO from $IsoUrl"
    }
    Log "ISO downloaded successfully."
} else {
    Log "ISO already present; skipping download."
}

# Prepare Setup files dir
Ensure-Folder $SetupDir

# Extract setup files from ISO if needed
$SetupExe = Join-Path $SetupDir "setup.exe"
if (-not (Test-Path -LiteralPath $SetupExe)) {
    Log "Mounting ISO to extract setup files..."
    try {
        $disk = Mount-DiskImage -ImagePath $IsoFile -PassThru -ErrorAction Stop
        # The volume can be slow to show up—retry until it does
        $driveLetter = $null
        $ok = Wait-For-Condition -TimeoutSec 30 -IntervalSec 2 -Condition {
            $vol = $disk | Get-Volume -ErrorAction SilentlyContinue
            if ($vol -and $vol.DriveLetter) { $script:driveLetter = $vol.DriveLetter; return $true }
            return $false
        }
        if (-not $ok -or -not $driveLetter) {
            throw "Mounted, but no volume/drive letter detected."
        }
        $src = "$driveLetter`:"
        Log "Copying setup files from $src to $SetupDir..."
        # Ensure destination exists
        Ensure-Folder $SetupDir
        # Mirror copy (safest to rehydrate full media tree)
        robocopy $src $SetupDir /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
        Log "Setup files copied."
    } catch {
        Fail "Mount/copy failure: $($_.Exception.Message)"
    } finally {
        try {
            Dismount-DiskImage -ImagePath $IsoFile -ErrorAction SilentlyContinue
        } catch {
            Log "Warning: Could not dismount ISO: $($_.Exception.Message)"
        }
    }
} else {
    Log "Setup files already present."
}

# Write setupconfig.ini with bypasses
@"
[SetupConfig]
BypassTPMCheck=1
BypassSecureBootCheck=1
BypassRAMCheck=1
BypassStorageCheck=1
BypassCPUCheck=1
DynamicUpdate=Disable
Telemetry=Disable
"@ | Out-File -FilePath $SetupCfg -Encoding ASCII -Force
Log "setupconfig.ini written at $SetupCfg."

# Determine interactive user(s)
$Users = Get-ActiveUserNames
$NoUser = ($Users.Count -eq 0)
if ($NoUser) {
    Log "No active users detected — using auto reboot mode."
    $Arguments = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`" /copylogs `"$Root\PantherLogs`""
} else {
    Log "Active user(s) detected ($($Users -join ', ')) — using /noreboot interactive mode."
    $Arguments = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`" /noreboot /copylogs `"$Root\PantherLogs`""
    try { & msg.exe * "A Windows 11 upgrade has been staged. Please reboot your PC to complete installation." } catch {}
}

# Verify setup.exe exists
if (-not (Test-Path -LiteralPath $SetupExe)) {
    Fail "setup.exe not found at $SetupExe"
}

# Launch strategy:
# 1) If interactive user(s) + ServiceUI.exe -> try ServiceUI to avoid soft idle UX
# 2) Verify setup actually starts (SetupHost/Setup) within a grace period
# 3) If not, fallback to direct Start-Process of setup.exe
# 4) In headless/no-user cases, run silent and detached

$ServiceUI = Join-Path $RepoDir "ServiceUI.exe"
$LaunchedWithServiceUI = $false
$Started = $false

Log "Starting setup.exe..."
Log "Arguments: $Arguments"

try {
    if ((-not $NoUser) -and (Test-Path -LiteralPath $ServiceUI)) {
        Log "Attempting ServiceUI launch..."
        # Build a robust argument string; use -f formatting to avoid quote hell
        $svcArgs = ("-Process:explorer.exe `"{0}`" {1}" -f $SetupExe, $Arguments)
        Start-Process -FilePath $ServiceUI -ArgumentList $svcArgs -WorkingDirectory $SetupDir -WindowStyle Hidden
        $LaunchedWithServiceUI = $true

        # Confirm setup has actually spawned (some environments 'soft idle' otherwise)
        $Started = Wait-For-Condition -TimeoutSec 25 -IntervalSec 2 -Condition {
            (Get-Process -Name SetupHost, Setup -ErrorAction SilentlyContinue) -ne $null
        }
        if ($Started) {
            Log "setup.exe appears to be running (detected Setup/SetupHost)."
        } else {
            Log "ServiceUI launch did not result in a running setup process within the window; falling back to direct launch."
            $LaunchedWithServiceUI = $false
        }
    }

    if (-not $Started) {
        # Either no ServiceUI, no user, or ServiceUI failed to materialize the process.
        if ($NoUser) {
            Log "No interactive user detected — running setup silently (detached)."
            Start-Process -FilePath $SetupExe -ArgumentList $Arguments -WorkingDirectory $SetupDir
        } else {
            Log "Running setup without ServiceUI (detached)."
            Start-Process -FilePath $SetupExe -ArgumentList $Arguments -WorkingDirectory $SetupDir
        }

        # Optional: quick verify that something started; don't block forever
        $Started = Wait-For-Condition -TimeoutSec 15 -IntervalSec 2 -Condition {
            (Get-Process -Name SetupHost, Setup -ErrorAction SilentlyContinue) -ne $null
        }
        if ($Started) {
            Log "setup.exe appears to be running after direct launch."
        } else {
            Log "WARNING: Could not detect Setup/SetupHost shortly after launch. It may still be staging in background."
        }
    }

    Log ("setup.exe launched successfully ({0})." -f ($(if($LaunchedWithServiceUI) {'ServiceUI'} else {'direct'})))
} catch {
    Fail "Exception when starting setup: $($_.Exception.Message)"
}

# ------------------------
# Schedule cleanup (optional)
# ------------------------
$CleanupBat = Join-Path $RepoDir "Cleanup.bat"
if (Test-Path -LiteralPath $CleanupBat) {
    try {
        if (-not (Get-ScheduledTask -TaskName "Win11_Cleanup" -ErrorAction SilentlyContinue)) {
            Log "Scheduling cleanup on startup..."
            # Robust quoting for paths with spaces
            $arg = '/c start /min ' + ('"'{0}'"' -f $CleanupBat)
            $act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument $arg
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

# Done
Log "Upgrade.ps1 completed."
# Remove lockfile (best effort)
try { Remove-Item -Path $LockFile -Force -ErrorAction SilentlyContinue } catch {}
exit 0
