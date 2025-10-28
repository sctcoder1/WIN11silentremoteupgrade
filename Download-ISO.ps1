# ==============================================================
# Stage 1 – Download Windows 11 ISO
# ==============================================================

$Root   = "C:\Win11Upgrade"
$IsoUrl = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoFile = Join-Path $Root "Win11_24H2_English_x64.iso"

New-Item -ItemType Directory -Force -Path $Root | Out-Null

if (-not (Test-Path $IsoFile)) {
    Write-Host "Downloading ISO from $IsoUrl ..."
    try {
        Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoFile -UseBasicParsing
        Write-Host "✅ ISO downloaded to $IsoFile"
    } catch {
        Write-Host "❌ Download failed: $($_.Exception.Message)"
    }
} else {
    Write-Host "ISO already exists at $IsoFile"
}
