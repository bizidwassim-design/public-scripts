<#
.SYNOPSIS
    Exports the enabled user members of every group located in a given OU to a CSV.
.DESCRIPTION
    Lists all groups of the target OU (e.g. the groups delegated to an external vendor),
    expands their membership recursively, keeps only enabled user accounts and exports
    GroupName / UserName / Email / UserPrincipalName to a CSV. Run on a domain controller
    or a host with RSAT.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Export-ADGroupMembersInOU.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Définir l'OU cible
$ou         = "OU=VendorName,OU=Security,OU=Groups,DC=corp,DC=contoso,DC=local"
$OutputPath = "C:\Scripts\Reports\VendorName_Users_by_Group.csv"
# -------------------------------------------------------------------------

# Obtenir tous les groupes dans l'OU
$groups = Get-ADGroup -Filter * -SearchBase $ou

# Initialiser une liste pour stocker les résultats
$userList = @()

foreach ($group in $groups) {
    # Obtenir les membres du groupe
    $members = Get-ADGroupMember -Identity $group -Recursive | Where-Object { $_.objectClass -eq "user" }

    foreach ($member in $members) {
        # Obtenir les détails de l'utilisateur, y compris l'état Enabled
        $user = Get-ADUser -Identity $member -Properties EmailAddress, UserPrincipalName, Enabled

        # Vérifier si l'utilisateur est actif
        if ($user.Enabled) {
            # Ajouter les informations à la liste
            $userList += [PSCustomObject]@{
                GroupName = $group.Name
                UserName = $user.Name
                Email = $user.EmailAddress
                UserPrincipalName = $user.UserPrincipalName
            }
        }
    }
}

# Exporter la liste dans un fichier CSV
$userList | Export-Csv -Path $OutputPath -NoTypeInformation
