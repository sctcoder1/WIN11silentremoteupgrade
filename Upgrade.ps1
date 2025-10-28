# Upgrade.ps1
# Performs Windows 11 in-place upgrade silently with requirement bypass

$Root      = "C:\Win11Upgrade"
$IsoUrl    = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"   # your ISO URL
$IsoFile   = Join-Path $Root "Win11_24H2_English_x64.iso"
$SetupCfg  = Join-Path $Root "setupconfig.ini"
$LogFile   = Join-Path $Root "Upgrade.log"

function Log($m){ ("[$(Get-Date)] $m") | Out-File $LogFile -Append }

Log "=== Starting Windows 11 In-Place Upgrade ==="

# --- Download ISO only if missing ---
if (-not (Test-Path $IsoFile)) {
    Log "Downloading ISO..."
    try {
        Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoFile -UseBasicParsing -TimeoutSec 0
        Log "ISO downloaded successfully."
    } catch {
        Log "ERROR: Failed to download ISO. $_"
        exit 1
    }
} else {
    Log "ISO already present. Skipping download."
}

# --- Mount ISO and copy setup files if not already extracted ---
$SetupDir = Join-Path $Root "SetupFiles"
if (-not (Test-Path (Join-Path $SetupDir "setup.exe"))) {
    Log "Mounting ISO..."
    $disk = Mount-DiskImage -ImagePath $IsoFile -PassThru
    Start-Sleep 3
    $drive = ($disk | Get-Volume).DriveLetter
    $src = "$drive`:"
    Log "Copying setup files..."
    robocopy $src $SetupDir /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    Dismount-DiskImage -ImagePath $IsoFile
    Log "Extraction complete."
} else {
    Log "Setup files already exist at $SetupDir."
}

# --- Create SetupConfig.ini (bypass checks) ---
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
Log "SetupConfig.ini created."

# --- Determine user login state ---
$activeUsers = (& quser 2>$null) -match "Active"
$NoUser = [string]::IsNullOrWhiteSpace(($activeUsers -join ''))

if ($NoUser) {
    Log "No active user detected. Reboot will occur automatically."
    $Args = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate Disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`""
} else {
    Log "Active user(s) detected. Suppressing reboot."
    $Args = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate Disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`" /noreboot"
    try { & msg.exe * "A Windows 11 upgrade has been prepared. Please reboot when convenient to complete installation." } catch {}
}

# --- Launch setup.exe ---
$SetupExe = Join-Path $SetupDir "setup.exe"
if (-not (Test-Path $SetupExe)) {
    Log "ERROR: setup.exe not found in $SetupDir"
    exit 1
}

Log "Starting setup.exe..."
try {
    Start-Process -FilePath $SetupExe -ArgumentList $Args -Wait
    Log "setup.exe completed successfully."
} catch {
    Log "ERROR running setup.exe: $_"
    exit 1
}

# --- Schedule cleanup for next boot ---
$CleanupBat = Join-Path $Root "Cleanup.bat"
if (Test-Path $CleanupBat) {
    Log "Scheduling cleanup task..."
    $act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min `"$CleanupBat`""
    $trg = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName "Win11_Cleanup" -Action $act -Trigger $trg -RunLevel Highest -Force | Out-Null
} else {
    Log "WARNING: Cleanup.bat not found; skipping task registration."
}

Log "=== Upgrade process completed ==="
exit 0
