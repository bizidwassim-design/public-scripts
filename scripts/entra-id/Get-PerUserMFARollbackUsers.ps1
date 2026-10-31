<#
.SYNOPSIS
    Look up each user from the enforced-MFA rollback list and display the MSOL user object.
.DESCRIPTION
    Reads the UPN list produced by Get-PerUserMFAStatus.ps1 (users that had per-user MFA enforced),
    runs Get-MsolUser for each and prints the result. Step C (rollback preparation) of the per-user
    MFA to Conditional Access migration: use it to verify the accounts before re-enabling MFA on them.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : MSOnline (deprecated - consider migrating to Microsoft.Graph)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-PerUserMFARollbackUsers.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$EnforcedList = "C:\Scripts\Reports\enforcedMFA.TXT"
# -------------------------------------------------------------------------

# Read the content of the text file

$emailList = Get-Content -Path $EnforcedList

# Loop through each email address and run Get-MsolUser

foreach ($email in $emailList) {

    # Trim any leading or trailing whitespaces

    $email = $email.Trim()

    # Display the current email address being processed

    Write-Host "Processing email address: $email"

    # Run Get-MsolUser for the current email address

    try {

        $user = Get-MsolUser -UserPrincipalName $email -ErrorAction Stop

        Write-Host "User found:"

        $user

        Write-Host "------------------------"

    } catch {

        Write-Host "Error: $_"

        Write-Host "------------------------"

    }

}
