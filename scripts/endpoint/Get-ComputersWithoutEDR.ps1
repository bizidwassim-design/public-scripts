<#
.SYNOPSIS
    List enabled AD computers that are missing from the EDR console export.
.DESCRIPTION
    Reads a text file of hostnames exported from the EDR portal (one name per line), compares it
    with every enabled computer object in Active Directory and exports the computers that are
    NOT protected to a CSV file, then opens it.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ComputersWithoutEDR.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$InputPath  = "C:\Scripts\edr\withedr.txt"        # hostnames exported from the EDR portal
$OutputPath = "C:\Scripts\edr\withoutEDR.csv"
# -------------------------------------------------------------------------

# Read the list of computer names from the input file
$computerNames = Get-Content -Path $InputPath

# Get all active computers from Active Directory
$activeComputers = Get-ADComputer -Filter {Enabled -eq $true}

# Exclude computers from the input list
$filteredComputers = $activeComputers | Where-Object { $computerNames -notcontains $_.Name }

# Export the filtered active computers to a CSV file
$filteredComputers | Export-Csv -Path $OutputPath -NoTypeInformation

start $OutputPath
