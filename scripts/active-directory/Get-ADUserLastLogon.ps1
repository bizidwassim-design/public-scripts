<#
.SYNOPSIS
    Report the last logon date of every AD user account.
.DESCRIPTION
    Enumerates all users and exports Name / UserPrincipalName / Enabled / LastLogon ("Never" when
    LastLogonDate is empty) to a CSV file, then opens it.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ADUserLastLogon.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$OutputPath = "UsersAccountsReport.csv"
# -------------------------------------------------------------------------

# Retrieve all user accounts and their properties
$users = Get-ADUser -Filter * -Properties *

# Create a custom object to store the user account information
$report = foreach ($user in $users) {
    [PSCustomObject]@{
        Name        = $user.Name
        UserPrincipalName        = $user.UserPrincipalName
        Enabled     = $user.Enabled
        LastLogon   = if ($user.LastLogonDate) { $user.LastLogonDate } else { "Never" }
    }
}

# Export the report to a CSV file
$report | Export-Csv -Path $OutputPath -NoTypeInformation ; start $OutputPath
