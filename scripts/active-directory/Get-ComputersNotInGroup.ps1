<#
.SYNOPSIS
    Lists computer accounts in an OU that are not members of a given AD group (e.g. Servers OU vs "All-Servers").
.DESCRIPTION
    Enumerates all computers under the OU (subtree), gets the recursive computer members of the
    group and prints the computers that are missing from the group. Useful to catch servers that
    were added to the OU but never added to the group that scopes GPOs/monitoring.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module (RSAT) | no admin rights needed
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ComputersNotInGroup.ps1
#>

# Requires ActiveDirectory module (RSAT)
# Run on a machine with AD PowerShell module installed

Import-Module ActiveDirectory

# ---- EDIT ME ------------------------------------------------------------
$OU        = "OU=Servers,OU=Computers,DC=corp,DC=contoso,DC=local"
$GroupName = "All-Servers"
# -------------------------------------------------------------------------

# Get all computer accounts in the OU (and sub-OUs)
$computersInOU = Get-ADComputer -SearchBase $OU -SearchScope Subtree -Filter * |
    Select-Object -ExpandProperty DistinguishedName

# Get all members of the group (recursive to catch nested group members)
$groupMembers = Get-ADGroupMember -Identity $GroupName -Recursive |
    Where-Object { $_.objectClass -eq "computer" } |
    Select-Object -ExpandProperty DistinguishedName

# Find computers in the OU that are NOT in the group
$notInGroup = $computersInOU | Where-Object { $_ -notin $groupMembers }

if ($notInGroup.Count -eq 0) {
    Write-Host "All computers in the OU are members of '$GroupName'." -ForegroundColor Green
} else {
    Write-Host "`nComputers in OU but NOT in '$GroupName' ($($notInGroup.Count) found):" -ForegroundColor Yellow
    $notInGroup | ForEach-Object {
        # Resolve DN back to a friendly computer name
        (Get-ADComputer -Identity $_).Name
    } | Sort-Object | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor Cyan
    }
}
