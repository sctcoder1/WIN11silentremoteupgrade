# RepoHandler.ps1
# Self-contained version for C:\Win11Upgrade
# Handles downloading repo, scheduling upgrade + cleanup

$Root = "C:\Win11Upgrade"
$RepoUrl = "https://api.github.com/repos/sctcoder1/WIN11-inplace/zipball/main"
$Zip = "$Root\repo.zip"
$Token = "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"  # <--- Place token here
$Headers = @{ Authorization = "token $Token" }
$User = "WinUpgTemp"
$Log = "$Root\RepoHandler.log"

function Log($msg){ ("[$(Get-Date)] $msg") | Out-File $Log -Append }

Log "Starting RepoHandler."

# --- Check for existing extraction ---
$Existing = Get-ChildItem $Root -Directory | Where-Object Name -like "*WIN11-inplace*" | Select-Object -First 1
if ($Existing) {
    Log "Repo already exists at $($Existing.FullName). Skipping download."
    $WorkDir = $Existing.FullName
} else {
    if (Test-Path $Zip) { Log "Removing old zip..."; Remove-Item $Zip -Force }
    Log "Downloading repo ZIP from GitHub..."
    Invoke-WebRequest -Uri $RepoUrl -Headers $Headers -OutFile $Zip -UseBasicParsing
    Log "Extracting..."
    Expand-Archive -Path $Zip -DestinationPath $Root -Force
    Remove-Item $Zip -Force
    $WorkDir = (Get-ChildItem $Root -Directory | Where-Object Name -like "*WIN11-inplace*" | Select-Object -First 1).FullName
    Log "Extraction complete: $WorkDir"
}

# --- Schedule main upgrade BAT ---
$Bat = Join-Path $WorkDir "Win11_Upgrade.bat"
if (-not (Get-ScheduledTask -TaskName "Win11_Upgrade" -ErrorAction SilentlyContinue)) {
    Log "Scheduling Win11_Upgrade.bat..."
    $act = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min `"$Bat`""
    $trg = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddSeconds(30))
    $prn = New-ScheduledTaskPrincipal -UserId $User -RunLevel Highest
    Register-ScheduledTask -TaskName "Win11_Upgrade" -Action $act -Trigger $trg -Principal $prn -Force | Out-Null
    Start-ScheduledTask -TaskName "Win11_Upgrade"
} else {
    Log "Win11_Upgrade task already exists. Skipping scheduling."
}

# --- Schedule cleanup on startup ---
$CleanupBat = Join-Path $WorkDir "Cleanup.bat"
if (-not (Get-ScheduledTask -TaskName "Win11_Cleanup" -ErrorAction SilentlyContinue)) {
    Log "Scheduling Win11_Cleanup.bat..."
    $act2 = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c start /min `"$CleanupBat`""
    $trg2 = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName "Win11_Cleanup" -Action $act2 -Trigger $trg2 -RunLevel Highest -Force | Out-Null
} else {
    Log "Cleanup task already exists. Skipping scheduling."
}

Log "RepoHandler complete. Exiting."
