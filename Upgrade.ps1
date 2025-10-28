# ==============================================================
# Upgrade.ps1 - Windows 10 → Windows 11 automated upgrade
# ==============================================================

$ErrorActionPreference = 'Stop'
$Root = "C:\Win11Upgrade"
$LogFile = Join-Path $Root "Upgrade.log"

function Log { param($m) "[" + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] $m" | Out-File $LogFile -Append }

Log "Upgrade.ps1 started."

# --- Locate repo directory ---
$RepoDir = (Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'project-711-d' } | Select-Object -First 1)
if (-not $RepoDir) {
    Log "ERROR: Repo folder not found under $Root"
    exit 1
}
$RepoDir = $RepoDir.FullName

# --- ISO download ---
$IsoUrl  = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoFile = Join-Path $Root "Win11_24H2_English_x64.iso"
$SetupDir = Join-Path $Root "SetupFiles"
$SetupCfg = Join-Path $Root "setupconfig.ini"

if (-not (Test-Path $IsoFile)) {
    Log "Downloading ISO from $IsoUrl..."
    Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoFile -UseBasicParsing
    Log "ISO downloaded."
} else {
    Log "ISO already present; skipping download."
}

# --- Extract setup files ---
if (-not (Test-Path (Join-Path $SetupDir "setup.exe"))) {
    Log "Mounting ISO..."
    $disk = Mount-DiskImage -ImagePath $IsoFile -PassThru
    Start-Sleep -Seconds 3
    $drive = ($disk | Get-Volume).DriveLetter + ":"
    Log "Copying setup files from $drive to $SetupDir..."
    robocopy $drive $SetupDir /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    Dismount-DiskImage -ImagePath $IsoFile
    Log "Setup files copied."
} else {
    Log "Setup files already available at $SetupDir."
}

# --- Write setupconfig.ini (bypass checks) ---
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

# --- Determine active users ---
$active = (& quser 2>$null) -match "Active"
$NoUser = [string]::IsNullOrWhiteSpace(($active -join ''))
if ($NoUser) {
    Log "No active users detected — will allow automatic reboot."
} else {
    Log "Active user(s) detected — will suppress reboot."
    try { & msg.exe * "A Windows 11 upgrade has been staged. Please reboot to complete installation." } catch {}
}

# --- Build setup command ---
$SetupExe = Join-Path $SetupDir "setup.exe"
if (-not (Test-Path $SetupExe)) {
    Log "ERROR: setup.exe not found at $SetupExe"
    exit 1
}

if ($NoUser) {
    $Arguments = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`""
} else {
    $Arguments = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`" /noreboot"
}

# --- Run setup.exe ---
Log "Starting setup.exe..."
try {
    Log "Arguments: $Arguments"
    Start-Process -FilePath $SetupExe -ArgumentList $Arguments -Wait
    Log "setup.exe executed successfully."
} catch {
    Log "ERROR running setup.exe: $($_.Exception.Message)"
    exit 1
}

# --- Schedule cleanup after reboot ---
$CleanupBat = Join-Path $RepoDir "Cleanup.bat"
if (Test-Path $CleanupBat) {
    if (-not (Get-ScheduledTask -TaskName "Win11_Cleanup" -ErrorAction SilentlyContinue)) {
        Log "Scheduling cleanup on startup..."
        $act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min `"$CleanupBat`""
        $trg = New-ScheduledTaskTrigger -AtStartup
        Register-ScheduledTask -TaskName "Win11_Cleanup" -Action $act -Trigger $trg -RunLevel Highest -Force | Out-Null
        Log "Cleanup scheduled."
    } else {
        Log "Cleanup task already exists. Skipping."
    }
} else {
    Log "WARNING: Cleanup.bat not found; manual cleanup required."
}

Log "Upgrade.ps1 completed."
exit 0
