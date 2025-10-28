<#
Upgrade.ps1  –  Fully silent Windows 11 in-place upgrade
Everything happens inside C:\Win11Upgrade
#>

# --- Config ---
$UpgradeDir  = "C:\Win11Upgrade"
$IsoFile     = Join-Path $UpgradeDir "Win11_24H2_English_x64.iso"
$IsoUrl      = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$SetupCfg    = Join-Path $UpgradeDir "setupconfig.ini"
$LogFile     = Join-Path $UpgradeDir "upgrade.log"

# --- Elevate if needed ---
if (-not ([Security.Principal.WindowsPrincipal]
          [Security.Principal.WindowsIdentity]::GetCurrent()
          ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting elevation..."
    Start-Process "powershell" -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`""
    exit
}

# --- Prep folder ---
New-Item -ItemType Directory -Force -Path $UpgradeDir | Out-Null
Set-Location $UpgradeDir
"[$(Get-Date)] Starting upgrade script" | Out-File $LogFile

# --- Download ISO if missing ---
if (-not (Test-Path $IsoFile)) {
    Write-Host "Downloading ISO..."
    Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoFile -UseBasicParsing -Verbose *>> $LogFile
} else {
    Write-Host "ISO already present; skipping download."
}

# --- Mount ISO and copy contents ---
Write-Host "Mounting ISO..."
$disk = Mount-DiskImage -ImagePath $IsoFile -PassThru
Start-Sleep 3
$letter = ($disk | Get-Volume).DriveLetter
$src = "$letter`:"

Write-Host "Copying installer files..."
robocopy $src $UpgradeDir /MIR /NFL /NDL /NJH /NJS /NP *>> $LogFile

Dismount-DiskImage -ImagePath $IsoFile
Remove-Item $IsoFile -Force -ErrorAction SilentlyContinue

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

# --- Detect logged-in users ---
$active = (& quser 2>$null) -match "Active"
$NoUser = [string]::IsNullOrWhiteSpace(($active -join ''))
if ($NoUser) {
    Write-Host "No active users – auto reboot allowed."
    $Args = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate Disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`" /copylogs `"$UpgradeDir\setup-logs`""
} else {
    Write-Host "User logged in – suppressing reboot."
    $Args = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate Disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupCfg`" /copylogs `"$UpgradeDir\setup-logs`" /noreboot"
}

# --- Launch setup.exe ---
Write-Host "Starting setup..."
Start-Process -FilePath (Join-Path $UpgradeDir "setup.exe") -ArgumentList $Args -Wait
"[$(Get-Date)] Setup.exe finished" | Out-File $LogFile -Append

# --- Optional: self-cleanup after first reboot ---
$cleanup = @"
Start-Sleep -Seconds 20
try {
    \$prod = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName
    if (\$prod -match 'Windows 11') {
        Remove-Item -LiteralPath '$UpgradeDir' -Recurse -Force -ErrorAction SilentlyContinue
        schtasks /Delete /TN 'Win11_Cleanup' /F 2> \$null
    }
} catch {}
"@
$cleanupPath = Join-Path $UpgradeDir "cleanup.ps1"
$cleanup | Out-File $cleanupPath -Encoding ascii -Force
$act = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cleanupPath`""
$trg = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "Win11_Cleanup" -Action $act -Trigger $trg -RunLevel Highest -Force | Out-Null

Write-Host "Upgrade launched. System will reboot automatically when ready (if no users signed in)."
