<#
.SYNOPSIS
    Export the (approximate) disabled date of every account in a given OU.
.DESCRIPTION
    Reads all user objects under the target OU, uses whenChanged as an approximation of the
    date the account was disabled, resolves the manager display name and exports
    Name / UPN / DisabledDateTime / AccountStatus / Description / Manager to a CSV.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-DisabledAccountDates.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$ou         = "OU=Disabled,OU=Users,DC=corp,DC=contoso,DC=local"
$OutputPath = "C:\Scripts\Reports\disabled_accounts.csv"
# -------------------------------------------------------------------------

# Retrieve all user accounts within the specific OU
$users = Get-ADUser -Filter * -SearchBase $ou -Properties DisplayName, Enabled, whenChanged, whenCreated, userAccountControl, Description, Manager

# Create an array to store results
$result = @()

# Loop through each user
foreach ($user in $users) {
    # Initialize account status based on user enabled status
    $accountStatus = if ($user.Enabled -eq $false) { "Disabled" } else { "Active" }

    # Get the date and time when the account was last changed (an approximation for when it was disabled)
    $disabledDateTime = if ($user.Enabled -eq $false) { $user.whenChanged } else { $null }

    # Retrieve manager details, if the manager exists
    $managerName = if ($user.Manager) {
        (Get-ADUser -Identity $user.Manager -Properties DisplayName).DisplayName
    } else {
        $null
    }

    # Create a custom object with the required details, account status, description, and manager
    $userDetails = [PSCustomObject]@{
        Name              = $user.DisplayName
        UserPrincipalName = $user.UserPrincipalName
        DisabledDateTime  = $disabledDateTime
        AccountStatus     = $accountStatus
        Description       = $user.Description
        Manager           = $managerName
    }

    # Add the user details to the result array
    $result += $userDetails
}

# Export the results to a CSV file
$result | Export-Csv -Path $OutputPath -NoTypeInformation

Write-Host "Disabled account details exported to CSV."

start $OutputPath
