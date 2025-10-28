<#
Upgrade.ps1
Fully contained Win11 silent remote upgrade orchestration.
Everything lives under C:\Win11Upgrade

Default SourceUri: Github main.zip of sctcoder1/WIN11silentremoteupgrade (replace if you want a different source)
Recommended: host a ZIP containing the *extracted* Windows installer layout (setup.exe at the ZIP root).

Usage:
  - Run elevated (script will relaunch itself elevated if needed).
  - Example via Sophos Live Response (SYSTEM): powershell -ExecutionPolicy Bypass -NoProfile -File "C:\Win11Upgrade\Upgrade.ps1"

Test in a VM first.
#>

param(
    [string]$SourceUri = "https://github.com/sctcoder1/WIN11silentremoteupgrade/archive/refs/heads/main.zip",
    [switch]$UseTempAdmin = $true,                # Set to $false to skip creating the temporary admin
    [string]$TempAdminName = "UpgradeMonitor",
    [int]$RebootCheckMinutes = 30                 # how often the reboot checker runs (minutes)
)

# --- Configuration (internal) ---
$UpgradeFolder      = "C:\Win11Upgrade"
$LogFile            = Join-Path $UpgradeFolder "upgrade-orch.log"
$SetupConfigPath    = Join-Path $UpgradeFolder "setupconfig.ini"
$SetupExePath       = Join-Path $UpgradeFolder "setup.exe"
$TempAdminPasswordPlain = [System.Web.Security.Membership]::GeneratePassword(14,2)
$ScheduledRunNowName = "Win11Upgrade_RunNow"
$ScheduledRebootCheckName = "Win11Upgrade_RebootCheck"
$ScheduledCleanupName = "Win11Upgrade_Cleanup"
$PostCleanupScript   = Join-Path $UpgradeFolder "post-upgrade-cleanup.ps1"
$RebootCheckScript   = Join-Path $UpgradeFolder "reboot-check.ps1"

# --- Helpers ---
Function Log {
    param([string]$s)
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "$t`t$s"
    Try { $line | Out-File -FilePath $LogFile -Append -Encoding utf8 -ErrorAction SilentlyContinue } Catch {}
    Write-Output $s
}

# Relaunch elevated if not admin
If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Log "Not elevated. Relaunching elevated..."
    $arg = "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`""
    if ($PSBoundParameters.Count -gt 0) {
        # recompose param string
        $paramPairs = @()
        foreach ($k in $PSBoundParameters.Keys) {
            $v = $PSBoundParameters[$k]
            if ($v -is [switch]) {
                if ($v.IsPresent) { $paramPairs += "-$k" }
            } else {
                $escaped = $v.Replace("`"","`"`"")
                $paramPairs += "-$k `"$escaped`""
            }
        }
        $arg = $arg + " " + ($paramPairs -join ' ')
    }
    Start-Process -FilePath "powershell.exe" -ArgumentList $arg -Verb RunAs -WindowStyle Hidden
    Exit 0
}

# --- Ensure staging folder exists ---
Try { New-Item -ItemType Directory -Path $UpgradeFolder -Force | Out-Null } Catch { Log "Failed creating $UpgradeFolder: $_"; Exit 10 }
Log "Working folder: $UpgradeFolder"

# --- Logging startup info ---
Log "Upgrade orchestration started."
Log "SourceUri: $SourceUri"
Log "UseTempAdmin: $UseTempAdmin"
Log "TempAdminName: $TempAdminName"

# --- Stage install files: supports .zip (recommended) or .iso ---
Function Stage-InstallFiles {
    param([string]$uri, [string]$dest)
    if ([string]::IsNullOrWhiteSpace($uri)) {
        Log "No SourceUri provided - assuming setup.exe already present in $dest."
        return $true
    }

    $lower = $uri.ToLower()
    Try {
        If ($lower.EndsWith(".iso")) {
            $iso = Join-Path $dest "win11.iso"
            Log "Downloading ISO to $iso ..."
            Invoke-WebRequest -Uri $uri -OutFile $iso -UseBasicParsing -ErrorAction Stop
            Log "Mounting ISO..."
            Mount-DiskImage -ImagePath $iso -PassThru | Out-Null
            Start-Sleep -Seconds 3
            $vol = (Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' } | Select-Object -First 1).DriveLetter + ":\"
            if (-not $vol) { Throw "Mounted ISO but volume not found." }
            Log "Copying contents from $vol to $dest ..."
            robocopy $vol $dest /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
            Dismount-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue
            Remove-Item -Path $iso -Force -ErrorAction SilentlyContinue
            Log "ISO staged."
            return $true
        } elseif ($lower.EndsWith(".zip")) {
            $zipfile = Join-Path $dest "stage.zip"
            Log "Downloading zip to $zipfile ..."
            Invoke-WebRequest -Uri $uri -OutFile $zipfile -UseBasicParsing -ErrorAction Stop
            Log "Expanding zip..."
            Expand-Archive -Path $zipfile -DestinationPath $dest -Force
            Remove-Item -Path $zipfile -Force -ErrorAction SilentlyContinue
            Log "ZIP expanded."
            return $true
        } else {
            Log "SourceUri extension unsupported (expected .iso or .zip). Attempting direct download to file though may not be correct..."
            $out = Join-Path $dest (Split-Path $uri -Leaf)
            Invoke-WebRequest -Uri $uri -OutFile $out -UseBasicParsing -ErrorAction Stop
            Log "Downloaded $uri to $out"
            return $true
        }
    } Catch {
        Log "Error in Stage-InstallFiles: $($_.Exception.Message)"
        return $false
    }
}

# --- Ensure setup.exe is present; stage if missing ---
If (-not (Test-Path -Path $SetupExePath)) {
    Log "setup.exe not found. Attempting to stage from SourceUri..."
    $ok = Stage-InstallFiles -uri $SourceUri -dest $UpgradeFolder
    If (-not $ok -or -not (Test-Path -Path $SetupExePath)) {
        Log "Failed to stage setup.exe. Aborting."
        Exit 20
    }
} else {
    Log "setup.exe already present; skipping staging."
}

# --- Write setupconfig.ini to bypass checks ---
$setupConfigContent = @"
[SetupConfig]
BypassTPMCheck=1
BypassSecureBootCheck=1
BypassRAMCheck=1
BypassStorageCheck=1
BypassCPUCheck=1
DynamicUpdate=Disable
Telemetry=Disable
"@
Try {
    $setupConfigContent | Out-File -FilePath $SetupConfigPath -Encoding ascii -Force
    Log "Wrote setupconfig.ini to $SetupConfigPath"
} Catch { Log "Failed writing setupconfig.ini: $_"; Exit 21 }

# --- Detect interactive (console) users signed in ---
Function Get-InteractiveUsers {
    $users = @()
    Try {
        $quser = & quser 2>$null
        if ($LASTEXITCODE -eq 0 -and $quser) {
            foreach ($line in $quser) {
                # remove repeated spaces, split
                $norm = ($line -replace '\s+',' ')
                $parts = $norm.Trim() -split ' '
                if ($parts.Length -ge 3) {
                    $state = $parts[2]
                    if ($state -match 'Active|Console') {
                        $users += $parts[0]
                    }
                }
            }
        }
    } Catch { Log "quser detection failed: $_" }

    # fallback: owner of explorer.exe if nothing found
    if ($users.Count -eq 0) {
        Try {
            $proc = Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($proc) {
                $owner = (Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.Id)" | ForEach-Object { ($_.GetOwner()).User }) -join ','
                if ($owner) { $users += $owner }
            }
        } Catch {}
    }

    return $users | Select-Object -Unique
}

$activeUsers = Get-InteractiveUsers
If ($activeUsers.Count -eq 0) {
    Log "No interactive users detected."
    $NoUserSignedIn = $true
} else {
    Log "Interactive user(s) detected: $($activeUsers -join ', ')"
    $NoUserSignedIn = $false
}

# --- Optional: create temporary admin account so process appears under that name in Task Manager ---
If ($UseTempAdmin) {
    Try {
        if (-not (Get-LocalUser -Name $TempAdminName -ErrorAction SilentlyContinue)) {
            Log "Creating temporary admin account: $TempAdminName"
            $secure = ConvertTo-SecureString -String $TempAdminPasswordPlain -AsPlainText -Force
            New-LocalUser -Name $TempAdminName -Password $secure -FullName "Upgrade Monitor" -Description "Temporary account for Win11 upgrade monitoring" -PasswordNeverExpires -UserMayNotChangePassword:$false
            Add-LocalGroupMember -Group "Administrators" -Member $TempAdminName
            "Temp admin password: $TempAdminPasswordPlain" | Out-File -FilePath $LogFile -Append -Encoding utf8
            Log "Temp admin created and added to Administrators. (Password logged to logfile for testing - remove after.)"
        } else {
            Log "Temp admin $TempAdminName already exists; leaving it unchanged."
        }
    } Catch {
        Log "Error creating temp admin: $($_.Exception.Message)"
    }
}

# --- Build setup.exe arguments; if interactive users present add /noreboot ---
$BaseArgs = "/auto upgrade /quiet /compat IgnoreWarning /dynamicupdate Disable /showoobe none /Telemetry Disable /eula Accept /unattend `"$SetupConfigPath`" /copylogs `"$UpgradeFolder\setup-logs`""
If ($NoUserSignedIn) {
    $RunArgs = $BaseArgs   # allow reboot if installer needs
    Log "No interactive user -> installer will be allowed to reboot."
} else {
    $RunArgs = $BaseArgs + " /noreboot"
    Log "Interactive user(s) present -> /noreboot will be used to avoid disrupting them."
}

# --- Function: start installer (preferred method: register scheduled task to run under temp admin for visibility) ---
Function Start-Installer {
    param([string]$exePath, [string]$arguments)

    if ($UseTempAdmin) {
        Try {
            Log "Creating one-time scheduled task $ScheduledRunNowName to run installer as $TempAdminName..."
            $action = New-ScheduledTaskAction -Execute $exePath -Argument $arguments
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(15)
            $principal = New-ScheduledTaskPrincipal -UserId $TempAdminName -LogonType Password -RunLevel Highest
            Register-ScheduledTask -TaskName $ScheduledRunNowName -Action $action -Trigger $trigger -Principal $principal -Password $TempAdminPasswordPlain -Force | Out-Null
            Start-ScheduledTask -TaskName $ScheduledRunNowName
            Log "Scheduled and started $ScheduledRunNowName."
            return $true
        } Catch {
            Log "Failed scheduling installer under $TempAdminName: $($_.Exception.Message). Falling back to direct start."
        }
    }

    Try {
        Log "Starting setup.exe directly (current context / SYSTEM)."
        Start-Process -FilePath $exePath -ArgumentList $arguments -WindowStyle Hidden
        return $true
    } Catch {
        Log "Direct start failed: $($_.Exception.Message)"
        return $false
    }
}

# --- Start the installer ---
$started = Start-Installer -exePath $SetupExePath -arguments $RunArgs
If (-not $started) {
    Log "Failed to start installer. Aborting."
    Exit 30
}

# --- If interactive users present: notify them and create desktop notices; register recurring reboot-check task ---
If (-not $NoUserSignedIn) {
    Log "Notifying interactive users and creating desktop notices..."
    foreach ($u in $activeUsers) {
        Try {
            # try messaging by session name (if domain env supports it)
            & msg.exe $u "Windows 11 upgrade was installed. A reboot is required to finish installation. The system will NOT reboot while users are signed in. Please save your work." 2>$null
        } Catch {}
    }

    # Create a Desktop notice for each local profile found
    Try {
        $profiles = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { $_.LocalPath -and -not $_.Special } 
        foreach ($p in $profiles) {
            $desk = Join-Path $p.LocalPath "Desktop"
            if (Test-Path $desk) {
                $notice = @"
Windows 11 upgrade completed staging.
A reboot is required to finish installing Windows 11.
Please save your work and reboot at your convenience.
If you leave the system signed in, it will not reboot.
A scheduled checker will attempt to reboot when no users are signed in.
"@
                $outFile = Join-Path $desk "WINDOWS11_REBOOT_REQUIRED.txt"
                $notice | Out-File -FilePath $outFile -Encoding utf8 -Force
            }
        }
    } Catch { Log "Failed to write desktop notices: $_" }

    # Create reboot-check script
    $rebootScriptContent = @"
`$active = (& quser 2>`$null) -join ''
if ([string]::IsNullOrWhiteSpace(`$active)) {
    # no users - reboot with 60s countdown so we have a chance to cancel if needed
    shutdown /r /t 60 /c `"Rebooting now to finish Windows 11 upgrade.`"
}
"@
    Try {
        $rebootScriptContent | Out-File -FilePath $RebootCheckScript -Encoding ascii -Force
        Log "Wrote reboot-check script to $RebootCheckScript"
        # Register scheduled task to run every $RebootCheckMinutes
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$RebootCheckScript`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
        $trigger.RepetitionInterval = (New-TimeSpan -Minutes $RebootCheckMinutes)
        $trigger.RepetitionDuration = ([TimeSpan]::MaxValue)
        Register-ScheduledTask -TaskName $ScheduledRebootCheckName -Action $action -Trigger $trigger -RunLevel Highest -Force | Out-Null
        Log "Registered scheduled task $ScheduledRebootCheckName to run every $RebootCheckMinutes minutes."
    } Catch { Log "Failed to register reboot-check scheduled task: $_" }
}

# --- Register cleanup script to run at startup once; it will verify Windows edition and cleanup if Win11 present ---
$cleanupScriptContent = @"
# post-upgrade cleanup script - safe to run multiple times
Start-Sleep -Seconds 20
Try {
    `$prod = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).ProductName
} Catch { `$prod = '' }
# Only perform cleanup if it looks like Windows 11
if (`$prod -and `$prod -match 'Windows 11') {
    Try {
        # remove staged folder
        Remove-Item -LiteralPath '$UpgradeFolder' -Recurse -Force -ErrorAction SilentlyContinue
    } Catch {}
    Try { schtasks /Delete /TN `"$ScheduledRebootCheckName`" /F 2> $null } Catch {}
    Try { schtasks /Delete /TN `"$ScheduledRunNowName`" /F 2> $null } Catch {}
    Try { schtasks /Delete /TN `"$ScheduledCleanupName`" /F 2> $null } Catch {}
    # delete temp admin if it exists
    if ('$UseTempAdmin' -eq 'True') {
        try { net user $TempAdminName /delete 2>$null } catch {}
    }
}
"@
Try {
    $cleanupScriptContent | Out-File -FilePath $PostCleanupScript -Encoding ascii -Force
    Log "Wrote post-upgrade cleanup script to $PostCleanupScript"
    # Register a scheduled task at startup to run cleanup once
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PostCleanupScript`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName $ScheduledCleanupName -Action $action -Trigger $trigger -RunLevel Highest -Force | Out-Null
    Log "Registered startup cleanup scheduled task $ScheduledCleanupName."
} Catch { Log "Failed to register cleanup task: $_" }

Log "Installer started and orchestration complete. Check logs: $LogFile"
Exit 0
