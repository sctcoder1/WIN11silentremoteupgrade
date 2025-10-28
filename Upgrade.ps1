# ==============================================================
# Upgrade.ps1 – Windows 10 → 11 Fully Silent (No ISO Mount)
# Works in restricted contexts such as Sophos Live Response
# ==============================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root      = "C:\Win11Upgrade"
$LogFile   = Join-Path $Root "Upgrade.log"
$ZipUrl    = "https://dooleydigital.dev/files/Win11_24H2_SetupFiles.zip"
$ZipFile   = Join-Path $Root "Win11_24H2_SetupFiles.zip"
$SetupDir  = Join-Path $Root "SetupFiles"
$SetupCfg  = Join-Path $Root "setupconfig.ini"

function Log { param($m) Add-Content -Path $LogFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $m" -Encoding UTF8 }
function Fail { param($m) Log "ERROR: $m"; exit 1 }

# --- Ensure folders ---
New-Item -ItemType Directory -Force -Path $Root,$SetupDir | Out-Null
Log "Upgrade.ps1 started."

# --- Download pre-extracted setup files ---
if (-not (Test-Path (Join-Path $SetupDir "setup.exe"))) {
    Log "Downloading setup package from $ZipUrl..."
    try {
        Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipFile -UseBasicParsing
        Log "Extracting setup files..."
        Expand-Archive -Path $ZipFile -DestinationPath $SetupDir -Force
        Remove-Item $ZipFile -Force
        Log "Setup files extracted successfully."
    } catch {
        Fail "Failed to download or extract setup package: $($_.Exception.Message)"
    }
} else {
    Log "Setup files already available at $SetupDir."
}

# --- Validate setup.exe ---
$SetupExe = Join-Path $SetupDir "setup.exe"
if (-not (Test-Path $SetupExe)) { Fail "setup.exe not found after extraction." }
Log "setup.exe located at $SetupExe."

# --- Create setupconfig.ini (bypass checks) ---
@"
[SetupConfig]
BypassTPMCheck=1
BypassSecureBootCheck=1
BypassRAMCheck=1
BypassStorageCheck=1
BypassCPUCheck=1
DynamicUpdate=Disable
Telemetry=Disable
"@ | Out-File $SetupCfg -Encoding ascii -Force
Log "setupconfig.ini written."

# --- Build and run silent upgrade ---
$Args = '/auto upgrade /quiet /noreboot /dynamicupdate disable /compat IgnoreWarning /Telemetry Disable /eula Accept /unattend "' + $SetupCfg + '"'
Log "Starting setup.exe silently..."
try {
    Start-Process -FilePath $SetupExe -ArgumentList $Args -WorkingDirectory $SetupDir
    Log "setup.exe launched (detached, fully silent)."
} catch {
    Fail "Failed to launch setup.exe: $($_.Exception.Message)"
}

Log "Upgrade.ps1 completed — Windows setup now running in background."
exit 0
