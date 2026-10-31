<#
.SYNOPSIS
    List Microsoft 365 users, their licences and blocked state, and isolate the users that own a mailbox.
.DESCRIPTION
    Uses the legacy MSOnline module to enumerate all users, split them into active vs blocked
    (BlockCredential) and flag the accounts holding a mailbox-bearing SKU (E5 / F3 / Teams Exploratory).
    Writes three CSV files (all active users, blocked users, users with mailboxes) and opens them.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : MSOnline (deprecated - consider migrating to Microsoft.Graph)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    Connect-MsolService
    .\Get-UsersWithMailboxes.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$TenantSkuPrefix        = "contoso*"              # AccountSkuId prefix of your tenant (e.g. "contoso:SPE_E5")
$OutputFolder           = "C:\Scripts\Reports\O365"
# -------------------------------------------------------------------------

#Connect-MsolService
#Connect-ExchangeOnline
# Connect-AzureAD

$UserDetailsCsv         = Join-Path $OutputFolder "UserDetails.csv"
$BlockedUserDetailsCsv  = Join-Path $OutputFolder "BlockedUserDetails.csv"
$UserWithMailBoxesCsv   = Join-Path $OutputFolder "UserWithMailBoxesE5F3TEAMS_EXPLORATORY.csv"

# Retrieve user information
$Users = Get-MsolUser -All

# Create an empty array to store user details
$UserDetails = $UserWithMailBoxes = $BlockedUserDetails = @()

# Iterate through each user
foreach ($User in $Users) {

#check if the user account is enabled or blocked
$UserAccount = Get-MsolUser -UserPrincipalName $User.UserPrincipalName

#add user information to dynamic object
    $UserDetail = [PSCustomObject]@{
        'UserPrincipalName' = $User.UserPrincipalName
        'DisplayName' = $User.DisplayName
        'Licenses' = ($User.Licenses).AccountSkuId -join ','
        'Disabled' = $UserAccount.BlockCredential
        }

 #if disabled account
if ($UserAccount.BlockCredential -eq $true -and $UserDetail.licenses -notlike $TenantSkuPrefix) {
        $BlockedUserDetail = [PSCustomObject]@{
        'UserPrincipalName' = $User.UserPrincipalName
        'DisplayName' = $User.DisplayName
        'Licenses' = ($User.Licenses).AccountSkuId -join ','
        'Disabled' = $UserAccount.BlockCredential
        }
         $BlockedUserDetails += $BlockedUserDetail

} else{ #if active account
        $UserDetails += $UserDetail

        if ($UserDetail.licenses -like "*SPE_E5*" -or $UserDetail.licenses -like "*SPE_F1*" -or $UserDetail.licenses -like "*TEAMS_EXPLORATORY*")
        {  $UserWithMailBoxes += $UserDetail
            #add user to the IDR users group as a member
            #Add-DistributionGroupMember -Identity "identity-team@contoso.com" -Member "$User.UserPrincipalName"
            #Delegate svc-idr to his mailbox
            #Add-MailboxPermission -Identity "$User.UserPrincipalName" -User "svc-idr" -AccessRights FullAccess

         #add Tag  CyberSecurityTraining for only user mail box and not generic accounts either consultant either service account
         # we have to use graph to display extended attribute cause the other command not working well
         #get-aduser -identi

         }
       }
  }


# Export user details to a CSV file
$UserDetails | Export-Csv -Path $UserDetailsCsv -NoTypeInformation
start $UserDetailsCsv

$BlockedUserDetails | Export-Csv -Path $BlockedUserDetailsCsv -NoTypeInformation
start $BlockedUserDetailsCsv

$UserWithMailBoxes| Export-Csv -Path $UserWithMailBoxesCsv -NoTypeInformation
start $UserWithMailBoxesCsv
