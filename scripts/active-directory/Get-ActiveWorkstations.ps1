<#
.SYNOPSIS
    Export all enabled, non-server AD computer objects to CSV.
.DESCRIPTION
    Selects computers whose OperatingSystem does not contain "server" and that are enabled,
    writes them to workstations.csv in the current folder and opens the file.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ActiveWorkstations.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$OutputPath = ".\workstations.csv"
# -------------------------------------------------------------------------

# Import the Active Directory module
Import-Module ActiveDirectory

# Get all active and enabled workstations
$workstations = Get-ADComputer -Filter {OperatingSystem -notlike "*server*"} -Properties Name,Enabled | Where-Object {$_.Enabled -eq $true}

# Export the results to a CSV file
$workstations | Export-Csv -Path $OutputPath -NoTypeInformation
start $OutputPath
