<#
.SYNOPSIS
    Exports enabled AD users from one OU (excluding a sub-OU) with full identity/HR attributes to CSV.
.DESCRIPTION
    Reads enabled users under the include OU, drops those located in the exclude OU, resolves the
    manager's display name and exports name, UPN, title, department, office, address, phone,
    employee IDs, dates and password flags to a timestamped CSV on the desktop.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module (RSAT) | AD read permission
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Export-ActiveADUsers.ps1
#>

<#
.SYNOPSIS
  Exporte les utilisateurs ACTIFS d'Active Directory appartenant à une OU précise,
  en excluant une sous-OU spécifique. Inclut tous les détails utiles (nom, UPN, gestionnaire, département, etc.)
  et exporte le résultat en CSV.

.PREREQUIS
  - Module RSAT ActiveDirectory (Import-Module ActiveDirectory)
  - Droits de lecture AD
#>

Import-Module ActiveDirectory -ErrorAction Stop

# ---- EDIT ME ------------------------------------------------------------
# OU à inclure et à exclure
$includeOU = "OU=Corporate,OU=Users,DC=corp,DC=contoso,DC=local"
$excludeOU = "OU=External,OU=Corporate,OU=Users,DC=corp,DC=contoso,DC=local"
# Emplacement du CSV
$timestamp = Get-Date -Format 'yyyyMMdd_HHmm'
$csvPath   = Join-Path $env:USERPROFILE "Desktop\ActiveUsers_Corporate_$timestamp.csv"
# -------------------------------------------------------------------------

# Propriétés à récupérer
$adProps = @(
    'GivenName','Surname','DisplayName','sAMAccountName','UserPrincipalName',
    'Title','Department','Company','physicalDeliveryOfficeName',
    'StreetAddress','City','State','PostalCode','Country',
    'telephoneNumber','mobile','mail','employeeID','employeeNumber',
    'whenCreated','whenChanged','LastLogonDate','manager',
    'AccountExpirationDate','PasswordLastSet','PasswordNeverExpires','Description'
)

# Récupération des comptes actifs dans l'OU incluse
$users = Get-ADUser -Filter 'Enabled -eq $true' -SearchBase $includeOU -SearchScope Subtree -Properties $adProps

# Exclure les comptes présents dans l'OU "External"
$filteredUsers = $users | Where-Object { $_.DistinguishedName -notlike "*$($excludeOU)*" }

# Préparation des données
$export = $filteredUsers | ForEach-Object {
    $managerName = $null
    if ($_.Manager) {
        try {
            $managerName = (Get-ADUser -Identity $_.Manager -Properties DisplayName).DisplayName
        } catch {
            $managerName = $_.Manager
        }
    }

    [PSCustomObject]@{
        DisplayName           = $_.DisplayName
        FirstName             = $_.GivenName
        LastName              = $_.Surname
        SamAccountName        = $_.sAMAccountName
        UserPrincipalName     = $_.UserPrincipalName
        Title                 = $_.Title
        Department            = $_.Department
        Company               = $_.Company
        Manager               = $managerName
        Office                = $_.physicalDeliveryOfficeName
        StreetAddress         = $_.StreetAddress
        City                  = $_.City
        State                 = $_.State
        PostalCode            = $_.PostalCode
        Country               = $_.Country
        Email                 = $_.mail
        Telephone             = $_.telephoneNumber
        Mobile                = $_.mobile
        EmployeeID            = $_.employeeID
        EmployeeNumber        = $_.employeeNumber
        WhenCreated           = $_.whenCreated
        WhenChanged           = $_.whenChanged
        LastLogonDate         = $_.LastLogonDate
        Enabled               = $true
        AccountExpirationDate = $_.AccountExpirationDate
        PasswordLastSet       = $_.PasswordLastSet
        PasswordNeverExpires  = $_.PasswordNeverExpires
        Description           = $_.Description
        DistinguishedName     = $_.DistinguishedName
    }
}

# Export CSV
$export |
    Sort-Object DisplayName |
    Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "Export terminé : $($export.Count) usagers actifs -> $csvPath"
