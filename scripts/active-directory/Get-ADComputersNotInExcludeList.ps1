<#
.SYNOPSIS
    Export enabled L-*/D-* AD workstations that are not listed in an exclusion file.
.DESCRIPTION
    Gets every enabled computer whose name starts with "l-" or "d-" (laptop/desktop convention),
    removes the hostnames found in an exclude list and exports the remainder to CSV. Used to build
    the target list for an agent deployment (e.g. PDQ Connect).
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ADComputersNotInExcludeList.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$ExcludeListPath = "C:\Scripts\PDQconnect\ExcludeList.txt"   # one hostname per line
$OutputPath      = "C:\Scripts\PDQconnect\ExportedDevices.csv"
# -------------------------------------------------------------------------

# Import the Active Directory module if not already loaded
Import-Module ActiveDirectory

# Get all computer objects from AD
$allComputers = Get-ADComputer -Filter *

# Filter for active devices with computer names starting with "l-" or "d-"
$filteredComputers = $allComputers | Where-Object { $_.Enabled -eq $true -and $_.Name -match '^(l-|d-)' }

# Load the list of hostnames from a text file
$excludeList = Get-Content -Path $ExcludeListPath

# Filter out devices that are not in the exclude list
$filteredDevices = $filteredComputers | Where-Object { $_.Name -notin $excludeList }

# Export the filtered list to a CSV file
$filteredDevices | Export-Csv -Path $OutputPath -NoTypeInformation
