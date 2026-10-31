<#
.SYNOPSIS
    Bulk-updates AD user attributes (department, company, manager, office, address) from an Excel sheet.
.DESCRIPTION
    Reads an .xlsx with SamAccountName + UserPrincipalName (both must match the AD object) and the
    optional columns NewDepartment, Company, Manager, Office, StreetAddress, City, State, PostalCode,
    Country. Managers are resolved with a 6-step search (SamAccountName, UPN, DisplayName, Name,
    first/last name, wildcard), interactively confirmed if requested, and cached in a JSON file.
    Writes a log and prints a summary.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory + ImportExcel modules | write permission on user attributes
    Impact      : Modifies AD (Set-ADUser on listed users)
    License     : MIT
.EXAMPLE
    .\Update-ADUsersFromExcel.ps1
#>

<#
.SYNOPSIS
    Met à jour les attributs Active Directory des utilisateurs à partir d'un fichier Excel
.DESCRIPTION
    Ce script lit un fichier Excel contenant les informations des utilisateurs et met à jour
    leurs attributs dans Active Directory en se basant sur SamAccountName et UserPrincipalName
.NOTES
    Prérequis: Module ImportExcel et ActiveDirectory
#>

# Importer les modules nécessaires
Import-Module ActiveDirectory
Import-Module ImportExcel

# ---- EDIT ME ------------------------------------------------------------
$ExcelFilePath    = "C:\Scripts\Input\UsersUpdate.xlsx"
$LogFilePath      = "C:\Scripts\Logs\AD_Update_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$ManagerCachePath = "C:\Scripts\Logs\Manager_Cache.json"
# -------------------------------------------------------------------------

# Cache pour les managers trouvés (évite de rechercher plusieurs fois)
$script:managerCache = @{}

# Charger le cache existant si disponible
if (Test-Path $ManagerCachePath) {
    try {
        $script:managerCache = Get-Content $ManagerCachePath -Raw | ConvertFrom-Json -AsHashtable
        Write-Host "Cache de managers chargé: $($script:managerCache.Count) entrées" -ForegroundColor Cyan
    } catch {
        $script:managerCache = @{}
    }
}

# Fonction de logging
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage }
    }

    Add-Content -Path $LogFilePath -Value $logMessage
}

# Fonction de recherche interactive de manager
function Search-ADManager {
    param(
        [string]$SearchTerm,
        [switch]$Interactive
    )

    if ([string]::IsNullOrWhiteSpace($SearchTerm)) {
        return $null
    }

    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Recherche de manager: $SearchTerm" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

    $foundManagers = @()

    # Méthode 1: Recherche par SamAccountName
    Write-Host "→ Tentative 1: Recherche par SamAccountName..." -ForegroundColor Gray
    try {
        $manager = Get-ADUser -Identity $SearchTerm -Properties DisplayName, UserPrincipalName, Title, Department -ErrorAction Stop
        $foundManagers += $manager
        Write-Host "  [OK] Trouvé par SamAccountName" -ForegroundColor Green
    } catch {
        Write-Host "  [X] Non trouvé" -ForegroundColor DarkGray
    }

    # Méthode 2: Recherche par UserPrincipalName (email)
    if ($foundManagers.Count -eq 0) {
        Write-Host "→ Tentative 2: Recherche par Email/UPN..." -ForegroundColor Gray
        try {
            $manager = Get-ADUser -Filter "UserPrincipalName -eq '$SearchTerm'" -Properties DisplayName, UserPrincipalName, Title, Department -ErrorAction Stop
            if ($manager) {
                $foundManagers += $manager
                Write-Host "  [OK] Trouvé par Email" -ForegroundColor Green
            } else {
                Write-Host "  [X] Non trouvé" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "  [X] Non trouvé" -ForegroundColor DarkGray
        }
    }

    # Méthode 3: Recherche par DisplayName
    if ($foundManagers.Count -eq 0) {
        Write-Host "→ Tentative 3: Recherche par DisplayName..." -ForegroundColor Gray
        try {
            $managers = Get-ADUser -Filter "DisplayName -eq '$SearchTerm'" -Properties DisplayName, UserPrincipalName, Title, Department -ErrorAction Stop
            if ($managers) {
                $foundManagers += $managers
                Write-Host "  [OK] Trouvé $(@($managers).Count) résultat(s)" -ForegroundColor Green
            } else {
                Write-Host "  [X] Non trouvé" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "  [X] Non trouvé" -ForegroundColor DarkGray
        }
    }

    # Méthode 4: Recherche par Name
    if ($foundManagers.Count -eq 0) {
        Write-Host "→ Tentative 4: Recherche par Name..." -ForegroundColor Gray
        try {
            $managers = Get-ADUser -Filter "Name -eq '$SearchTerm'" -Properties DisplayName, UserPrincipalName, Title, Department -ErrorAction Stop
            if ($managers) {
                $foundManagers += $managers
                Write-Host "  [OK] Trouvé $(@($managers).Count) résultat(s)" -ForegroundColor Green
            } else {
                Write-Host "  [X] Non trouvé" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "  [X] Non trouvé" -ForegroundColor DarkGray
        }
    }

    # Méthode 5: Recherche par Prénom Nom
    if ($foundManagers.Count -eq 0 -and $SearchTerm -match '\s') {
        Write-Host "→ Tentative 5: Recherche par Prénom/Nom..." -ForegroundColor Gray

        # Enlever les accents pour la recherche
        $searchTermNoAccent = $SearchTerm
        $searchTermNoAccent = $searchTermNoAccent -replace 'é|è|ê|ë', 'e'
        $searchTermNoAccent = $searchTermNoAccent -replace 'à|â|ä', 'a'
        $searchTermNoAccent = $searchTermNoAccent -replace 'ô|ö', 'o'
        $searchTermNoAccent = $searchTermNoAccent -replace 'î|ï', 'i'
        $searchTermNoAccent = $searchTermNoAccent -replace 'ù|û|ü', 'u'
        $searchTermNoAccent = $searchTermNoAccent -replace 'ç', 'c'

        $parts = $searchTermNoAccent.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)

        if ($parts.Count -ge 2) {
            $firstName = $parts[0]
            $lastName = $parts[-1]

            try {
                # Recherche avec wildcard pour gérer les différentes formes de noms
                $filter = "((GivenName -like '$firstName*') -and (Surname -like '$lastName*')) -or ((GivenName -like '$lastName*') -and (Surname -like '$firstName*'))"
                $managers = Get-ADUser -Filter $filter -Properties DisplayName, UserPrincipalName, Title, Department, GivenName, Surname -ErrorAction Stop

                if ($managers) {
                    $foundManagers += $managers
                    Write-Host "  [OK] Trouvé $(@($managers).Count) résultat(s) par Prénom/Nom" -ForegroundColor Green
                } else {
                    Write-Host "  [X] Non trouvé" -ForegroundColor DarkGray
                }
            } catch {
                Write-Host "  [X] Erreur de recherche" -ForegroundColor DarkGray
            }
        }
    }

    # Méthode 6: Recherche approximative (wildcard)
    if ($foundManagers.Count -eq 0) {
        Write-Host "→ Tentative 6: Recherche approximative (wildcard)..." -ForegroundColor Gray
        try {
            $searchTermClean = $SearchTerm -replace '-', '' -replace '\.', '' -replace '\s+', '*'
            $managers = Get-ADUser -Filter "Name -like '*$searchTermClean*' -or DisplayName -like '*$searchTermClean*'" -Properties DisplayName, UserPrincipalName, Title, Department -ErrorAction Stop

            if ($managers) {
                $foundManagers += $managers
                Write-Host "  [OK] Trouvé $(@($managers).Count) résultat(s) approximatifs" -ForegroundColor Green
            } else {
                Write-Host "  [X] Non trouvé" -ForegroundColor DarkGray
            }
        } catch {
            Write-Host "  [X] Non trouvé" -ForegroundColor DarkGray
        }
    }

    # Traiter les résultats
    if ($foundManagers.Count -eq 0) {
        Write-Host ""
        Write-Host "[X] Aucun manager trouvé pour: $SearchTerm" -ForegroundColor Red
        Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

        if ($Interactive) {
            Write-Host ""
            $manualSearch = Read-Host "Voulez-vous faire une recherche manuelle? (O/N)"
            if ($manualSearch -eq 'O' -or $manualSearch -eq 'o') {
                $newSearch = Read-Host "Entrez un autre terme de recherche (SamAccountName, Email, ou Nom)"
                if (![string]::IsNullOrWhiteSpace($newSearch)) {
                    return Search-ADManager -SearchTerm $newSearch -Interactive
                }
            }

            $skipOption = Read-Host "Voulez-vous ignorer ce manager? (O/N)"
            if ($skipOption -eq 'O' -or $skipOption -eq 'o') {
                return "SKIP"
            }
        }

        return $null
    }

    # Si un seul résultat trouvé
    if ($foundManagers.Count -eq 1) {
        $manager = $foundManagers[0]
        Write-Host ""
        Write-Host "[OK] Manager trouvé:" -ForegroundColor Green
        Write-Host "  Nom complet  : $($manager.DisplayName)" -ForegroundColor White
        Write-Host "  Email        : $($manager.UserPrincipalName)" -ForegroundColor White
        Write-Host "  SamAccount   : $($manager.SamAccountName)" -ForegroundColor White
        Write-Host "  Titre        : $($manager.Title)" -ForegroundColor Gray
        Write-Host "  Département  : $($manager.Department)" -ForegroundColor Gray
        Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

        if ($Interactive) {
            $confirm = Read-Host "Est-ce le bon manager? (O/N)"
            if ($confirm -eq 'N' -or $confirm -eq 'n') {
                $newSearch = Read-Host "Entrez un autre terme de recherche"
                if (![string]::IsNullOrWhiteSpace($newSearch)) {
                    return Search-ADManager -SearchTerm $newSearch -Interactive
                }
                return $null
            }
        }

        return $manager.DistinguishedName
    }

    # Plusieurs résultats trouvés
    Write-Host ""
    Write-Host "[!] Plusieurs managers trouvés ($($foundManagers.Count) résultats):" -ForegroundColor Yellow
    Write-Host ""

    for ($i = 0; $i -lt $foundManagers.Count; $i++) {
        $mgr = $foundManagers[$i]
        Write-Host "[$($i + 1)] $($mgr.DisplayName)" -ForegroundColor White
        Write-Host "    Email: $($mgr.UserPrincipalName)" -ForegroundColor Gray
        Write-Host "    Sam  : $($mgr.SamAccountName)" -ForegroundColor Gray
        Write-Host "    Titre: $($mgr.Title)" -ForegroundColor Gray
        Write-Host ""
    }

    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan

    if ($Interactive) {
        $selection = Read-Host "Sélectionnez le numéro du bon manager (1-$($foundManagers.Count)), ou 0 pour ignorer"

        if ($selection -match '^\d+$') {
            $index = [int]$selection - 1
            if ($index -ge 0 -and $index -lt $foundManagers.Count) {
                $selectedManager = $foundManagers[$index]
                Write-Host "[OK] Manager sélectionné: $($selectedManager.DisplayName)" -ForegroundColor Green
                return $selectedManager.DistinguishedName
            }
            elseif ($selection -eq '0') {
                return "SKIP"
            }
        }

        Write-Host "Sélection invalide" -ForegroundColor Red
        return $null
    } else {
        # Mode non-interactif: prendre le premier
        Write-Log "Mode automatique: Sélection du premier résultat" -Level "WARNING"
        return $foundManagers[0].DistinguishedName
    }
}

# Fonction pour trouver un manager (avec cache)
function Find-ADManager {
    param(
        [string]$ManagerIdentifier,
        [switch]$Interactive
    )

    if ([string]::IsNullOrWhiteSpace($ManagerIdentifier)) {
        return $null
    }

    # Vérifier le cache
    if ($script:managerCache.ContainsKey($ManagerIdentifier)) {
        $cachedValue = $script:managerCache[$ManagerIdentifier]
        if ($cachedValue -eq "SKIP") {
            Write-Log "    [i] Manager '$ManagerIdentifier' marqué comme ignoré (cache)" -Level "INFO"
            return "SKIP"
        }
        Write-Log "    [OK] Manager trouvé dans le cache: $ManagerIdentifier" -Level "INFO"
        return $cachedValue
    }

    # Rechercher le manager
    $managerDN = Search-ADManager -SearchTerm $ManagerIdentifier -Interactive:$Interactive

    # Sauvegarder dans le cache
    if ($managerDN) {
        $script:managerCache[$ManagerIdentifier] = $managerDN

        # Sauvegarder le cache sur disque
        try {
            $script:managerCache | ConvertTo-Json | Set-Content -Path $ManagerCachePath -Force
        } catch {
            Write-Log "Erreur lors de la sauvegarde du cache" -Level "WARNING"
        }
    }

    return $managerDN
}

# Vérifier si le fichier Excel existe
if (-not (Test-Path $ExcelFilePath)) {
    Write-Log "Erreur: Le fichier Excel n'existe pas: $ExcelFilePath" -Level "ERROR"
    exit
}

# Vérifier si le module ImportExcel est installé
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Log "Installation du module ImportExcel..." -Level "WARNING"
    Install-Module -Name ImportExcel -Force -Scope CurrentUser
    Import-Module ImportExcel
}

Write-Log "Début du traitement - Lecture du fichier Excel: $ExcelFilePath"
Write-Host ""
$interactiveMode = Read-Host "Mode interactif pour la recherche de managers? (O/N) [Recommandé: O]"
$useInteractive = ($interactiveMode -eq 'O' -or $interactiveMode -eq 'o')

try {
    # Lire le fichier Excel
    $users = Import-Excel -Path $ExcelFilePath

    Write-Log "Nombre d'utilisateurs à traiter: $($users.Count)"

    # Compteurs
    $successCount = 0
    $errorCount = 0
    $notFoundCount = 0
    $mismatchCount = 0
    $managerNotFoundCount = 0
    $managerSkippedCount = 0

    # Parcourir chaque utilisateur
    foreach ($user in $users) {
        $samAccountName = $user.SamAccountName
        $upnFromExcel = $user.UserPrincipalName

        Write-Log "================================================"
        Write-Log "Traitement de l'utilisateur: $samAccountName / $upnFromExcel"

        # Vérifier que les deux identifiants sont présents
        if ([string]::IsNullOrWhiteSpace($samAccountName) -or [string]::IsNullOrWhiteSpace($upnFromExcel)) {
            Write-Log "[X] Identifiants manquants - SamAccountName: '$samAccountName', UPN: '$upnFromExcel'" -Level "ERROR"
            $errorCount++
            continue
        }

        try {
            # Chercher l'utilisateur dans AD par SamAccountName
            $adUser = Get-ADUser -Identity $samAccountName -Properties UserPrincipalName -ErrorAction Stop

            if ($adUser) {
                # Vérifier que l'UPN correspond
                if ($adUser.UserPrincipalName -eq $upnFromExcel) {
                    Write-Log "[OK] Utilisateur trouvé et validé dans AD"

                    # Préparer les paramètres à mettre à jour
                    $updateParams = @{
                        Identity = $samAccountName
                    }

                    $hasUpdates = $false

                    # Mapper les colonnes Excel aux attributs AD
                    if ($user.NewDepartment) {
                        $updateParams.Department = $user.NewDepartment
                        Write-Log "  → Department: $($user.NewDepartment)"
                        $hasUpdates = $true
                    }
                    if ($user.Company) {
                        $updateParams.Company = $user.Company
                        Write-Log "  → Company: $($user.Company)"
                        $hasUpdates = $true
                    }
                    if ($user.Manager) {
                        Write-Log "  → Recherche du Manager: $($user.Manager)"
                        $managerDN = Find-ADManager -ManagerIdentifier $user.Manager -Interactive:$useInteractive

                        if ($managerDN -and $managerDN -ne "SKIP") {
                            $updateParams.Manager = $managerDN
                            $hasUpdates = $true
                        } elseif ($managerDN -eq "SKIP") {
                            Write-Log "    [i] Manager ignoré par l'utilisateur" -Level "INFO"
                            $managerSkippedCount++
                        } else {
                            $managerNotFoundCount++
                        }
                    }
                    if ($user.Office) {
                        $updateParams.Office = $user.Office
                        Write-Log "  → Office: $($user.Office)"
                        $hasUpdates = $true
                    }
                    if ($user.StreetAddress) {
                        $updateParams.StreetAddress = $user.StreetAddress
                        Write-Log "  → StreetAddress: $($user.StreetAddress)"
                        $hasUpdates = $true
                    }
                    if ($user.City) {
                        $updateParams.City = $user.City
                        Write-Log "  → City: $($user.City)"
                        $hasUpdates = $true
                    }
                    if ($user.State) {
                        $updateParams.State = $user.State
                        Write-Log "  → State: $($user.State)"
                        $hasUpdates = $true
                    }
                    if ($user.PostalCode) {
                        $updateParams.PostalCode = $user.PostalCode
                        Write-Log "  → PostalCode: $($user.PostalCode)"
                        $hasUpdates = $true
                    }
                    if ($user.Country) {
                        $updateParams.Country = $user.Country
                        Write-Log "  → Country: $($user.Country)"
                        $hasUpdates = $true
                    }

                    # Mettre à jour l'utilisateur dans AD
                    if ($hasUpdates) {
                        Set-ADUser @updateParams -ErrorAction Stop
                        Write-Log "[OK] Utilisateur mis à jour avec succès: $samAccountName" -Level "SUCCESS"
                        $successCount++
                    } else {
                        Write-Log "[i] Aucune mise à jour nécessaire pour: $samAccountName" -Level "INFO"
                    }

                } else {
                    Write-Log "[X] ERREUR DE VALIDATION: L'UPN ne correspond pas!" -Level "ERROR"
                    Write-Log "  Excel UPN: $upnFromExcel" -Level "ERROR"
                    Write-Log "  AD UPN: $($adUser.UserPrincipalName)" -Level "ERROR"
                    $mismatchCount++
                }
            }
        }
        catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
            Write-Log "[X] Utilisateur non trouvé dans AD: $samAccountName" -Level "ERROR"
            $notFoundCount++
        }
        catch {
            Write-Log "[X] Erreur lors de la mise à jour de $samAccountName : $($_.Exception.Message)" -Level "ERROR"
            $errorCount++
        }
    }

    # Résumé
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "               RÉSUMÉ DU TRAITEMENT" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "Total d'utilisateurs traités:    $($users.Count)"
    Write-Host "Mises à jour réussies:           $successCount" -ForegroundColor Green
    Write-Host "Utilisateurs non trouvés:        $notFoundCount" -ForegroundColor Red
    Write-Host "Erreurs de validation UPN:       $mismatchCount" -ForegroundColor Red
    Write-Host "Managers non trouvés:            $managerNotFoundCount" -ForegroundColor Yellow
    Write-Host "Managers ignorés:                $managerSkippedCount" -ForegroundColor Gray
    Write-Host "Autres erreurs:                  $errorCount" -ForegroundColor Red
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "Log sauvegardé dans: $LogFilePath" -ForegroundColor Cyan
    Write-Host "Cache managers dans: $ManagerCachePath" -ForegroundColor Cyan

}
catch {
    Write-Log "Erreur critique lors de la lecture du fichier Excel: $($_.Exception.Message)" -Level "ERROR"
}

Write-Log "Fin du traitement"
