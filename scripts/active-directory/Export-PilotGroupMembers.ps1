<#
.SYNOPSIS
    Export the members of an AD pilot group with their manager and the computers assigned to them.
.DESCRIPTION
    Recursively lists the user members of a group, resolves the manager display name and finds every
    computer object whose Description equals the user's DisplayName (convention: the computer
    Description holds the owner's name). Exports DisplayName / Sam / Email / Department / Title /
    Manager / DN / City / Computer to a CSV and opens it.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Export-PilotGroupMembers.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$GroupName      = "Pilot-Users"
$OutputFile     = "C:\Scripts\Reports\Pilot-Users_Members.csv"
$ComputerSearch = "OU=Computers,DC=corp,DC=contoso,DC=local"
# -------------------------------------------------------------------------

# Import the Active Directory module
Import-Module ActiveDirectory

# Initialize an array to hold the user details
$UserDetails = @()

# Get all members of the group
$GroupMembers = Get-ADGroupMember -Identity $GroupName -Recursive | Where-Object { $_.objectClass -eq "user" }

# Iterate through each member
foreach ($Member in $GroupMembers) {
    try {
        # Get detailed user information
        $User = Get-ADUser -Identity $Member.SamAccountName -Properties DisplayName, EmailAddress, Description, Department, Title, Manager, DistinguishedName, City

        # Resolve the manager's name
        $ManagerName = if ($User.Manager) {
            try {
                (Get-ADUser -Identity $User.Manager -Properties DisplayName).DisplayName
            } catch {
                "Error retrieving manager"
            }
        } else {
            "No manager assigned"
        }

        # Find all computer accounts with matching description
        $ComputerAccounts = Get-ADComputer -Filter * -SearchBase $ComputerSearch -Properties Description |
                            Where-Object { $_.Description -eq $User.DisplayName }

        # Collect all matching computer names into a single string
        $ComputerNames = if ($ComputerAccounts) {
            ($ComputerAccounts | Select-Object -ExpandProperty Name -Unique) -join ", "
        } else {
            "No computers found"
        }

        # Add user details to the array
        $UserDetails += [PSCustomObject]@{
            DisplayName       = $User.DisplayName
            SamAccountName    = $User.SamAccountName
            Email             = $User.EmailAddress
            Description       = $User.Description
            Department        = $User.Department
            JobTitle          = $User.Title
            Manager           = $ManagerName
            DistinguishedName = $User.DistinguishedName
            City              = $User.City
            Computer          = $ComputerNames
        }
    } catch {
        Write-Host "Failed to retrieve details for user:" $Member.SamAccountName -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
}

# Export the user details to a CSV file
$UserDetails | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

Write-Host "User details exported to $OutputFile"

# Open the CSV file automatically
Start-Process $OutputFile
