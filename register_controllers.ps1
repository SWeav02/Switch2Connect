# Run this script in PowerShell as Administrator to register the NYXI Hyperion 3 Joy-Con 2
# controllers in the Windows Bluetooth kernel registry (BTHPORT\Parameters\Keys).
# This prevents Windows BTHUSB from disconnecting the controllers after 28 seconds.

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Please run this script from an elevated PowerShell prompt (Run as Administrator)."
    exit 1
}

$scriptContent = @'
$keysRoot = "HKLM:\SYSTEM\CurrentControlSet\Services\BTHPORT\Parameters\Keys"
$adapterMac = (Get-ChildItem -Path $keysRoot -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty PSChildName)
if (!$adapterMac) {
    $adapterMac = "{0:x12}" -f 264597180458982
}

$controllers = @("c8480500213c", "c84805b5df27")
$ltkBytes = [byte[]](0xb6,0x4b,0xa9,0x6a,0xa5,0xea,0x47,0x27,0xc3,0xc5,0x64,0xd7,0x97,0x36,0x33,0x21)

foreach ($dev in $controllers) {
    $devPath = "$keysRoot\$adapterMac\$dev"
    if (!(Test-Path $devPath)) {
        New-Item -Path $devPath -Force | Out-Null
    }
    New-ItemProperty -Path $devPath -Name "KeyLength" -Value 16 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $devPath -Name "AuthReq" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $devPath -Name "LTK" -Value $ltkBytes -PropertyType Binary -Force | Out-Null
    New-ItemProperty -Path $devPath -Name "ERand" -Value 0 -PropertyType QWord -Force | Out-Null
    New-ItemProperty -Path $devPath -Name "EDIV" -Value 0 -PropertyType DWord -Force | Out-Null

    # Also register link key in adapter root
    New-ItemProperty -Path "$keysRoot\$adapterMac" -Name $dev -Value $ltkBytes -PropertyType Binary -Force | Out-Null
}
'@

$tempScript = "$env:TEMP\reg_bt_keys.ps1"
$scriptContent | Out-File -FilePath $tempScript -Encoding utf8 -Force

# Execute via one-time Scheduled Task under SYSTEM account to access BTHPORT\Keys
$taskName = "RegisterJoyconBTKeys"
$action = "powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$tempScript`""

schtasks /delete /tn $taskName /f 2>$null | Out-Null
schtasks /create /tn $taskName /tr $action /sc once /st 00:00 /ru "NT AUTHORITY\SYSTEM" /rl HIGHEST /f | Out-Null
schtasks /run /tn $taskName | Out-Null
Start-Sleep -Seconds 1
schtasks /delete /tn $taskName /f | Out-Null
Remove-Item -Path $tempScript -Force -ErrorAction SilentlyContinue

Write-Host "Restarting Bluetooth Support Service to apply kernel bonding keys..." -ForegroundColor Cyan
Restart-Service bthserv -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "==========================================================================" -ForegroundColor Green
Write-Host " Successfully registered Joy-Con 2 bonding keys in Windows BTHPORT!" -ForegroundColor Green
Write-Host " The 28-second BTHUSB Security Manager timeout will no longer occur." -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor Green
