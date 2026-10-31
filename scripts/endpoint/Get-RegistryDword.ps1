<#
.SYNOPSIS
    Reads a DWORD registry value from a single "HIVE\Key\ValueName" path string.
.DESCRIPTION
    Template companion to Set-RegistryDword.ps1: converts the hive prefix to the PowerShell drive
    form, splits the key path from the value name and prints the value with Get-ItemProperty.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : nothing (read access to the key)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-RegistryDword.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Provide the full registry path including hive and value name as the last segment
# Example: "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Scan\DisableEmailScanning"
$fullPath  = "HKLM\SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeUpdate\hideenabledisableupdates"
# -------------------------------------------------------------------------

# Convert hive (e.g. HKLM) to PowerShell drive format (e.g. HKLM:)
$fullPathPS = $fullPath -replace "^(HK[A-Z_]+)\\", '$1:\'
# Split into key path and value name
$regPath = Split-Path $fullPathPS -Parent
$regName = Split-Path $fullPathPS -Leaf

# Get the DWORD value
Get-ItemProperty -Path $regPath -Name $regName
