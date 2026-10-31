<#
.SYNOPSIS
    Audit des dernières connexions Entra ID pour une liste de comptes AD (détection des comptes stale).
.DESCRIPTION
    Pour chaque SamAccountName de la liste : lit le compte AD on-prem (UPN, activation, mot de passe,
    dernier logon), retrouve l'objet Entra ID (par UPN, mail ou onPremisesSamAccountName), lit
    signInActivity (interactif / non interactif) et marque le compte inactif au-delà du seuil
    ($inactiveThresholdDays). Exporte un CSV horodaté avec une recommandation par compte et affiche
    un résumé (top 10 inactifs, comptes non synchronisés, mots de passe expirés).
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | Microsoft.Graph (User.Read.All, AuditLog.Read.All)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-StaleAccountSignIns.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$outputPath = "C:\Scripts\Reports\StaleAccountsAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$inactiveThresholdDays = 180  # 6 mois

# Liste des utilisateurs à auditer (SamAccountName)
$userList = @(
    "jdoe",
    "jsmith",
    "svc-example"
)
# -------------------------------------------------------------------------

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "  AUDIT DES COMPTES STALE" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Utilisateurs à auditer: $($userList.Count)" -ForegroundColor White
Write-Host "Seuil d'inactivité: $inactiveThresholdDays jours (6 mois)" -ForegroundColor White
Write-Host "=======================================================`n" -ForegroundColor Cyan

# Connexion à Microsoft Graph
Write-Host "[1/3] Connexion à Microsoft Graph..." -ForegroundColor Cyan
try {
    Connect-MgGraph -Scopes "User.Read.All", "AuditLog.Read.All" -NoWelcome
    Write-Host "      [OK] Connecté à Microsoft Graph" -ForegroundColor Green
} catch {
    Write-Host "      [X] Erreur de connexion à Graph: $_" -ForegroundColor Red
    exit
}

# Import du module Active Directory
Write-Host "`n[2/3] Chargement du module Active Directory..." -ForegroundColor Cyan
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "      [OK] Module AD chargé" -ForegroundColor Green
} catch {
    Write-Host "      [X] Erreur: $_" -ForegroundColor Red
    Disconnect-MgGraph | Out-Null
    exit
}

# Traitement des utilisateurs
Write-Host "`n[3/3] Analyse des comptes utilisateurs...`n" -ForegroundColor Cyan

$results = @()
$counter = 0
$totalUsers = $userList.Count
$staleCount = 0
$errorCount = 0
$notFoundInEntra = 0

foreach ($username in $userList) {
    $counter++
    $percentComplete = [math]::Round(($counter / $totalUsers) * 100, 2)
    Write-Progress -Activity "Audit des connexions" -Status "Traitement: $username ($counter/$totalUsers)" -PercentComplete $percentComplete

    try {
        # Récupération depuis AD on-prem
        $adUser = Get-ADUser -Identity $username -Properties UserPrincipalName, DisplayName, Enabled, PasswordExpired, PasswordLastSet, LastLogonDate, whenCreated, Mail -ErrorAction Stop
        $upn = $adUser.UserPrincipalName

        if ([string]::IsNullOrEmpty($upn)) {
            Write-Host "      [!] $username : Aucun UPN trouvé dans AD" -ForegroundColor Yellow
            $errorCount++

            $results += [PSCustomObject]@{
                SamAccountName = $username
                DisplayName = $adUser.DisplayName
                UserPrincipalName = "N/A"
                ADEnabled = $adUser.Enabled
                EntraEnabled = "N/A"
                EntraSyncStatus = "NO UPN"
                AccountCreated = $adUser.whenCreated
                PasswordExpired = $adUser.PasswordExpired
                PasswordLastSet = $adUser.PasswordLastSet
                LastADLogon = $adUser.LastLogonDate
                LastEntraSignIn = "N/A"
                LastNonInteractiveSignIn = "N/A"
                DaysSinceLastSignIn = $null
                IsStale = $true
                StaleReason = "Aucun UPN configuré dans AD"
                Recommendation = "Configurer UPN ou désactiver"
                Flag = "[X] NO UPN"
            }
            continue
        }

        Write-Verbose "      -> $username : UPN = $upn"

        # Recherche dans Entra ID avec plusieurs méthodes
        $entraUser = $null
        $syncStatus = "Unknown"

        try {
            # Méthode 1: Recherche par UPN avec filter
            $entraUser = Get-MgUser -Filter "userPrincipalName eq '$upn'" -Property "signInActivity,accountEnabled,displayName,userPrincipalName,onPremisesSyncEnabled" -ErrorAction Stop | Select-Object -First 1

            if ($null -eq $entraUser) {
                # Méthode 2: Recherche par Mail si disponible
                if (![string]::IsNullOrEmpty($adUser.Mail)) {
                    $entraUser = Get-MgUser -Filter "mail eq '$($adUser.Mail)'" -Property "signInActivity,accountEnabled,displayName,userPrincipalName,onPremisesSyncEnabled" -ErrorAction Stop | Select-Object -First 1
                }
            }

            if ($null -eq $entraUser) {
                # Méthode 3: Recherche par SamAccountName dans onPremisesSamAccountName
                $entraUser = Get-MgUser -Filter "onPremisesSamAccountName eq '$username'" -Property "signInActivity,accountEnabled,displayName,userPrincipalName,onPremisesSyncEnabled" -ErrorAction Stop | Select-Object -First 1
            }

            if ($null -ne $entraUser) {
                if ($entraUser.OnPremisesSyncEnabled -eq $true) {
                    $syncStatus = "Synchronized"
                } else {
                    $syncStatus = "Cloud Only"
                }
            }
        } catch {
            Write-Verbose "      ! Erreur recherche Entra: $($_.Exception.Message)"
        }

        if ($null -eq $entraUser) {
            Write-Host "      [!] $username ($upn) : Compte non trouvé dans Entra ID" -ForegroundColor Yellow
            $notFoundInEntra++

            $results += [PSCustomObject]@{
                SamAccountName = $username
                DisplayName = $adUser.DisplayName
                UserPrincipalName = $upn
                ADEnabled = $adUser.Enabled
                EntraEnabled = "N/A"
                EntraSyncStatus = "NOT IN ENTRA"
                AccountCreated = $adUser.whenCreated
                PasswordExpired = $adUser.PasswordExpired
                PasswordLastSet = $adUser.PasswordLastSet
                LastADLogon = $adUser.LastLogonDate
                LastEntraSignIn = "N/A"
                LastNonInteractiveSignIn = "N/A"
                DaysSinceLastSignIn = $null
                IsStale = $true
                StaleReason = "Compte non synchronisé vers Entra ID"
                Recommendation = "Vérifier AD Connect ou compte cloud-only manquant"
                Flag = "[X] NOT IN ENTRA"
            }
            continue
        }

        # Analyse des sign-ins Entra ID
        $lastSignIn = $null
        $lastNonInteractiveSignIn = $null
        $daysSinceLastSignIn = $null
        $isStale = $false
        $staleReason = ""
        $recommendation = ""

        if ($entraUser.SignInActivity) {
            $lastSignIn = $entraUser.SignInActivity.LastSignInDateTime
            $lastNonInteractiveSignIn = $entraUser.SignInActivity.LastNonInteractiveSignInDateTime

            # Date la plus récente
            $mostRecentSignIn = @($lastSignIn, $lastNonInteractiveSignIn) |
                Where-Object { $_ -ne $null } |
                Sort-Object -Descending |
                Select-Object -First 1

            if ($mostRecentSignIn) {
                $daysSinceLastSignIn = (New-TimeSpan -Start $mostRecentSignIn -End (Get-Date)).Days

                if ($daysSinceLastSignIn -gt $inactiveThresholdDays) {
                    $isStale = $true
                    $staleReason = "Dernière connexion: il y a $daysSinceLastSignIn jours"
                    $recommendation = "Désactiver le compte ou confirmer utilisation"
                    $staleCount++
                    Write-Host "      [!] $username : Inactif depuis $daysSinceLastSignIn jours" -ForegroundColor Yellow
                } else {
                    $recommendation = "Compte actif - RAS"
                    Write-Host "      [OK] $username : Actif ($daysSinceLastSignIn jours)" -ForegroundColor Green
                }
            } else {
                $isStale = $true
                $staleReason = "Aucune connexion enregistrée"
                $recommendation = "Vérifier si compte nécessaire"
                $staleCount++
                Write-Host "      [!] $username : Aucune connexion enregistrée" -ForegroundColor Yellow
            }
        } else {
            $isStale = $true
            $staleReason = "Données de connexion non disponibles (jamais connecté)"
            $recommendation = "Compte jamais utilisé - Considérer désactivation"
            $staleCount++
            Write-Host "      [!] $username : Jamais connecté à Entra" -ForegroundColor Yellow
        }

        # Ajout des informations sur le mot de passe expiré
        if ($adUser.PasswordExpired) {
            $staleReason += " | Mot de passe expiré"
        }

        # Création de l'objet résultat
        $result = [PSCustomObject]@{
            SamAccountName = $username
            DisplayName = $adUser.DisplayName
            UserPrincipalName = $upn
            EntraUPN = $entraUser.UserPrincipalName
            ADEnabled = $adUser.Enabled
            EntraEnabled = $entraUser.AccountEnabled
            EntraSyncStatus = $syncStatus
            AccountCreated = $adUser.whenCreated
            PasswordExpired = $adUser.PasswordExpired
            PasswordLastSet = $adUser.PasswordLastSet
            LastADLogon = $adUser.LastLogonDate
            LastEntraSignIn = $lastSignIn
            LastNonInteractiveSignIn = $lastNonInteractiveSignIn
            DaysSinceLastSignIn = $daysSinceLastSignIn
            IsStale = $isStale
            StaleReason = $staleReason
            Recommendation = $recommendation
            Flag = if ($isStale) { "[!] INACTIF" } else { "[OK] Actif" }
        }

        $results += $result

    } catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Host "      [X] $username : Compte non trouvé dans AD" -ForegroundColor Red
        $errorCount++

        $results += [PSCustomObject]@{
            SamAccountName = $username
            DisplayName = "N/A"
            UserPrincipalName = "N/A"
            EntraUPN = "N/A"
            ADEnabled = "N/A"
            EntraEnabled = "N/A"
            EntraSyncStatus = "NOT IN AD"
            AccountCreated = $null
            PasswordExpired = "N/A"
            PasswordLastSet = $null
            LastADLogon = $null
            LastEntraSignIn = "N/A"
            LastNonInteractiveSignIn = "N/A"
            DaysSinceLastSignIn = $null
            IsStale = $true
            StaleReason = "Compte non trouvé dans AD on-prem"
            Recommendation = "Vérifier existence du compte"
            Flag = "[X] NOT IN AD"
        }
    } catch {
        Write-Host "      [X] $username : Erreur - $($_.Exception.Message)" -ForegroundColor Red
        $errorCount++

        $results += [PSCustomObject]@{
            SamAccountName = $username
            DisplayName = if ($adUser) { $adUser.DisplayName } else { "N/A" }
            UserPrincipalName = if ($upn) { $upn } else { "N/A" }
            EntraUPN = "N/A"
            ADEnabled = if ($adUser) { $adUser.Enabled } else { "N/A" }
            EntraEnabled = "N/A"
            EntraSyncStatus = "ERROR"
            AccountCreated = if ($adUser) { $adUser.whenCreated } else { $null }
            PasswordExpired = if ($adUser) { $adUser.PasswordExpired } else { "N/A" }
            PasswordLastSet = if ($adUser) { $adUser.PasswordLastSet } else { $null }
            LastADLogon = if ($adUser) { $adUser.LastLogonDate } else { $null }
            LastEntraSignIn = "ERROR"
            LastNonInteractiveSignIn = "ERROR"
            DaysSinceLastSignIn = $null
            IsStale = $true
            StaleReason = "Erreur: $($_.Exception.Message)"
            Recommendation = "Vérifier manuellement"
            Flag = "[X] ERROR"
        }
    }

    # Pause pour éviter le throttling
    Start-Sleep -Milliseconds 150
}

Write-Progress -Activity "Audit des connexions" -Completed

# Export vers CSV
Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "  EXPORT DES RÉSULTATS" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

try {
    # Créer le dossier si nécessaire
    $outputDir = Split-Path -Path $outputPath
    if (!(Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
    Write-Host "[OK] Rapport exporté: $outputPath" -ForegroundColor Green
} catch {
    Write-Host "[X] Erreur d'export: $_" -ForegroundColor Red
}

# Statistiques finales
$activeAccounts = ($results | Where-Object { $_.IsStale -eq $false }).Count
$synchronizedAccounts = ($results | Where-Object { $_.EntraSyncStatus -eq "Synchronized" }).Count

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "  RÉSUMÉ DE L'AUDIT" -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Total analysé              : $totalUsers comptes" -ForegroundColor White
Write-Host "Actifs (< 6 mois)          : $activeAccounts comptes" -ForegroundColor Green
Write-Host "Inactifs (> 6 mois)        : $staleCount comptes" -ForegroundColor Yellow
Write-Host "Non synchronisés vers Entra: $notFoundInEntra comptes" -ForegroundColor Magenta
Write-Host "Synchronisés avec Entra    : $synchronizedAccounts comptes" -ForegroundColor Cyan
Write-Host "Erreurs                    : $errorCount comptes" -ForegroundColor Red
Write-Host "Seuil d'inactivité         : $inactiveThresholdDays jours" -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor Cyan

# Top 10 comptes les plus inactifs (parmi ceux trouvés dans Entra)
$entraAccounts = $results | Where-Object { $_.DaysSinceLastSignIn -ne $null }
if ($entraAccounts.Count -gt 0) {
    Write-Host "`n=======================================================" -ForegroundColor Yellow
    Write-Host "  TOP 10 COMPTES LES PLUS INACTIFS (ENTRA)" -ForegroundColor Yellow
    Write-Host "=======================================================" -ForegroundColor Yellow

    $entraAccounts |
        Sort-Object DaysSinceLastSignIn -Descending |
        Select-Object -First 10 SamAccountName, DisplayName, DaysSinceLastSignIn, LastEntraSignIn |
        Format-Table -AutoSize
}

# Comptes non synchronisés
if ($notFoundInEntra -gt 0) {
    Write-Host "`n=======================================================" -ForegroundColor Magenta
    Write-Host "  COMPTES NON SYNCHRONISÉS VERS ENTRA ID" -ForegroundColor Magenta
    Write-Host "=======================================================" -ForegroundColor Magenta

    $results |
        Where-Object { $_.EntraSyncStatus -eq "NOT IN ENTRA" } |
        Select-Object SamAccountName, DisplayName, UserPrincipalName, ADEnabled, PasswordExpired |
        Format-Table -AutoSize

    Write-Host "[!] Ces comptes existent dans AD mais pas dans Entra ID" -ForegroundColor Yellow
    Write-Host "  -> Vérifier AD Connect ou si comptes doivent être cloud-only" -ForegroundColor Yellow
}

# Comptes avec mot de passe expiré
$expiredPasswords = ($results | Where-Object { $_.PasswordExpired -eq $true }).Count
if ($expiredPasswords -gt 0) {
    Write-Host "`n[!] $expiredPasswords comptes avec mot de passe expiré détectés" -ForegroundColor Yellow
}

# Déconnexion
Disconnect-MgGraph | Out-Null
Write-Host "`n[OK] Déconnecté de Microsoft Graph" -ForegroundColor Green
Write-Host "`n=======================================================" -ForegroundColor Cyan

# Ouvrir le fichier CSV
Write-Host "`nVoulez-vous ouvrir le rapport CSV? (O/N): " -ForegroundColor Cyan -NoNewline
$response = Read-Host
if ($response -eq 'O' -or $response -eq 'o') {
    Start-Process $outputPath
}
