<#
.SYNOPSIS
    Sets the account expiration date of one AD account (default: 15 June of the current year).
.DESCRIPTION
    Builds the target date and calls Set-ADAccountExpiration on the given SamAccountName.
    Typically used for contractor / temporary accounts whose access must end on a fixed date.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Modifies AD (sets accountExpires on the user)
    License     : MIT
.EXAMPLE
    .\Set-ADAccountExpirationDate.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Specify the username of the AD account
$username = "jdoe-admin"

# Specify the new expiration date (15th June of the current year)
$newExpirationDate = Get-Date -Year (Get-Date).Year -Month 6 -Day 15
# -------------------------------------------------------------------------

# Set the new expiration date for the user account
Set-ADAccountExpiration -Identity $username -DateTime $newExpirationDate

# Output success message
Write-Host "Expiration date for $username has been set to $newExpirationDate."
