# Cleanup.ps1
$Log = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "Cleanup.log"
function Log { param($m) ("[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m") | Out-File $Log -Append }

Start-Sleep -Seconds 20
Log "Cleanup started."

try {
    $product = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
    Log "Detected product: $product"
    if ($product -match "Windows 11") {
        # Remove extracted repo dir and upgrade files
        $Root = "C:\Win11Upgrade"
        Log "Removing $Root ..."
        Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue

        # Remove temp admin user
        $user = "WinUpgTemp"
        if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
            Log "Removing local user $user ..."
            try { Remove-LocalUser -Name $user -ErrorAction SilentlyContinue } catch { Log "Failed to remove user: $_" }
        } else {
            Log "Temp user $user not found."
        }

        # Delete scheduled tasks if still present
        foreach ($t in @("Win11_RepoHandler","Win11_Upgrade","Win11_Cleanup")) {
            try { schtasks /Delete /TN $t /F > $null 2>&1 } catch {}
        }

        Log "Cleanup complete."
    } else {
        Log "OS not Windows 11 yet. Skipping destructive cleanup."
    }
} catch {
    Log "ERROR during cleanup: $_"
}
exit 0
