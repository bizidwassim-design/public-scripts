<#
.SYNOPSIS
    Removes disabled user and computer objects from an AD security group (e.g. "USB Authorized").
.DESCRIPTION
    Inventories every member of the group, checks the Enabled flag of users and computers, lists
    the disabled ones, asks for confirmation, removes them from the group and writes a log file
    plus a CSV report of all members with their status and the action taken.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module (RSAT) | write permission on the group
    Impact      : Modifies AD (removes group members, after interactive confirmation)
    License     : MIT
.EXAMPLE
    .\Remove-DisabledMembersFromGroup.ps1
#>

<#
.SYNOPSIS
    Retrait automatique des comptes désactivés du groupe "USB Authorized"
.DESCRIPTION
    Ce script identifie et retire tous les utilisateurs et ordinateurs désactivés
    du groupe de sécurité USB Authorized
#>

# ---- EDIT ME ------------------------------------------------------------
$GroupDN    = "CN=USB Authorized,OU=Security,OU=Groups,DC=corp,DC=contoso,DC=local"
$LogPath    = "C:\Scripts\Logs\Remove-DisabledFromGroup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$ExportPath = "C:\Scripts\Reports\DisabledAccounts_Removed_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
# -------------------------------------------------------------------------

# Fonction de logging
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "INFO"    { Write-Host $logMessage -ForegroundColor Cyan }
        "HEADER"  { Write-Host $logMessage -ForegroundColor Magenta }
        default   { Write-Host $logMessage }
    }

    Add-Content -Path $LogPath -Value $logMessage
}

# Créer les dossiers si nécessaires
$LogDir = Split-Path -Path $LogPath -Parent
$ExportDir = Split-Path -Path $ExportPath -Parent

foreach ($dir in @($LogDir, $ExportDir)) {
    if (!(Test-Path -Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Début du script
Write-Log "============================================================" "HEADER"
Write-Log "  NETTOYAGE DES COMPTES DÉSACTIVÉS - GROUPE USB AUTHORIZED" "HEADER"
Write-Log "============================================================" "HEADER"
Write-Log "Date d'exécution: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
Write-Log "Exécuté par: $env:USERNAME sur $env:COMPUTERNAME" "INFO"
Write-Log "" "INFO"

# Vérifier que le groupe existe
try {
    $Group = Get-ADGroup -Identity $GroupDN -ErrorAction Stop
    Write-Log "[OK] Groupe trouvé: $($Group.Name)" "SUCCESS"
    Write-Log "  Distinguished Name: $($Group.DistinguishedName)" "INFO"
    Write-Log "" "INFO"
}
catch {
    Write-Log "[X] ERREUR CRITIQUE: Le groupe n'a pas pu être trouvé" "ERROR"
    Write-Log "  Path: $GroupDN" "ERROR"
    Write-Log "  Détails: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ===== INVENTAIRE INITIAL =====
Write-Log "=== INVENTAIRE INITIAL DU GROUPE ===" "HEADER"
try {
    $AllMembers = Get-ADGroupMember -Identity $GroupDN | Sort-Object Name
    Write-Log "Nombre total de membres: $($AllMembers.Count)" "INFO"
    Write-Log "" "INFO"
}
catch {
    Write-Log "[X] Erreur lors de l'inventaire: $($_.Exception.Message)" "ERROR"
    exit 1
}

# ===== ANALYSE DES MEMBRES =====
Write-Log "=== ANALYSE DES MEMBRES DU GROUPE ===" "HEADER"
$DisabledObjects = @()
$ActiveObjects = @()
$ErrorObjects = @()

foreach ($member in $AllMembers) {
    try {
        $ObjectDetails = $null
        $IsDisabled = $false
        $ObjectType = $member.objectClass

        # Récupérer les détails selon le type d'objet
        switch ($ObjectType) {
            "user" {
                $ObjectDetails = Get-ADUser -Identity $member.DistinguishedName -Properties Enabled, LastLogonDate, Description
                $IsDisabled = -not $ObjectDetails.Enabled
            }
            "computer" {
                $ObjectDetails = Get-ADComputer -Identity $member.DistinguishedName -Properties Enabled, LastLogonDate, Description, OperatingSystem
                $IsDisabled = -not $ObjectDetails.Enabled
            }
            default {
                # Pour les groupes ou autres objets
                $ObjectDetails = Get-ADObject -Identity $member.DistinguishedName -Properties *
                $IsDisabled = $false # Les groupes ne peuvent pas être "désactivés"
            }
        }

        # Créer un objet de résultat
        $ResultObj = [PSCustomObject]@{
            Name = $member.Name
            SamAccountName = $member.SamAccountName
            ObjectType = $ObjectType
            Enabled = -not $IsDisabled
            Status = if ($IsDisabled) { "Désactivé" } else { "Actif" }
            LastLogonDate = if ($ObjectDetails.LastLogonDate) { $ObjectDetails.LastLogonDate } else { "Jamais" }
            Description = $ObjectDetails.Description
            OperatingSystem = if ($ObjectType -eq "computer") { $ObjectDetails.OperatingSystem } else { "N/A" }
            DistinguishedName = $member.DistinguishedName
            Action = ""
            Result = ""
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        if ($IsDisabled) {
            $DisabledObjects += $ResultObj
            Write-Log "[!] DÉSACTIVÉ: $($member.Name) ($ObjectType)" "WARNING"
        }
        else {
            $ActiveObjects += $ResultObj
            Write-Log "[OK] Actif: $($member.Name) ($ObjectType)" "INFO"
        }
    }
    catch {
        Write-Log "[X] Erreur lors de l'analyse de $($member.Name): $($_.Exception.Message)" "ERROR"
        $ErrorObj = [PSCustomObject]@{
            Name = $member.Name
            SamAccountName = $member.SamAccountName
            ObjectType = $member.objectClass
            Enabled = "Erreur"
            Status = "Erreur d'analyse"
            LastLogonDate = "N/A"
            Description = "N/A"
            OperatingSystem = "N/A"
            DistinguishedName = $member.DistinguishedName
            Action = "Aucune"
            Result = $_.Exception.Message
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
        $ErrorObjects += $ErrorObj
    }
}

Write-Log "" "INFO"
Write-Log "Résumé de l'analyse:" "INFO"
Write-Log "  - Objets actifs:     $($ActiveObjects.Count)" "SUCCESS"
Write-Log "  - Objets désactivés: $($DisabledObjects.Count)" "WARNING"
Write-Log "  - Erreurs d'analyse: $($ErrorObjects.Count)" "ERROR"
Write-Log "" "INFO"

# ===== AFFICHAGE DES OBJETS DÉSACTIVÉS =====
if ($DisabledObjects.Count -gt 0) {
    Write-Log "=== LISTE DES OBJETS DÉSACTIVÉS À RETIRER ===" "HEADER"
    foreach ($obj in $DisabledObjects) {
        Write-Log "  - $($obj.Name) [$($obj.ObjectType)] - Dernière connexion: $($obj.LastLogonDate)" "WARNING"
    }
    Write-Log "" "INFO"
}
else {
    Write-Log "[OK] Aucun objet désactivé trouvé dans le groupe" "SUCCESS"
    Write-Log "Le groupe est propre, aucune action nécessaire" "SUCCESS"
    Write-Log "" "INFO"

    # Export quand même pour traçabilité
    $AllObjects = $ActiveObjects + $ErrorObjects
    $AllObjects | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Log "[OK] Rapport exporté: $ExportPath" "SUCCESS"
    Write-Log "[OK] Log complet: $LogPath" "SUCCESS"

    Write-Host "`nAppuyez sur une touche pour fermer..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

# ===== CONFIRMATION AVANT RETRAIT =====
Write-Log "=== CONFIRMATION ===" "HEADER"
Write-Host "`n[!] ATTENTION: Vous êtes sur le point de retirer $($DisabledObjects.Count) objet(s) désactivé(s) du groupe" -ForegroundColor Yellow
Write-Host "Voulez-vous continuer? (O/N): " -NoNewline -ForegroundColor Yellow
$Confirmation = Read-Host

if ($Confirmation -notin @('O', 'o', 'Oui', 'oui', 'Y', 'y', 'Yes', 'yes')) {
    Write-Log "[X] Opération annulée par l'utilisateur" "WARNING"
    Write-Log "" "INFO"

    # Export des objets identifiés sans retrait
    $AllObjects = $ActiveObjects + $DisabledObjects + $ErrorObjects
    $AllObjects | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Log "[OK] Rapport (sans modification) exporté: $ExportPath" "SUCCESS"
    Write-Log "[OK] Log complet: $LogPath" "SUCCESS"

    Write-Host "`nAppuyez sur une touche pour fermer..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

Write-Log "[OK] Confirmation reçue, début des retraits..." "SUCCESS"
Write-Log "" "INFO"

# ===== RETRAIT DES OBJETS DÉSACTIVÉS =====
Write-Log "=== RETRAIT DES OBJETS DÉSACTIVÉS ===" "HEADER"
$SuccessCount = 0
$FailCount = 0

foreach ($obj in $DisabledObjects) {
    try {
        Remove-ADGroupMember -Identity $GroupDN -Members $obj.DistinguishedName -Confirm:$false -ErrorAction Stop
        Write-Log "[OK] $($obj.Name) - Retiré avec succès" "SUCCESS"
        $obj.Action = "Retiré"
        $obj.Result = "Succès"
        $SuccessCount++
    }
    catch {
        Write-Log "[X] $($obj.Name) - ERREUR: $($_.Exception.Message)" "ERROR"
        $obj.Action = "Tentative de retrait"
        $obj.Result = "ERREUR: $($_.Exception.Message)"
        $FailCount++
    }
}

Write-Log "" "INFO"

# ===== INVENTAIRE FINAL =====
Write-Log "=== INVENTAIRE FINAL DU GROUPE ===" "HEADER"
try {
    $MembersAfter = Get-ADGroupMember -Identity $GroupDN | Sort-Object Name
    Write-Log "Nombre de membres restants: $($MembersAfter.Count)" "INFO"
    Write-Log "" "INFO"

    if ($MembersAfter.Count -gt 0) {
        Write-Log "Membres actifs restants:" "INFO"
        foreach ($member in $MembersAfter) {
            Write-Log "  - $($member.Name) ($($member.ObjectClass))" "INFO"
        }
    }
    else {
        Write-Log "[!] Le groupe est maintenant vide" "WARNING"
    }
    Write-Log "" "INFO"
}
catch {
    Write-Log "[X] Erreur lors de l'inventaire final: $($_.Exception.Message)" "ERROR"
}

# ===== RÉSUMÉ FINAL =====
Write-Log "============================================================" "HEADER"
Write-Log "                    RÉSUMÉ DES OPÉRATIONS" "HEADER"
Write-Log "============================================================" "HEADER"
Write-Log "Membres initiaux:                $($AllMembers.Count)" "INFO"
Write-Log "  - Objets actifs:               $($ActiveObjects.Count)" "SUCCESS"
Write-Log "  - Objets désactivés trouvés:   $($DisabledObjects.Count)" "WARNING"
Write-Log "  - Erreurs d'analyse:           $($ErrorObjects.Count)" "ERROR"
Write-Log "" "INFO"
Write-Log "Opérations de retrait:" "INFO"
Write-Log "  [OK] Retirés avec succès:      $SuccessCount" "SUCCESS"
Write-Log "  [X]  Échecs:                   $FailCount" "ERROR"
Write-Log "" "INFO"
Write-Log "Membres après nettoyage:         $($MembersAfter.Count)" "INFO"
Write-Log "Objets retirés au total:         $($AllMembers.Count - $MembersAfter.Count)" "SUCCESS"
Write-Log "" "INFO"

# ===== EXPORT DES RÉSULTATS =====
try {
    $AllResults = $ActiveObjects + $DisabledObjects + $ErrorObjects
    $AllResults | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
    Write-Log "[OK] Rapport détaillé exporté: $ExportPath" "SUCCESS"
}
catch {
    Write-Log "[X] Erreur lors de l'export CSV: $($_.Exception.Message)" "ERROR"
}

Write-Log "[OK] Log complet sauvegardé: $LogPath" "SUCCESS"
Write-Log "" "INFO"
Write-Log "============================================================" "HEADER"
Write-Log "                    FIN DU SCRIPT" "HEADER"
Write-Log "============================================================" "HEADER"

# ===== AFFICHAGE DES TABLEAUX =====
Write-Host "`n"
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "           OBJETS DÉSACTIVÉS RETIRÉS" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
if ($DisabledObjects.Count -gt 0) {
    $DisabledObjects | Format-Table Name, ObjectType, Status, LastLogonDate, Action, Result -AutoSize
}
else {
    Write-Host "Aucun objet désactivé trouvé" -ForegroundColor Green
}

Write-Host "`n"
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "           OBJETS ACTIFS CONSERVÉS ($($ActiveObjects.Count))" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
if ($ActiveObjects.Count -gt 0) {
    $ActiveObjects | Format-Table Name, ObjectType, Status, LastLogonDate -AutoSize
}

if ($ErrorObjects.Count -gt 0) {
    Write-Host "`n"
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Red
    Write-Host "           ERREURS D'ANALYSE" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Red
    $ErrorObjects | Format-Table Name, ObjectType, Result -AutoSize
}

# Statistiques finales
Write-Host "`n"
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "                  STATISTIQUES FINALES" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "Membres AVANT:    " -NoNewline; Write-Host "$($AllMembers.Count)" -ForegroundColor Yellow
Write-Host "Membres APRÈS:    " -NoNewline; Write-Host "$($MembersAfter.Count)" -ForegroundColor Green
Write-Host "Objets retirés:   " -NoNewline; Write-Host "$($AllMembers.Count - $MembersAfter.Count)" -ForegroundColor Cyan
Write-Host "Taux de succès:   " -NoNewline
if ($DisabledObjects.Count -gt 0) {
    $SuccessRate = [math]::Round(($SuccessCount / $DisabledObjects.Count) * 100, 2)
    Write-Host "$SuccessRate%" -ForegroundColor $(if ($SuccessRate -eq 100) { "Green" } else { "Yellow" })
}
else {
    Write-Host "N/A" -ForegroundColor Gray
}

# Pause finale
Write-Host "`nAppuyez sur une touche pour fermer..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
