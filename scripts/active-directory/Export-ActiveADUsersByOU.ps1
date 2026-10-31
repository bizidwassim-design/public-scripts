<#
.SYNOPSIS
    Counts and exports enabled AD users per site OU, excluding admin/disabled/external OUs.
.DESCRIPTION
    Reads enabled users under a base OU, excludes any user whose DN contains one of the excluded
    OU names, derives the site-level OU from the DN, resolves manager names, prints statistics
    (per site OU, top departments, extensionAttribute8 usage) and exports a CSV with the OU path,
    department, title, manager and extensionAttribute8 of each user.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module (RSAT)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Export-ActiveADUsersByOU.ps1
#>

<#
.SYNOPSIS
    Compte et exporte les utilisateurs ACTIFS depuis Corporate

.DESCRIPTION
    Base: OU=Corporate,OU=Users,DC=corp,DC=contoso,DC=local
    Exclut: Admins, Disabled*, External
    Export: SamAccountName, OU Parent, Chemin Complet, extensionAttribute8
#>

Import-Module ActiveDirectory -ErrorAction Stop

# ---- EDIT ME ------------------------------------------------------------
$SearchBase     = "OU=Corporate,OU=Users,DC=corp,DC=contoso,DC=local"
$SearchBaseText = "corp.contoso.local/Users/Corporate"      # affichage seulement
# OUs à exclure (le nom d'OU, à n'importe quel niveau sous la base)
$ExcludeOUNames = @(
    "Admins",
    "Disabled",
    "Disabled-Consultants",
    "Disabled-Terminated Employees",
    "External"
)
# OUs de site attendues (affichage seulement)
$IncludedOUs = @("Site-A","Site-B","Site-C","IT")
$csvPath     = ".\ActiveUsers_Corporate_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
# -------------------------------------------------------------------------

Write-Host @"
╔═══════════════════════════════════════════════════════════════════╗
║  Export Utilisateurs ACTIFS - OU Corporate                       ║
╚═══════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host "`nBase de recherche:" -ForegroundColor Yellow
Write-Host "  $SearchBase" -ForegroundColor White

Write-Host "`nOUs exclues:" -ForegroundColor Yellow
foreach ($ouName in $ExcludeOUNames) {
    Write-Host "  X $ouName" -ForegroundColor Red
}

# ============================================================================
# VÉRIFICATION DE L'OU
# ============================================================================

Write-Host "`n[1/4] Vérification de l'OU Corporate..." -ForegroundColor Cyan

try {
    $CorporateOU = Get-ADOrganizationalUnit -Identity $SearchBase -ErrorAction Stop
    Write-Host "[OK] OU Corporate trouvée: $($CorporateOU.Name)" -ForegroundColor Green
} catch {
    Write-Host "[ERREUR] L'OU Corporate n'existe pas ou n'est pas accessible!" -ForegroundColor Red
    Write-Host "Vérifiez le chemin: $SearchBase" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# RÉCUPÉRATION DES UTILISATEURS ACTIFS
# ============================================================================

Write-Host "`n[2/4] Récupération des utilisateurs ACTIFS..." -ForegroundColor Cyan

$AllActiveUsers = Get-ADUser -Filter {Enabled -eq $true} `
                             -SearchBase $SearchBase `
                             -SearchScope Subtree `
                             -Properties DistinguishedName, CanonicalName, whenCreated, `
                                         Department, Title, Manager, EmailAddress, `
                                         extensionAttribute8

Write-Host "[OK] $($AllActiveUsers.Count) utilisateurs actifs trouvés (avant exclusion)" -ForegroundColor Green

# ============================================================================
# EXCLUSION DES OUs
# ============================================================================

Write-Host "`n[3/4] Exclusion des OUs spécifiées..." -ForegroundColor Cyan

$FilteredUsers = $AllActiveUsers | Where-Object {
    $dn = $_.DistinguishedName
    $isExcluded = $false

    foreach ($ouName in $ExcludeOUNames) {
        if ($dn -like "*OU=$ouName,*") {
            $isExcluded = $true
            break
        }
    }

    -not $isExcluded
}

$ExcludedCount = $AllActiveUsers.Count - $FilteredUsers.Count

Write-Host "[OK] $($FilteredUsers.Count) utilisateurs INCLUS (comptabilisés)" -ForegroundColor Green
Write-Host "[INFO] $ExcludedCount utilisateurs exclus (Admins/Disabled*/External)" -ForegroundColor Yellow

if ($FilteredUsers.Count -eq 0) {
    Write-Host "`n[ATTENTION] Aucun utilisateur actif trouvé après exclusion!" -ForegroundColor Red
    Write-Host "Vérifiez que des utilisateurs existent dans Corporate (hors OUs exclues)" -ForegroundColor Yellow
    exit 0
}

# ============================================================================
# PRÉPARATION DES DONNÉES
# ============================================================================

Write-Host "`n[4/4] Préparation des données..." -ForegroundColor Cyan

$Results = $FilteredUsers | ForEach-Object {
    $ouComplet = ($_.DistinguishedName -split ',', 2)[1]
    $ouParent  = ($ouComplet -split ',')[0] -replace '^OU=', '' -replace '^CN=', ''
    $pathParts = $_.CanonicalName -split '/'
    $cheminOU  = $pathParts[0..($pathParts.Count - 2)] -join '/'

    $ouPrincipale = ""
    if ($ouComplet -match 'OU=([^,]+),OU=Corporate') {
        $ouPrincipale = $matches[1]
    }

    $managerName = ""
    if ($_.Manager) {
        try {
            $managerObj  = Get-ADUser $_.Manager -Properties DisplayName -ErrorAction SilentlyContinue
            $managerName = $managerObj.DisplayName
        } catch {
            $managerName = $_.Manager
        }
    }

    [PSCustomObject]@{
        SamAccountName      = $_.SamAccountName
        Nom                 = $_.Name
        Email               = if ($_.EmailAddress) { $_.EmailAddress } else { "" }
        OUPrincipale        = $ouPrincipale
        OUParentDirect      = $ouParent
        CheminOUComplet     = $cheminOU
        Department          = $_.Department
        Title               = $_.Title
        Manager             = $managerName
        ExtensionAttribute8 = if ($_.extensionAttribute8) { $_.extensionAttribute8 } else { "" }
        DateCreation        = $_.whenCreated
        DistinguishedNameOU = $ouComplet
    }
}

# ============================================================================
# STATISTIQUES PAR OU PRINCIPALE
# ============================================================================

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  STATISTIQUES PAR OU PRINCIPALE                                  ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$StatsByOU = $Results |
             Where-Object { -not [string]::IsNullOrEmpty($_.OUPrincipale) } |
             Group-Object -Property OUPrincipale |
             Sort-Object Count -Descending |
             Select-Object @{N='OU';E={$_.Name}},
                           @{N='Utilisateurs Actifs';E={$_.Count}}

$StatsByOU | Format-Table -AutoSize

# ============================================================================
# RÉSUMÉ TOTAL
# ============================================================================

Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  COMPTAGE FINAL                                                  ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Green

Write-Host "`nBase de recherche :" -ForegroundColor White
Write-Host "  $SearchBaseText" -ForegroundColor Cyan

Write-Host "`nUtilisateurs actifs TOTAUX (Corporate)     : " -NoNewline
Write-Host "$($AllActiveUsers.Count)" -ForegroundColor Yellow

Write-Host "Utilisateurs dans Admins/Disabled/External : " -NoNewline
Write-Host "-$ExcludedCount" -ForegroundColor Red

Write-Host "`n" + ("=" * 69) -ForegroundColor Green
Write-Host "UTILISATEURS ACTIFS COMPTABILISES          : " -NoNewline
Write-Host "$($FilteredUsers.Count)" -ForegroundColor Green -NoNewline
Write-Host " (production)" -ForegroundColor Gray
Write-Host ("=" * 69) -ForegroundColor Green

# ============================================================================
# TOP DÉPARTEMENTS
# ============================================================================

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║  TOP 10 DÉPARTEMENTS                                             ║" -ForegroundColor Magenta
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Magenta

$TopDepts = $Results |
            Where-Object { -not [string]::IsNullOrEmpty($_.Department) } |
            Group-Object -Property Department |
            Sort-Object Count -Descending |
            Select-Object -First 10 @{N='Département';E={$_.Name}}, @{N='Utilisateurs';E={$_.Count}}

if ($TopDepts.Count -gt 0) {
    $TopDepts | Format-Table -AutoSize
} else {
    Write-Host "  Aucun département défini" -ForegroundColor Gray
}

# ============================================================================
# STATISTIQUES extensionAttribute8
# ============================================================================

Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  STATISTIQUES extensionAttribute8                                ║" -ForegroundColor Yellow
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Yellow

$WithAttr8    = $Results | Where-Object { -not [string]::IsNullOrEmpty($_.ExtensionAttribute8) }
$WithoutAttr8 = $Results | Where-Object {        [string]::IsNullOrEmpty($_.ExtensionAttribute8) }

Write-Host "  Avec    extensionAttribute8 : $($WithAttr8.Count)" -ForegroundColor Green
Write-Host "  Sans    extensionAttribute8 : $($WithoutAttr8.Count)" -ForegroundColor Gray

if ($WithAttr8.Count -gt 0) {
    Write-Host "`n  Valeurs distinctes:" -ForegroundColor White
    $WithAttr8 | Group-Object ExtensionAttribute8 | Sort-Object Count -Descending |
        ForEach-Object { Write-Host "    $($_.Name) : $($_.Count) usagers" -ForegroundColor Cyan }
}

# ============================================================================
# EXPORT CSV
# ============================================================================

$Results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  EXPORT RÉUSSI                                                   ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

Write-Host "Fichier CSV           : " -NoNewline
Write-Host "$csvPath" -ForegroundColor Cyan

Write-Host "Utilisateurs exportés : " -NoNewline
Write-Host "$($FilteredUsers.Count)" -ForegroundColor Green

Write-Host "Taille du fichier     : " -NoNewline
$fileSize = (Get-Item $csvPath).Length
Write-Host "$([math]::Round($fileSize/1KB, 2)) KB" -ForegroundColor White

# ============================================================================
# APERÇU DES DONNÉES
# ============================================================================

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║  APERÇU (10 premiers utilisateurs)                               ║" -ForegroundColor Yellow
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Yellow

$Results |
    Select-Object SamAccountName, Nom, Email, OUPrincipale, Department, ExtensionAttribute8 -First 10 |
    Format-Table -AutoSize

if ($Results.Count -gt 10) {
    Write-Host "... et $($Results.Count - 10) autres utilisateurs`n" -ForegroundColor Gray
}

# ============================================================================
# STRUCTURE DU CSV
# ============================================================================

Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  COLONNES DU FICHIER CSV                                         ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

Write-Host "1.  SamAccountName       - Nom du compte utilisateur" -ForegroundColor White
Write-Host "2.  Nom                  - Nom complet de l'utilisateur" -ForegroundColor White
Write-Host "3.  Email                - Adresse courriel" -ForegroundColor White
Write-Host "4.  OUPrincipale         - OU principale (Site-A, Site-B, etc.)" -ForegroundColor White
Write-Host "5.  OUParentDirect       - OU parent immédiat" -ForegroundColor White
Write-Host "6.  CheminOUComplet      - Chemin OU complet lisible" -ForegroundColor White
Write-Host "7.  Department           - Département de l'utilisateur" -ForegroundColor White
Write-Host "8.  Title                - Titre du poste" -ForegroundColor White
Write-Host "9.  Manager              - Nom du gestionnaire" -ForegroundColor White
Write-Host "10. ExtensionAttribute8  - Valeur de extensionAttribute8 (AD)" -ForegroundColor Green
Write-Host "11. DateCreation         - Date de création du compte" -ForegroundColor White
Write-Host "12. DistinguishedNameOU  - Distinguished Name de l'OU" -ForegroundColor White

# ============================================================================
# OUs EXCLUES / INCLUSES
# ============================================================================

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  OUs EXCLUES DU COMPTAGE                                         ║" -ForegroundColor Red
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Red

foreach ($ouName in $ExcludeOUNames | Sort-Object) {
    Write-Host "  X $ouName" -ForegroundColor Red
}
Write-Host "`nCes OUs et toutes leurs sous-OUs ne sont PAS comptées." -ForegroundColor Gray

Write-Host "`n╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  OUs INCLUSES (COMPTÉES)                                         ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

foreach ($ouName in $IncludedOUs) {
    Write-Host "  OK $ouName" -ForegroundColor Green
}

# ============================================================================
# OUVERTURE DU FICHIER
# ============================================================================

Write-Host "`nOuvrir le fichier CSV maintenant? (O/N): " -NoNewline -ForegroundColor Cyan
$openChoice = Read-Host

if ($openChoice -eq 'O' -or $openChoice -eq 'o') {
    Start-Process $csvPath
}

Write-Host "`n═══════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "Script terminé avec succès!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════════`n" -ForegroundColor Green
