<#
.SYNOPSIS
    Add a list of computer accounts to an AD group (e.g. a pilot-workstations group), skipping disabled ones.
.DESCRIPTION
    Looks up each computer name under the search base, skips the ones not found or disabled, and adds
    the others to the target group. Progress is written to the console.
    Naming convention used in the example list: L-### laptops, D-### desktops.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Modifies AD (group membership)
    License     : MIT
.EXAMPLE
    .\Add-ComputersToADGroup.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# List of all computers to be added to the group
$Computers = @(
    "L-001", "L-002", "D-003"
)
# Group to which computers will be added
$GroupName = "Pilot-Workstations"
$BaseDN    = "OU=Computers,DC=corp,DC=contoso,DC=local"
# -------------------------------------------------------------------------

foreach ($Computer in $Computers) {
    # Get the computer object from AD
    $ComputerObject = Get-ADComputer -Filter {Name -eq $Computer} -SearchBase $BaseDN -SearchScope Subtree -ErrorAction SilentlyContinue

    # If computer object is found
    if ($null -eq $ComputerObject) {
        Write-Host "Failed to find $Computer in Active Directory."
        continue
    }

    # Check if the computer is disabled
    if ($ComputerObject.Enabled -eq $false) {
        Write-Host "$Computer is disabled. Skipping addition to the group."
        continue
    }

    # Add the computer to the group
    try {
        Add-ADGroupMember -Identity $GroupName -Members $ComputerObject.DistinguishedName
        Write-Host "$Computer successfully added to $GroupName."
    } catch {
        Write-Host "Failed to add $Computer to $GroupName. Error: $_"
    }
}
