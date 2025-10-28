# --- Config ---
$UpgradeDir = "C:\Win11Upgrade"
$IsoUrl = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoFile = Join-Path $UpgradeDir "Win11_24H2_English_x64.iso"
$SetupCfg = Join-Path $UpgradeDir "setupconfig.ini"
$LogFile = Join-Path $UpgradeDir "upgrade.log"

# --- Logging helper ---
function Log($m){ "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) `t $m" | Out-File $LogFile -Append }

Log "Starting upgrade script."

# --- Download ISO if needed ---
if (-not (Test-Path $IsoFile)) {
    Log "Downloading ISO..."
    Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoFile -UseBasicParsing
} else {
    Log "ISO already exists."
}

# --- Mount ISO and copy contents ---
$disk = Mount-DiskImage -ImagePath $IsoFile -PassThru
Start-Sleep 3
$drive = ($disk | Get-Volume).DriveLetter
$src = "$drive`:"

Log "Copying setup files..."
robocopy $src $UpgradeDir /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
Dismount-DiskImage -ImagePath $IsoFile
Remove-Item $IsoFile -Force -ErrorAction SilentlyContinue

# --- Bypass setup checks ---
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

# --- Detect users ---
$active = (& quser 2>$null) -match "Active"
$NoUser = [string]::IsNullOrWhiteSpace(($active -join ''))
if ($NoUser) {
    Log "No active user detected. Will reboot automatically."
    $Args = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate Disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`""
} else {
    Log "Active user logged in. No automatic reboot."
    $Args = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate Disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`" /noreboot"
    try { & msg.exe * "Windows 11 upgrade staged. Please reboot to finish installation." } catch {}
}

# --- Start setup ---
Log "Starting setup.exe..."
Start-Process -FilePath (Join-Path $UpgradeDir "setup.exe") -ArgumentList $Args -Wait
Log "Setup.exe completed."

# --- Schedule cleanup ---
$CleanupScript = @"
Start-Sleep -Seconds 20
try {
    if ((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName -match 'Windows 11') {
        Remove-Item -Recurse -Force 'C:\Win11Upgrade' -ErrorAction SilentlyContinue
        Remove-LocalUser -Name 'WinUpgTemp' -ErrorAction SilentlyContinue
        schtasks /Delete /TN 'Win11_Upgrade_Start' /F
        schtasks /Delete /TN 'Win11_Cleanup' /F
    }
} catch {}
"@
$CleanupPath = Join-Path $UpgradeDir "cleanup.ps1"
$CleanupScript | Out-File $CleanupPath -Encoding ascii
$act = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$CleanupPath`""
$trg = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "Win11_Cleanup" -Action $act -Trigger $trg -RunLevel Highest -Force | Out-Null

Log "Upgrade launched successfully."
