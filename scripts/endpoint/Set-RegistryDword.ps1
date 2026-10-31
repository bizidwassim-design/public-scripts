<#
.SYNOPSIS
    Sets (and creates if needed) a DWORD registry value from a single "HIVE\Key\ValueName" path string.
.DESCRIPTION
    Template: takes a full registry path whose last segment is the value name, converts the hive
    to the PowerShell drive form (HKLM: etc.), creates the key if missing, writes the DWORD and
    reads it back for confirmation. Example target: an Office policy value.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin for HKLM (remove the #Requires line if it blocks your deployment tool)
    Impact      : Modifies the local registry
    License     : MIT
.EXAMPLE
    .\Set-RegistryDword.ps1
#>

# Requires elevation (Run as Administrator)
#Requires -RunAsAdministrator

# ---- EDIT ME ------------------------------------------------------------
# Provide the full registry path including hive and value name as the last segment
# Example: "HKLM\SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeUpdate\hideenabledisableupdates"
$fullPath  = "HKLM\SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeUpdate\hideenabledisableupdates"
$regValue  = 1
# -------------------------------------------------------------------------

# Convert hive (e.g. HKLM) to PowerShell drive format (e.g. HKLM:)
$fullPathPS = $fullPath -replace "^(HK[A-Z_]+)\\", '$1:\'

# Split into key path and value name
$regPath = Split-Path $fullPathPS -Parent
$regName = Split-Path $fullPathPS -Leaf

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
}
catch {
    Write-Error "Failed to set registry value: $_"
}
