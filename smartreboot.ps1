# Ultra-Safe Reboot Script
# - Reboot immediately if no user logged in
# - If user logged in, reboot ONLY if no Office apps are running
# - Otherwise skip and log

$LogFile = "C:\Win11Upgrade\RebootLog.txt"

function Log($msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "$ts - $msg"
}

# Determine logged-in user
try { 
    $User = (Get-CimInstance Win32_ComputerSystem).UserName 
} catch { 
    $User = $null 
}

# --- Case 1: No user logged in → reboot immediately ---
if ([string]::IsNullOrEmpty($User)) {
    Log "No user logged in → rebooting immediately."
    shutdown /r /t 0 /c "Automatic reboot to complete updates."
    exit
}

Log "User logged in: $User"

# --- Case 2: Check for Office apps ---
$OfficeApps = @("WINWORD","EXCEL","POWERPNT","OUTLOOK","VISIO","MSPUB","ONENOTE")

$OfficeRunning = $false
foreach ($app in $OfficeApps) {
    if (Get-Process -Name $app -ErrorAction SilentlyContinue) {
        $OfficeRunning = $true
        Log "Office app detected: $app"
    }
}

if ($OfficeRunning) {
    Log "Reboot SKIPPED → Office applications open, preventing safe reboot."
    exit
}

# --- Safe conditions met → reboot ---
Log "No Office apps running → safe to reboot. Executing reboot now."

shutdown /r /t 60 /c "System will reboot in 60 seconds to complete updates."
