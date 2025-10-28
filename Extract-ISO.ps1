# ==============================================================
# Stage 2 – Mount and Extract Windows 11 ISO
# ==============================================================

$Root = "C:\Win11Upgrade"
$IsoFile  = Join-Path $Root "Win11_24H2_English_x64.iso"
$SetupDir = Join-Path $Root "SetupFiles"

New-Item -ItemType Directory -Force -Path $SetupDir | Out-Null

Write-Host "Mounting $IsoFile ..."
try {
    $disk = Mount-DiskImage -ImagePath $IsoFile -PassThru
    Start-Sleep -Seconds 5
    $vol = $disk | Get-Volume -ErrorAction SilentlyContinue
    if (-not $vol) { throw "No volume detected." }
    $drive = "$($vol.DriveLetter):"
    Write-Host "Mounted on $drive"

    Write-Host "Copying setup files to $SetupDir ..."
    robocopy $drive $SetupDir /E
    Write-Host "✅ Files copied."

    Dismount-DiskImage -ImagePath $IsoFile
    Write-Host "ISO dismounted."
} catch {
    Write-Host "❌ Extraction failed: $($_.Exception.Message)"
}
