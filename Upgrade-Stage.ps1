$Root = "C:\Win11Upgrade"
$IsoUrl = "https://dooleydigital.dev/files/Win11_24H2_English_x64.iso"
$IsoFile = "$Root\Win11_24H2_English_x64.iso"
$SetupDir = "$Root\SetupFiles"

New-Item -ItemType Directory -Force -Path $Root,$SetupDir | Out-Null

if (-not (Test-Path $IsoFile)) {
    Write-Host "Downloading ISO..."
    Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoFile -UseBasicParsing
}

Write-Host "Mounting..."
$disk = Mount-DiskImage -ImagePath $IsoFile -PassThru
Start-Sleep -Seconds 5
$vol = $disk | Get-Volume
$drive = $vol.DriveLetter + ":"
Write-Host "Copying from $drive ..."
robocopy $drive $SetupDir /E
Dismount-DiskImage -ImagePath $IsoFile
Write-Host "Extraction complete."
