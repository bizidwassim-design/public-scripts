<#
.SYNOPSIS
    List AD groups that have no members (candidates for clean-up).
.DESCRIPTION
    Reads every group in the domain with its Members attribute, keeps the ones with no member,
    prints Name / DistinguishedName to the console and exports the list to a CSV.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-EmptyADGroups.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$OutputPath = "C:\Scripts\Reports\EmptyGroups.csv"
# -------------------------------------------------------------------------

# Import Active Directory module
Import-Module ActiveDirectory

# Get all groups in the domain
$allGroups = Get-ADGroup -Filter * -Properties Members

# Initialize an array to store empty groups
$emptyGroups = @()

# Loop through each group and check if it has members
foreach ($group in $allGroups) {
    if (-not $group.Members) {
        # Add group to empty groups list
        $emptyGroups += $group
    }
}

# Output the empty groups
$emptyGroups | Select-Object Name, DistinguishedName | Format-Table -AutoSize

# Optionally, export to a CSV file
$emptyGroups | Select-Object Name, DistinguishedName | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
