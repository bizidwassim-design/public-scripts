<#
.SYNOPSIS
    Enables Microsoft Defender Antivirus real-time behavior monitoring through the policy registry key.
.DESCRIPTION
    Sets HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection\DisableBehaviorMonitoring
    to 0 (equivalent to the GPO "Turn on behavior monitoring"), creates the key if needed, reads
    the value back and prints the Defender preference via Get-MpPreference for confirmation.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin (remove the #Requires line if it blocks your deployment tool) | Defender module
    Impact      : Modifies the local registry (Defender policy)
    License     : MIT
.EXAMPLE
    .\Enable-DefenderBehaviorMonitoring.ps1
#>

# Requires elevation (Run as Administrator)
#Requires -RunAsAdministrator

# This script enables Microsoft Defender Antivirus real-time behavior monitoring
# via the registry, equivalent to enabling the Group Policy:
# Computer Configuration\Administrative Templates\Windows Components\
#   Microsoft Defender Antivirus\Real-time Protection\Turn on behavior monitoring

$regPath  = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"
$regName  = "DisableBehaviorMonitoring"
$regValue = 0   # 0 = Behavior Monitoring ENABLED (policy not disabled)

try {
    # Ensure the registry key path exists
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
        Write-Host "Created registry path: $regPath" -ForegroundColor Yellow
    }

    # Set the DWORD value
    Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Type DWord

    # Verify the change
    $result = Get-ItemProperty -Path $regPath -Name $regName
    Write-Host "Successfully set '$regName' to '$($result.$regName)' at:" -ForegroundColor Green
    Write-Host "  $regPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "Behavior Monitoring is now ENABLED." -ForegroundColor Green

    # Confirm current Defender status via CIM
    $defenderStatus = Get-MpPreference
    Write-Host ""
    Write-Host "Defender DisableBehaviorMonitoring (should be False): $($defenderStatus.DisableBehaviorMonitoring)" -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to set registry value: $_"
}
