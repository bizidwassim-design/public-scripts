<#
.SYNOPSIS
    Add the CyberSecurityTraining tag (extensionAttribute1) to a list of eligible AD users.
.DESCRIPTION
    Reads display names from a text file, resolves each user, and sets extensionAttribute1 =
    CyberSecurityTraining when the account is enabled and NOT already tagged as AdminAccount (ea4),
    UserDontUseEmails (ea7), Generic (ea12), Consultant (ea13) or ServiceAccount (ea15).
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | write permission on user extensionAttributes
    Impact      : Modifies AD (sets extensionAttribute1 on eligible users)
    License     : MIT
.EXAMPLE
    .\Set-CyberSecurityTrainingTag.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Define the path to your input text file (one Display Name per line)
$inputFilePath = "C:\Scripts\input.txt"
# Optional: the loop stops when this UPN is reached (leave empty to process the whole list)
$StopAtUpn     = ""
# -------------------------------------------------------------------------

# Read the list of Display Names from the input file
$displayNames = Get-Content $inputFilePath

# Initialize an array to store the results
$results = @()

# Loop through each Display Name and retrieve the corresponding UPN
foreach ($displayName in $displayNames) {

    # Use the Get-ADUser cmdlet to retrieve the UPN based on Display Name
    $user = Get-ADUser -Filter {DisplayName -eq $displayName} -Properties UserPrincipalName

if($StopAtUpn -and $user.UserPrincipalName -like $StopAtUpn){break}

	$Eligible = $true

$CyberSecurityTraining = (Get-ADUser -Filter 'UserPrincipalName -like $user.UserPrincipalName' -Properties extensionAttribute1 |select extensionAttribute1).extensionAttribute1
$AdminAccount = (Get-ADUser -Filter 'UserPrincipalName -like $user.UserPrincipalName' -Properties extensionAttribute4 |select extensionAttribute4).extensionAttribute4
$UserDontUseEmails = (Get-ADUser -Filter 'UserPrincipalName -like $user.UserPrincipalName' -Properties extensionAttribute7 |select extensionAttribute7).extensionAttribute7
$Generic = (Get-ADUser -Filter 'UserPrincipalName -like $user.UserPrincipalName' -Properties extensionAttribute12 |select extensionAttribute12).extensionAttribute12
$Consultant = (Get-ADUser -Filter 'UserPrincipalName -like $user.UserPrincipalName' -Properties extensionAttribute13 |select extensionAttribute13).extensionAttribute13

$ServiceAccount = (Get-ADUser -Filter 'UserPrincipalName -like $user.UserPrincipalName' -Properties extensionAttribute15 |select extensionAttribute15).extensionAttribute15


if ($CyberSecurityTraining -like "CyberSecurityTraining"){$Eligible = $false}
if ($AdminAccount -like "AdminAccount"){$Eligible = $false}
if ($UserDontUseEmails -like "UserDontUseEmails"){$Eligible = $false}
if ($Generic -like "Generic"){$Eligible = $false}
if ($Consultant -like "Consultant"){$Eligible = $false}

if ($ServiceAccount -like "ServiceAccount"){$Eligible = $false}



if ($Eligible -and $user.Enabled){

Write-Host $displayName " is " $Eligible -ForegroundColor green
				$ThisUser = Get-ADUser -Filter 'UserPrincipalName -like $user.UserPrincipalName' -Properties extensionAttribute1
			Set-ADUser -Identity $ThisUser -add @{"extensionattribute1"="CyberSecurityTraining"}
			}

}
