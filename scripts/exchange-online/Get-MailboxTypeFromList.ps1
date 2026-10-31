<#
.SYNOPSIS
    For a list of UPNs, reports whether each one has a user mailbox, a shared mailbox or no mailbox.
.DESCRIPTION
    Reads UserPrincipalNames (one per line) from a text file. For each UPN, fetches the Microsoft 365
    account (display name, licences, blocked state) and checks Exchange Online for a user or shared
    mailbox. Results (including "introuvable" for unknown accounts) are exported to a CSV and opened.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ExchangeOnlineManagement (Connect-ExchangeOnline) | MSOnline (Connect-MsolService, deprecated)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    Connect-ExchangeOnline; Connect-MsolService
    .\Get-MailboxTypeFromList.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Chemin du fichier texte contenant les UserPrincipalNames
$CheminFichier = "C:\Scripts\Input\upn-list.txt"
$OutputPath    = "C:\Scripts\Reports\MailboxTypes.csv"
# -------------------------------------------------------------------------

# Function to check if a mailbox is a user mailbox or a shared mailbox
function Get-MailboxType {
    param (
        [string]$UserPrincipalName
    )

    # Check if the UPN exists in user mailboxes
    $userMailbox = Get-Mailbox -Identity $UserPrincipalName -ErrorAction SilentlyContinue
    if ($userMailbox) {
        return 0
    } else {
        # Check if the UPN exists in shared mailboxes
        $sharedMailbox = Get-Mailbox -Identity $UserPrincipalName -RecipientTypeDetails SharedMailbox -ErrorAction SilentlyContinue
        if ($sharedMailbox) {
            return 1
        } else {
            # If neither user mailbox nor shared mailbox found, indicate it's not found
            return 2
        }
    }
}

# Créer un tableau vide pour stocker les détails des utilisateurs
$UserDetails = @()

# Lire les UserPrincipalNames depuis le fichier texte
$Users = Get-Content $CheminFichier

# Parcourir chaque UserPrincipalName dans la liste
foreach ($UserPrincipalName in $Users) {
    # Vérifier l'état du compte utilisateur
    $UserAccount = Get-MsolUser -UserPrincipalName $UserPrincipalName -ErrorAction SilentlyContinue

    # Vérifier si le compte est activé ou bloqué
    if ($UserAccount -ne $null) {
        # Obtenir le type de boîte aux lettres
        $mailboxtype = Get-MailboxType -UserPrincipalName $UserPrincipalName

        # Déterminer le type de boîte aux lettres
        switch ($mailboxtype) {
            0 { $type = "usermailbox" }
            1 { $type = "sharedmailbox" }
            2 { $type = "no mailbox" }
        }

        # Créer un objet personnalisé pour stocker les détails de l'utilisateur
        $UserDetail = [PSCustomObject]@{
            'UserPrincipalName' = $UserPrincipalName
            'DisplayName' = $UserAccount.DisplayName
            'Licenses' = ($UserAccount.Licenses).AccountSkuId -join ','
            'Disabled' = $UserAccount.BlockCredential
            'MailboxType' = $type
        }

        # Ajouter les détails de l'utilisateur à la liste
        $UserDetails += $UserDetail
    } else {
        # Si l'utilisateur n'est pas trouvé, ajouter des détails avec des valeurs par défaut
        $UserDetail = [PSCustomObject]@{
            'UserPrincipalName' = $UserPrincipalName
            'DisplayName' = "introuvable"
            'Licenses' = "introuvable"
            'Disabled' = "introuvable"
            'MailboxType' = "introuvable"
        }

        # Ajouter les détails de l'utilisateur à la liste
        $UserDetails += $UserDetail
    }
}

# Export user details to a CSV file
$UserDetails | Export-Csv -Path $OutputPath -NoTypeInformation

# Ouvrir le fichier CSV exporté
start $OutputPath
