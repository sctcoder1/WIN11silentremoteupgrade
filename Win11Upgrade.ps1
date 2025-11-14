# Windows 11 In-Place Upgrade Script (No Scheduled Reboot)

$log = "C:\Win11Upgrade\upgrade.log"
function Log($msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$ts $msg" | Tee-Object -FilePath $log -Append
}

Log "`n===== Windows 11 Upgrade Script Start ====="

# Check if already Windows 11
$os = (Get-CimInstance Win32_OperatingSystem).Version
if ($os -ge "10.0.22000") {
    Log "System is already running Windows 11 (version $os). Exiting."
    exit 0
}

# Prepare working folder
$dir = "C:\Win11Upgrade"
if (!(Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
    Log "Created working directory: $dir"
} else {
    Log "Using existing working directory."
}

# Check free space BEFORE download
$minGB = 10
$freeGB = (Get-PSDrive C).Free / 1GB
if ($freeGB -lt $minGB) {
    Log "Insufficient disk space. Only $([math]::Round($freeGB,1)) GB free. Require at least $minGB GB. Exiting."
    exit 1
}
Log "Free disk space: $([math]::Round($freeGB,1)) GB"

# Define ISO and size
$isoUrl = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$isoPath = "$dir\Win11_24H2.iso"
$expectedSizeKB = 5683090
$needsDownload = $true

# Check if ISO exists and matches expected size
if (Test-Path $isoPath) {
    $actualSizeKB = (Get-Item $isoPath).Length / 1KB
    if ([int]$actualSizeKB -eq $expectedSizeKB) {
        Log "ISO exists and size matches: $expectedSizeKB KB"
        $needsDownload = $false
    } else {
        Log "ISO exists but wrong size ($([int]$actualSizeKB) KB). Deleting."
        Remove-Item $isoPath -Force
    }
}

# Download if needed
if ($needsDownload) {
    Log "Downloading ISO from $isoUrl..."
    Invoke-WebRequest -Uri $isoUrl -OutFile $isoPath
    $downloadedSizeKB = (Get-Item $isoPath).Length / 1KB
    if ([int]$downloadedSizeKB -ne $expectedSizeKB) {
        Log "Download failed or incorrect size. Got $([int]$downloadedSizeKB) KB. Aborting."
        exit 2
    }
    Log "Download complete: $expectedSizeKB KB"
}

# Mount ISO with fallback to extraction
$mountSuccess = $false
$setupPath = ""
try {
    Mount-DiskImage -ImagePath $isoPath -ErrorAction Stop | Out-Null
    Start-Sleep 5
    $image = Get-DiskImage -ImagePath $isoPath
    $vols = Get-Volume -DiskImage $image
    $cdDrive = $vols | Where-Object { $_.DriveLetter -ne $null } | Select-Object -First 1
    if ($cdDrive) {
        $setupPath = "$($cdDrive.DriveLetter):\setup.exe"
        Log "Mounted ISO to $($cdDrive.DriveLetter):"
        $mountSuccess = $true
    } else {
        Log "Mount succeeded but no drive letter assigned."
    }
} catch {
    Log "Mount failed: $($_.Exception.Message)"
}

# If mount failed or setup not found, extract ISO
if (-not $mountSuccess -or -not (Test-Path $setupPath)) {
    Log "Falling back to ISO extraction."
    $extractDir = "$dir\Extracted"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
    Expand-Archive -Path $isoPath -DestinationPath $extractDir -Force
    $setupPath = "$extractDir\setup.exe"
    if (!(Test-Path $setupPath)) {
        Log "Extraction failed. setup.exe not found. Aborting."
        exit 3
    }
    Log "Extracted ISO to $extractDir"
}

# Set registry for bypass
$reg = "HKLM:\SYSTEM\Setup\MoSetup"
if (!(Test-Path $reg)) { New-Item -Path $reg -Force | Out-Null }
Set-ItemProperty -Path $reg -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -Value 1 -Type DWord -Force
Log "Set bypass registry key."

# Suspend BitLocker
$bit = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
if ($bit.ProtectionStatus -eq "On") {
    Suspend-BitLocker -MountPoint "C:" -RebootCount 1
    Log "Suspended BitLocker on C:"
} else {
    Log "BitLocker not active or not detected."
}

# Run upgrade
$args = "/auto upgrade /quiet /noreboot /dynamicupdate disable /compat ignorewarning /bitlocker alwayssuspend /eula accept"
Log "Running setup.exe with args: $args"
$p = Start-Process -FilePath $setupPath -ArgumentList $args -Wait -PassThru
Log "setup.exe exit code: $($p.ExitCode)"

# Done — No scheduled reboot
if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
    Log "Upgrade staged successfully. Manual reboot required to complete installation."
} else {
    Log "Setup failed with exit code $($p.ExitCode)."
}

Log "===== Script complete. No reboot scheduled. ====="
exit 0
