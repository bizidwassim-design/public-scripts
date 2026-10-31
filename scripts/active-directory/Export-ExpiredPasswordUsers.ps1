<#
.SYNOPSIS
    Exports enabled AD users whose password has expired to a CSV.
.DESCRIPTION
    Queries Active Directory for enabled accounts where PasswordNeverExpires is false and
    PasswordExpired is true, then exports SamAccountName, DisplayName, EmailAddress,
    PasswordLastSet and the computed password expiry date to a CSV and opens it.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Export-ExpiredPasswordUsers.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Specify the path for the CSV file
$csvPath = "C:\Scripts\Reports\ExpiredPasswordUsers.csv"
# -------------------------------------------------------------------------

# Import the Active Directory module
Import-Module ActiveDirectory

# Get the current date
$currentDate = Get-Date

# Get expired password accounts
$expiredAccounts = Get-ADUser -Filter {Enabled -eq $true -and PasswordNeverExpires -eq $false -and PasswordExpired -eq $true} -Properties "SamAccountName", "DisplayName", "EmailAddress", "PasswordLastSet", "msDS-UserPasswordExpiryTimeComputed" | Where-Object { $_.Enabled -eq $true } | Select-Object SamAccountName, DisplayName, EmailAddress, @{Name='PasswordLastSet';Expression={[datetime]::FromFileTime($_.'PasswordLastSet')}}, @{Name='PasswordExpiryDate';Expression={[datetime]::FromFileTime($_.'msDS-UserPasswordExpiryTimeComputed')}}

# Export the results to a CSV file
$expiredAccounts | Export-Csv -Path $csvPath -NoTypeInformation

Write-Host "Expired password accounts (only active) exported to: $csvPath"
start $csvPath
