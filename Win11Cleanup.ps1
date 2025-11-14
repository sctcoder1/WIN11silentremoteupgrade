# Safe Cleanup Script
# Only runs if OS is Windows 11 AND upgrade folder exists

$Log = "C:\Win11Upgrade\Cleanup.log"
function Log { param($m) ("[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m") | Out-File $Log -Append }

Log "Cleanup started."

# Check OS version — must be Windows 11
try {
    $prod = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
} catch {
    $prod = ""
}

if ($prod -notmatch "Windows 11") {
    Log "OS is NOT Windows 11 → Cleanup aborted."
    exit
}

# Check if upgrade folder exists
$root = "C:\Win11Upgrade"
if (-not (Test-Path $root)) {
    Log "Upgrade folder not found → Nothing to clean."
    exit
}

Log "Confirmed Windows 11. Proceeding with cleanup."

# Delete the upgrade folder
try {
    Remove-Item $root -Recurse -Force -ErrorAction Stop
    Log "Deleted upgrade folder: $root"
} catch {
    Log "Failed to delete upgrade folder: $_"
}

# Delete scheduled tasks (optional but safe)
foreach ($t in @("Win11Upgrade","Win11Reboot","Win11Cleanup")) {
    try { schtasks /Delete /TN $t /F > $null 2>&1; Log "Deleted scheduled task: $t" } catch {}
}

Log "Cleanup completed successfully."
