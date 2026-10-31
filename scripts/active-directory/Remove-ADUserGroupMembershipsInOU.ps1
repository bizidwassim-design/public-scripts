<#
.SYNOPSIS
    Strips every group membership (except "Domain Users") from all users of a given OU.
.DESCRIPTION
    Enumerates the users of the OU, reads their MemberOf attribute and removes them from each
    group, logging every removal to the console. Typically used on an OU of departed /
    disabled accounts before archiving them.
    Note: the comparison is made against the group DistinguishedName, so the primary group
    "Domain Users" is skipped only because AD refuses to remove a primary group membership.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Modifies AD (removes users from groups) — run with $WhatIf = $true first
    License     : MIT
.EXAMPLE
    .\Remove-ADUserGroupMembershipsInOU.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Specify the DN (DistinguishedName) of the OU where the users are located
$ouDN   = "OU=Disabled,OU=Users,DC=corp,DC=contoso,DC=local"
$WhatIf = $true    # set to $false to actually remove memberships
# -------------------------------------------------------------------------

# Import the Active Directory module
Import-Module ActiveDirectory

# Get all users in the specified OU
$users = Get-ADUser -Filter * -SearchBase $ouDN

# Specify the group name to exclude (e.g., "Domain Users")
$excludedGroup = "Domain Users"

# Loop through each user and remove all group memberships except the excluded group
foreach ($user in $users) {
    $userDN = $user.DistinguishedName
    $groupMemberships = Get-ADUser $userDN | Get-ADUser -Properties MemberOf | Select-Object -ExpandProperty MemberOf

    foreach ($group in $groupMemberships) {
       if ($group -ne $excludedGroup) {
        Remove-ADGroupMember -Identity $group -Members $userDN -Confirm:$false -WhatIf:$WhatIf
        Write-Host "Removed $userDN from group $group"
       }
    }
}

# Optional: If you want to remove users from the "Domain Users" group as well, uncomment the following line

# Remove-ADGroupMember -Identity "Domain Users" -Members $users.DistinguishedName -Confirm:$false
