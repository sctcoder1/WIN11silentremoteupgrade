# Cleanup.ps1
$Root = "C:\Win11Upgrade"
$Log  = "$Root\Cleanup.log"
function Log($m){ ("[$(Get-Date)] $m") | Out-File $Log -Append }

Start-Sleep -Seconds 15
Log "Starting cleanup."

try {
    $Product = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ProductName
    if ($Product -match "Windows 11") {
        Log "Windows 11 confirmed. Removing upgrade files and temp admin."
        Remove-Item -Recurse -Force $Root -ErrorAction SilentlyContinue
        Remove-LocalUser -Name "WinUpgTemp" -ErrorAction SilentlyContinue
        schtasks /Delete /TN "Win11_RepoHandler" /F >$null 2>&1
        schtasks /Delete /TN "Win11_Upgrade" /F >$null 2>&1
        schtasks /Delete /TN "Win11_Cleanup" /F >$null 2>&1
        Log "Cleanup complete."
    } else {
        Log "OS still reports $Product — skipping cleanup."
    }
} catch {
    Log "ERROR during cleanup: $_"
}
exit 0
