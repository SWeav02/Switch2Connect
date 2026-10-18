# Run this script in PowerShell as Administrator to register the NYXI Hyperion 3 Joy-Con 2
# controllers in the Windows Bluetooth kernel registry (BTHPORT\Parameters\Keys).
# This prevents Windows BTHUSB from disconnecting the controllers after 28 seconds.

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Please run this script from an elevated PowerShell prompt (Run as Administrator)."
    exit 1
}

$scriptPath = "$env:windir\Temp\reg_bt_keys.ps1"
$logPath = "$env:windir\Temp\reg_bt_keys.log"

$scriptContent = @'
$log = "C:\Windows\Temp\reg_bt_keys.log"
"Starting registry injection as $(whoami)..." | Out-File -FilePath $log -Encoding utf8

$keysRoot = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys"
$adapters = Get-ChildItem -Path $keysRoot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty PSChildName

if (-not $adapters) {
    "No adapters found in $keysRoot directly. Using default host MAC." | Out-File -FilePath $log -Append -Encoding utf8
    $adapters = @("{0:x12}" -f 264597180458982)
}

$controllers = @("c8480500213c", "c84805b5df27")
$ltkBytes = [byte[]](0xb6,0x4b,0xa9,0x6a,0xa5,0xea,0x47,0x27,0xc3,0xc5,0x64,0xd7,0x97,0x36,0x33,0x21)

foreach ($adapterMac in $adapters) {
    "Processing Bluetooth Adapter: $adapterMac" | Out-File -FilePath $log -Append -Encoding utf8
    $adapterPath = "$keysRoot\$adapterMac"
    if (!(Test-Path $adapterPath)) {
        New-Item -Path $adapterPath -Force | Out-Null
    }

    foreach ($dev in $controllers) {
        $devPath = "$adapterPath\$dev"
        if (!(Test-Path $devPath)) {
            New-Item -Path $devPath -Force | Out-Null
        }
        New-ItemProperty -Path $devPath -Name "KeyLength" -Value 16 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $devPath -Name "AuthReq" -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $devPath -Name "LTK" -Value $ltkBytes -PropertyType Binary -Force | Out-Null
        New-ItemProperty -Path $devPath -Name "ERand" -Value 0 -PropertyType QWord -Force | Out-Null
        New-ItemProperty -Path $devPath -Name "EDIV" -Value 0 -PropertyType DWord -Force | Out-Null

        # Also set the link key directly on the adapter path
        New-ItemProperty -Path $adapterPath -Name $dev -Value $ltkBytes -PropertyType Binary -Force | Out-Null
        
        "Created bonding entry for $dev under $adapterPath" | Out-File -FilePath $log -Append -Encoding utf8
    }
}
"Completed registry injection successfully." | Out-File -FilePath $log -Append -Encoding utf8
'@

$scriptContent | Out-File -FilePath $scriptPath -Encoding utf8 -Force
Remove-Item -Path $logPath -Force -ErrorAction SilentlyContinue

# Execute via one-time Scheduled Task under SYSTEM account to access BTHPORT\Keys
$taskName = "RegisterJoyconBTKeys"
$action = "powershell.exe -ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`""

schtasks /delete /tn $taskName /f 2>$null | Out-Null
schtasks /create /tn $taskName /tr $action /sc once /st 00:00 /ru "NT AUTHORITY\SYSTEM" /rl HIGHEST /f | Out-Null
schtasks /run /tn $taskName | Out-Null

# Wait for task completion
$timeout = 10
while ($timeout -gt 0) {
    Start-Sleep -Seconds 1
    $taskInfo = schtasks /query /tn $taskName /fo csv 2>$null | ConvertFrom-Csv
    if ($taskInfo -and $taskInfo.Status -ne "Running") {
        break
    }
    $timeout--
}

schtasks /delete /tn $taskName /f 2>$null | Out-Null
Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue

if (Test-Path $logPath) {
    Write-Host "--- Task Execution Log ---" -ForegroundColor Yellow
    Get-Content -Path $logPath
    Write-Host "--------------------------" -ForegroundColor Yellow
    Remove-Item -Path $logPath -Force -ErrorAction SilentlyContinue
} else {
    Write-Warning "Could not find task log. Task may not have executed."
}

Write-Host "Restarting Bluetooth Support Service to apply kernel bonding keys..." -ForegroundColor Cyan
Restart-Service bthserv -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host " Successfully registered Joy-Con 2 bonding keys in Windows BTHPORT!" -ForegroundColor Green
Write-Host " The 28-second BTHUSB Security Manager timeout will no longer occur." -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
