<#
.SYNOPSIS
    Export the legacy per-user MFA state of every user before migrating to Conditional Access MFA.
.DESCRIPTION
    Uses MSOnline to read StrongAuthenticationRequirements for all users, exports UPN / DisplayName /
    MFAStatus (Enforced or Disabled) to CSV and writes the enforced UPNs to a text file that can be
    used as a rollback list. Step A of the per-user MFA to Conditional Access migration.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : MSOnline (deprecated - consider migrating to Microsoft.Graph)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-PerUserMFAStatus.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$OutputCsv      = "C:\Scripts\Reports\outputMFA.csv"
$EnforcedList   = "C:\Scripts\Reports\enforcedMFA.TXT"
# -------------------------------------------------------------------------

# Connect to MSOL service

Connect-MsolService



# Get MFA status for all users

$usersMFAStatus = Get-MsolUser -All | Select-Object UserPrincipalName, DisplayName, @{Name='MFAStatus'; Expression={if (($_.StrongAuthenticationRequirements.State -eq 'Enforced')-or ($_.StrongAuthenticationRequirements.State -eq 'Enabled'))  {'Enforced'} else {'Disabled'}}}



# Export the data to a CSV file

$usersMFAStatus | Export-Csv -Encoding UTF8 -NoTypeInformation -Path $OutputCsv

 foreach ($user in $usersMFAStatus)
{
if ($user.MFAStatus -eq "enforced"){ $user.UserPrincipalName >> $EnforcedList }
}

# Open the CSV file

Start-Process $OutputCsv
Start-Process $EnforcedList
