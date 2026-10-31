<#
.SYNOPSIS
    Build a membership matrix of the high-privilege AD groups (Domain / Enterprise / Schema Admins, Administrators).
.DESCRIPTION
    Recursively expands the members of each high-privilege group, de-duplicates users and produces one
    row per user with a True/False column per group. Prints the matrix and exports it to a CSV.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-PrivilegedAccountMatrix.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$OutputPath     = "C:\Scripts\Reports\HighPrivilegedMembershipMatrix.csv"
# Define high-privileged AD groups
$highPrivGroups = @("Domain Admins", "Enterprise Admins", "Schema Admins", "Administrators")
# -------------------------------------------------------------------------

# Import the Active Directory module
Import-Module ActiveDirectory

# Initialize a hashtable to store user memberships
$userMemberships = @{}

# Loop through each group and collect user memberships
foreach ($group in $highPrivGroups) {
    $members = Get-ADGroupMember -Identity $group -Recursive | Where-Object { $_.objectClass -eq 'user' }
    foreach ($member in $members) {
        $samAccountName = $member.SamAccountName
        if (-not $userMemberships.ContainsKey($samAccountName)) {
            $userMemberships[$samAccountName] = [PSCustomObject]@{
                UserName         = $samAccountName
                DisplayName      = $member.Name
                DistinguishedName = $member.DistinguishedName
                'Domain Admins'  = $false
                'Enterprise Admins' = $false
                'Schema Admins'  = $false
                'Administrators' = $false
            }
        }
        # Mark the membership for the corresponding group
        $userMemberships[$samAccountName].$group = $true
    }
}

# Convert the hashtable values to an array
$userMembershipsArray = $userMemberships.Values

# Display the results as a table
$userMembershipsArray | Select-Object UserName, DisplayName, 'Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators' | Format-Table -AutoSize

# Optionally, export to a CSV file
$userMembershipsArray | Select-Object UserName, DisplayName, 'Domain Admins', 'Enterprise Admins', 'Schema Admins', 'Administrators' | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Membership matrix exported to $OutputPath"
