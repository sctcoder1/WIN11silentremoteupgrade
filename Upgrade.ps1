<#
Upgrade.ps1
Fully automated Windows 11 in-place upgrade orchestrator.

Edit at top:
- $SourceUri : URL to a .zip containing the extracted Windows 11 install folder (setup.exe at root of extracted), OR a direct ISO (will mount and copy).
- $CreateTempAdmin : $true to create a temporary admin account (name: UpgradeMonitor) for visibility/testing.
- $TempAdminName : username for temporary admin.
- $CleanupAfterSuccess : $true to remove folder, temp user, tasks after successful upgrade.

Test in a VM first.
#>

# --- CONFIG --- modify if you want
$SourceUri = "https://raw.githubusercontent.com/your/repo/main/win11-extracted.zip"
$CreateTempAdmin = $true
$TempAdminName = "UpgradeMonitor"
$TempAdminPasswordPlain = [System.Web.Security.Membership]::GeneratePassword(14,2) # random-ish
$UpgradeFolder = "C:\Win11Upgrade"
$LogFile = Join-Path $UpgradeFolder "upgrade-orch.log"
$CleanupAfterSuccess = $true
$ScheduledRebootCheckName = "Win11Upgrade_RebootCheck"
$ScheduledRunNowName = "Win11Upgrade_RunNow"
$ScheduledCleanupName = "Win11Upgrade_Cleanup"

# --- helper logging ---
Function Log {
    param($s)
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$t`t$s" | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Output $s
}

# --- ensure elevated ---
If (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Log "Not running elevated. Re-launching as admin..."
    Start-Process -FilePath "powershell" -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    Exit 0
}
Log "Running as Administrator."

# --- prepare folder ---
New-Item -Path $UpgradeFolder -ItemType Directory -Force | Out-Null
Log "Upgrade folder: $UpgradeFolder"

# --- download & stage install files ---
Function Stage-InstallFiles {
    param($uri, $dest)
    Try {
        Log "Beginning stage from $uri"
        $lower = $uri.ToLower()
        if ($lower -like "*.iso" -or $lower -like "*.iso*") {
            # Download ISO then mount & copy
            $iso = Join-Path $dest "win11.iso"
            Log "Downloading ISO to $iso"
            Invoke-WebRequest -Uri $uri -OutFile $iso -UseBasicParsing -ErrorAction Stop
            Log "Mounting ISO"
            $mount = Mount-DiskImage -ImagePath $iso -PassThru
            Start-Sleep -Seconds 2
            $vol = (Get-Volume | Where-Object {$_.DriveType -eq 'CD-ROM'} | Select-Object -First 1).DriveLetter + ":\"
            Log "Copying contents from $vol to $dest"
            robocopy $vol $dest /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
            Dismount-DiskImage -ImagePath $iso
            Remove-Item $iso -Force -ErrorAction SilentlyContinue
            Log "ISO staged"
        } else {
            # assume zip or extracted folder. If zip: expand
            $lowerUri = $uri.ToLower()
            if ($lowerUri -like "*.zip" -or $lowerUri -like "*.zip*") {
                $zipfile = Join-Path $dest "stage.zip"
                Log "Downloading zip to $zipfile"
                Invoke-WebRequest -Uri $uri -OutFile $zipfile -UseBasicParsing -ErrorAction Stop
                Log "Expanding zip"
                Expand-Archive -Path $zipfile -DestinationPath $dest -Force
                Remove-Item $zipfile -Force
                Log "Zip expanded"
            } else {
                # attempt to download a single file or directory listing - try raw download to a temporary path
                Log "Unknown extension - attempting to Invoke-WebRequest directly into folder (may fail)"
                $fileDest = Join-Path $dest (Split-Path $uri -Leaf)
                Invoke-WebRequest -Uri $uri -OutFile $fileDest -UseBasicParsing -ErrorAction Stop
            }
        }
        return $true
    } catch {
        Log "Error staging install files: $($_.Exception.Message)"
        return $false
    }
}

if (-not(Test-Path (Join-Path $UpgradeFolder "setup.exe"))) {
    $staged = Stage-InstallFiles -uri $SourceUri -dest $UpgradeFolder
    if (-not $staged) {
        Log "Staging failed. Aborting."
        Exit 2
    }
} else {
    Log "setup.exe already present; skipping staging."
}

# --- create setupconfig.ini to bypass requirements ---
$SetupConfig = @"
[SetupConfig]
BypassTPMCheck=1
BypassSecureBootCheck=1
BypassRAMCheck=1
BypassStorageCheck=1
BypassCPUCheck=1
"@
$SetupConfigPath = Join-Path $UpgradeFolder "setupconfig.ini"
$SetupConfig | Out-File -FilePath $SetupConfigPath -Encoding ascii -Force
Log "Wrote setupconfig.ini to bypass hardware checks."

# --- find interactive sessions (Active users) ---
Function Get-ActiveInteractiveUsers {
    $users = @()
    try {
        $quser = & quser 2>&1
        if ($LASTEXITCODE -eq 0) {
            foreach ($line in $quser) {
                # parse "USERNAME SESSIONNAME ID STATE ..."
                $cols = ($line -replace '\s+',' ') -split ' '
                if ($cols.Length -ge 3) {
                    if ($line -match 'Active') {
                        $name = $cols[0].Trim()
                        if ($name -and $name -ne "USERNAME") { $users += $name }
                    }
                }
            }
        } else {
            # fallback - find owner of explorer.exe (console user)
            $proc = Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($proc) {
                $owner = (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" | ForEach-Object {
                    $null = $_.GetOwner(); $_.GetOwner().User
                }) -join ','
                if ($owner) { $users += $owner }
            }
        }
    } catch {
        Log "Get-ActiveInteractiveUsers fallback error: $_"
    }
    return $users | Select-Object -Unique
}

$activeUsers = Get-ActiveInteractiveUsers
if ($activeUsers.Count -eq 0) {
    Log "No active interactive users detected."
    $NoUserSignedIn = $true
} else {
    Log "Active interactive user(s): $($activeUsers -join ',')"
    $NoUserSignedIn = $false
}

# --- optional: create temp admin user for monitoring ---
if ($CreateTempAdmin) {
    try {
        if (Get-LocalUser -Name $TempAdminName -ErrorAction SilentlyContinue) {
            Log "Temp admin $TempAdminName already exists - leaving it."
        } else {
            Log "Creating temp admin user $TempAdminName"
            $securePass = ConvertTo-SecureString -String $TempAdminPasswordPlain -AsPlainText -Force
            New-LocalUser -Name $TempAdminName -Password $securePass -FullName "Upgrade Monitor" -Description "Temporary monitoring account for Win11 upgrade" -PasswordNeverExpires
            Add-LocalGroupMember -Group "Administrators" -Member $TempAdminName
            Log "Created temp admin $TempAdminName (passwd in log)."
            "Temp admin password: $TempAdminPasswordPlain" | Out-File -FilePath $LogFile -Append
        }
    } catch {
        Log "Error creating temp admin: $($_.Exception.Message)"
    }
}

# --- prepare setup.exe commandline flags ---
$SetupExe = Join-Path $UpgradeFolder "setup.exe"
if (-not (Test-Path $SetupExe)) {
    Log "setup.exe not found at $SetupExe - abort."
    Exit 3
}

# Base common args
$BaseArgs = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate Disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupConfigPath`" /copylogs `"$UpgradeFolder\setup-logs`""

# If no users signed in -> allow reboot
if ($NoUserSignedIn) {
    Log "No interactive users: installer will run allowing auto-reboot when required."
    $RunArgs = $BaseArgs  # do NOT include /noreboot so setup may reboot
} else {
    Log "Interactive users present: installer will run with /noreboot to avoid rebooting them."
    $RunArgs = $BaseArgs + " /noreboot"
}

# --- Run the installer ---
Function Start-Installer {
    param($exe, $args, $useScheduledTaskUser)
    try {
        if ($useScheduledTaskUser -and $CreateTempAdmin) {
            # Create a scheduled task to run as the TempAdmin user (so the process shows under that user)
            $action = New-ScheduledTaskAction -Execute $exe -Argument $args
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(10)
            $principal = New-ScheduledTaskPrincipal -UserId $TempAdminName -LogonType Password -RunLevel Highest
            $cred = New-Object System.Management.Automation.PSCredential($TempAdminName, (ConvertTo-SecureString $TempAdminPasswordPlain -AsPlainText -Force))
            Register-ScheduledTask -TaskName $ScheduledRunNowName -Action $action -Trigger $trigger -Principal $principal -Password $TempAdminPasswordPlain -Force
            Start-ScheduledTask -TaskName $ScheduledRunNowName
            Log "Registered and started scheduled task $ScheduledRunNowName to run installer as $TempAdminName."
        } else {
            Log "Starting setup.exe directly under current account (SYSTEM). Command: `"$exe`" $args"
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $exe
            $psi.Arguments = $args
            $psi.RedirectStandardOutput = $false
            $psi.UseShellExecute = $true
            $psi.Verb = "runas"
            [System.Diagnostics.Process]::Start($psi) | Out-Null
            Log "Started installer process."
        }
        return $true
    } catch {
        Log "Failed to start installer: $($_.Exception.Message)"
        return $false
    }
}

$started = Start-Installer -exe $SetupExe -args $RunArgs -useScheduledTaskUser $true
if (-not $started) {
    Log "Installer failed to start. Aborting."
    Exit 4
}

# --- if users logged in: notify them & create desktop notice & schedule reboot-check ---
if (-not $NoUserSignedIn) {
    Log "Notifying interactive users of pending reboot and creating Desktop notice."

    foreach ($u in $activeUsers) {
        try {
            # Send msg to user (works on domain/Terminal Services setups). Will be skipped silently if it fails.
            & msg.exe $u "Windows 11 upgrade has finished installing and a reboot is required to complete the update. Please save your work. The system will not reboot while someone is signed in." 2>$null
        } catch { }
    }

    # Create a desktop text notice for each profile
    $profiles = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { $_.Loaded -eq $false -or $_.LocalPath -ne $null }
    foreach ($p in $profiles) {
        try {
            $desktop = Join-Path $p.LocalPath "Desktop"
            if (Test-Path $desktop) {
                $notice = @"
Windows 11 upgrade completed.
A reboot is required to finish the installation.
Please save your work and reboot, or the system will reboot when no users are signed in (a checker will run every 30 minutes).
"@
                $notice | Out-File -FilePath (Join-Path $desktop "WINDOWS11_REBOOT_REQUIRED.txt") -Force -Encoding UTF8
            }
        } catch { }
    }

    # Create scheduled task which runs every 30 minutes and attempts to reboot if no interactive users
    $scriptCheck = @"
`$active = (quser 2>`$null) -join ''
if ([string]::IsNullOrWhiteSpace(`$active)) {
    shutdown /r /t 60 /c `"Rebooting now to finish Windows 11 upgrade.`"
} else {
    # still users - do nothing
}
"@
    $checkPath = Join-Path $UpgradeFolder "reboot-check.ps1"
    $scriptCheck | Out-File -FilePath $checkPath -Encoding ascii -Force
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$checkPath`""
    $trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 30) -Once -At (Get-Date).AddMinutes(1)
    Register-ScheduledTask -TaskName $ScheduledRebootCheckName -Action $action -Trigger $trigger -RunLevel Highest -Force
    Log "Registered scheduled reboot-check task $ScheduledRebootCheckName (every 30 minutes)."
}

# --- schedule cleanup to run after next boot if installer will reboot the machine ---
# create cleanup script that runs once at boot and checks Windows version; if upgraded -> perform final cleanup.
$cleanupScript = @"
# Cleanup script for Win11 upgrade orchestrator
Start-Sleep -Seconds 30
# Check if upgrade completed by checking product name
try {
    `$prod = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).ProductName
} catch {
    `$prod = ''
}
if (`$prod -match 'Windows 11') {
    # remove staged folder and tasks and temp user if desired
    Remove-Item -LiteralPath '$UpgradeFolder' -Recurse -Force -ErrorAction SilentlyContinue
    schtasks /Delete /TN `"$ScheduledRebootCheckName`" /F 2> $null
    schtasks /Delete /TN `"$ScheduledRunNowName`" /F 2> $null
    # remove this scheduled task (self)
    schtasks /Delete /TN `"$ScheduledCleanupName`" /F 2> $null
    # delete temp admin
    if ($CreateTempAdmin) {
        try {
            net user $TempAdminName /delete 2>$null
        } catch {}
    }
}
"@
$cleanupPath = Join-Path $UpgradeFolder "post-upgrade-cleanup.ps1"
$cleanupScript | Out-File -FilePath $cleanupPath -Encoding ascii -Force
# register scheduled task to run at startup once
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cleanupPath`""
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName $ScheduledCleanupName -Action $action -Trigger $trigger -RunLevel Highest -Force
Log "Registered cleanup-at-startup task $ScheduledCleanupName."

Log "Upgrade orchestration complete. Installer running. See logs in $LogFile."

Exit 0
