# Upgrade.ps1
$Root = "C:\Win11Upgrade"
$LogFile = Join-Path $Root "Upgrade.log"
function Log { param($m) ("[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m") | Out-File $LogFile -Append }

Log "Upgrade.ps1 started."

# Workdir: find extracted repo dir (project-711-d)
$RepoDir = (Get-ChildItem -Path $Root -Directory | Where-Object { $_.Name -match 'project-711-d' } | Select-Object -First 1).FullName
if (-not $RepoDir) { Log "ERROR: Repo folder not found under $Root"; exit 1 }

# ISO settings (point to your Hostinger URL)
$IsoUrl = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoFile = Join-Path $Root "Win11_24H2_English_x64.iso"
$SetupDir = Join-Path $Root "SetupFiles"
$SetupCfg = Join-Path $Root "setupconfig.ini"

# --- Download ISO if missing ---
if (-not (Test-Path $IsoFile)) {
    Log "Downloading ISO from $IsoUrl..."
    try {
        Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoFile -UseBasicParsing -TimeoutSec 0
        Log "ISO downloaded."
    } catch {
        Log "ERROR downloading ISO: $_"
        exit 1
    }
} else {
    Log "ISO already present; skipping download."
}

# --- Extract setup files if not present ---
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
        Log "ERROR mounting/copying ISO: $_"
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

# --- Determine if user(s) are logged in ---
$active = (& quser 2>$null) -match "Active"
$NoUser = [string]::IsNullOrWhiteSpace(($active -join ''))
if ($NoUser) {
    Log "No active users detected — allowing automatic reboot."
    $Args = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate Disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`""
} else {
    Log "Active user(s) detected — using /noreboot and notifying user(s)."
    $Args = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate Disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`" /noreboot"
    try { & msg.exe * "A Windows 11 upgrade has been staged. Please reboot your PC to complete installation." } catch {}
}

$SetupExe = Join-Path $SetupDir "setup.exe"
if (-not (Test-Path $SetupExe)) {
    Log "ERROR: setup.exe not found at $SetupExe"
    exit 1
}

Log "Starting setup.exe..."
try {
    $SetupExe = Join-Path $SetupDir "setup.exe"

    if ($NoUser) {
        $Arguments = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate Disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`""
    }
    else {
        $Arguments = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate Disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`" /noreboot"
    }

    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        Log "Running setup.exe with arguments: $Arguments"
        Start-Process -FilePath $SetupExe -ArgumentList $Arguments -Wait
        Log "Setup.exe executed successfully."
    }
    else {
        Log "ERROR: Argument list is empty — skipping setup."
    }
}
catch {
    Log "ERROR running setup.exe: $($_.Exception.Message)"
    exit 1
}


# --- Register cleanup to run at next boot ---
$CleanupBat = Join-Path $RepoDir "Cleanup.bat"
if (Test-Path $CleanupBat) {
    if (-not (Get-ScheduledTask -TaskName "Win11_Cleanup" -ErrorAction SilentlyContinue)) {
        Log "Scheduling cleanup on startup..."
        $act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min `"$CleanupBat`""
        $trg = New-ScheduledTaskTrigger -AtStartup
        try {
            Register-ScheduledTask -TaskName "Win11_Cleanup" -Action $act -Trigger $trg -RunLevel Highest -Force | Out-Null
            Log "Cleanup scheduled."
        } catch {
            Log "ERROR scheduling cleanup: $_"
        }
    } else {
        Log "Cleanup task already exists. Skipping."
    }
} else {
    Log "WARNING: Cleanup.bat not found; manual cleanup required."
}

Log "Upgrade.ps1 completed."
exit 0
