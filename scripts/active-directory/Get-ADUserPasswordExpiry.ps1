<#
.SYNOPSIS
    Computes and displays the password expiration date of one AD account.
.DESCRIPTION
    Reads PasswordLastSet for the given SamAccountName, adds the domain default MaxPasswordAge
    and prints the resulting expiration date. Fine-grained password policies are not taken into
    account (use msDS-UserPasswordExpiryTimeComputed for those).
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ADUserPasswordExpiry.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Specify the username of the AD account
$username = "jdoe-admin"
# -------------------------------------------------------------------------

# Get the AD user object
$user = Get-ADUser -Identity $username -Properties "PasswordLastSet", "msDS-UserPasswordExpiryTimeComputed"

# Get the maximum password age policy
$maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge

# Calculate the password expiration date
$passwordLastSet = $user.PasswordLastSet
$passwordExpirationDate = $passwordLastSet + $maxPasswordAge

# Output the password expiration date
Write-Host "Password expiration date for $($username): $passwordExpirationDate"
