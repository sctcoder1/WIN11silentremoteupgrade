# ==============================================================
# Stage 3 – Launch Silent Windows 11 Upgrade
# ==============================================================

$Root = "C:\Win11Upgrade"
$SetupDir = Join-Path $Root "SetupFiles"
$SetupExe = Join-Path $SetupDir "setup.exe"
$SetupCfg = Join-Path $Root "setupconfig.ini"

if (-not (Test-Path $SetupExe)) {
    Write-Host "❌ setup.exe not found in $SetupDir"
    exit 1
}

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
Write-Host "setupconfig.ini written."

$Args = '/auto upgrade /quiet /noreboot /dynamicupdate disable /compat IgnoreWarning /Telemetry Disable /eula Accept /unattend "' + $SetupCfg + '"'

Write-Host "Launching setup.exe silently..."
try {
    Start-Process -FilePath $SetupExe -ArgumentList $Args -WorkingDirectory $SetupDir
    Write-Host "✅ setup.exe launched (silent background mode)."
} catch {
    Write-Host "❌ Failed to launch setup: $($_.Exception.Message)"
}
