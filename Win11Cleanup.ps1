# Cleanup.ps1
# Removes Win11Upgrade folder + scheduled tasks after successful upgrade

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Log = Join-Path $ScriptDir "Cleanup.log"

function Log {
    param($msg)
    ("[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $msg") | Out-File $Log -Append
}

Start-Sleep -Seconds 10
Log "Cleanup started."

try {
    # Detect OS version
    $product = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
    Log "Detected product: $product"

    if ($product -match "Windows 11") {

        # Remove upgrade working directory
        $Root = "C:\Win11Upgrade"
        if (Test-Path $Root) {
            Log "Removing directory: $Root"
            try {
                Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction Stop
                Log "Directory removed successfully."
            } catch {
                Log "Failed to remove directory: $_"
            }
        } else {
            Log "Directory not found: $Root"
        }

        # Remove only the tasks YOU create
        $TasksToRemove = @(
            "Win11Upgrade",
            "Win11Reboot",
            "Win11Cleanup"
        )

        foreach ($task in $TasksToRemove) {
            try {
                schtasks /Delete /TN $task /F > $null 2>&1
                Log "Removed scheduled task: $task"
            } catch {
                Log "Task $task not found or could not be removed."
            }
        }

        Log "Cleanup complete."

    } else {
        Log "OS not Windows 11 yet → Cleanup skipped."
    }

} catch {
    Log "ERROR during cleanup: $_"
}

exit 0
