<#
.SYNOPSIS
    Tag every enabled AD account containing "admin" in its name with extensionAttribute4 = AdminAccount.
.DESCRIPTION
    Loops over enabled users, skips those already tagged as ServiceAccount (extensionAttribute15)
    and adds the AdminAccount tag to extensionAttribute4 when the SamAccountName or Name contains
    "admin". Part of the extensionAttribute-based security tagging convention.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | write permission on user objects
    Impact      : Modifies AD (sets extensionAttribute4 on matching users)
    License     : MIT
.EXAMPLE
    .\Set-AdminAccountTag.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$TagValue = "AdminAccount"
# -------------------------------------------------------------------------

$users = Get-ADUser -Filter {Enabled -eq $true} -Properties *
foreach ($user in $users){
if ($user.extensionAttribute15 -notlike "ServiceAccount") {
if ($user.SamAccountName -like "*admin*" -or $user.Name -like "*admin*" ){

 write-host "this user "$user.UserPrincipalName -ForegroundColor Yellow
 $ThisUser = Get-ADUser -Filter 'UserPrincipalName -like $user.UserPrincipalName' -Properties extensionAttribute1
 Set-ADUser -Identity $ThisUser -add @{"extensionattribute4"=$TagValue}

}
}
}
