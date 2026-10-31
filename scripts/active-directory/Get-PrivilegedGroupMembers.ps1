<#
.SYNOPSIS
    Print the members of the built-in privileged AD groups (Domain Admins, Enterprise Admins, Administrators).
.DESCRIPTION
    Iterates over the privileged groups listed in $privilegedGroups, resolves each member as a user
    and writes "<group> Member: <SamAccountName>" to the console.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-PrivilegedGroupMembers.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Define an array of privileged groups
$privilegedGroups = @("Domain Admins", "Enterprise Admins", "Administrators")
# -------------------------------------------------------------------------

# Import the Active Directory module
Import-Module ActiveDirectory

# Iterate through each privileged group and retrieve members
foreach ($group in $privilegedGroups) {
    $members = Get-ADGroupMember -Identity $group

    # Display the members of each privileged group
    foreach ($member in $members) {
        $user = Get-ADUser -Identity $member
        Write-Host "$group Member: $($user.SamAccountName)"
    }
}
