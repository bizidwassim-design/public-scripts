#Requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Keeps an AD group in sync with the enabled users whose extensionAttribute1 equals a given value.
.DESCRIPTION
    Finds enabled users with extensionAttribute1 = AttributeValue, compares them with the current
    group members, adds the missing users and removes members that no longer carry the attribute.
    Logs to a file, supports -WhatIf and triggers a replication (repadmin /syncall) at the end.
    Designed to run as a weekly scheduled task on a domain controller.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | write permission on the group | repadmin (optional)
    Impact      : Modifies AD (adds/removes group members)
    License     : MIT
.EXAMPLE
    .\Sync-ADGroupFromExtensionAttribute.ps1
    .\Sync-ADGroupFromExtensionAttribute.ps1 -GroupName "All-Regions" -AttributeValue "CyberSecurityTraining" -WhatIf
#>

<#
.SYNOPSIS
    Synchronise le groupe AD base sur l'attribut extensionAttribute1

.DESCRIPTION
    Ce script verifie les usagers AD avec extensionAttribute1 = valeur cible
    et synchronise leur appartenance au groupe
    - Ajoute les usagers qui ont l'attribut mais ne sont pas dans le groupe
    - Retire les usagers du groupe qui n'ont plus l'attribut

.PARAMETER GroupName
    Nom du groupe AD a synchroniser (par defaut: All-Regions)

.PARAMETER AttributeValue
    Valeur de l'attribut a verifier (par defaut: CyberSecurityTraining)

.PARAMETER LogPath
    Chemin du fichier de log (par defaut: C:\Scripts\Logs\GroupSync.log)
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
    # ---- EDIT ME (defaults) ------------------------------------------------
    [Parameter(Mandatory=$false)]
    [string]$GroupName = "All-Regions",

    [Parameter(Mandatory=$false)]
    [string]$AttributeValue = "CyberSecurityTraining",

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\Scripts\Logs\GroupSync.log"
    # -------------------------------------------------------------------------
)

# Fonction pour ecrire dans le log
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARNING','ERROR','SUCCESS')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Creer le repertoire si necessaire
    $logDir = Split-Path -Path $LogPath -Parent
    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    # Ecrire dans le fichier et afficher a l'ecran
    Add-Content -Path $LogPath -Value $logMessage

    switch ($Level) {
        'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
        default   { Write-Host $logMessage }
    }
}

# Debut du script
Write-Log "========================================" -Level INFO
Write-Log "Debut de la synchronisation du groupe $GroupName" -Level INFO
Write-Log "========================================" -Level INFO

try {
    # Verifier que le module Active Directory est disponible
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "Le module ActiveDirectory n'est pas disponible"
    }

    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "Module ActiveDirectory importe avec succes" -Level INFO

    # Verifier que le groupe existe
    Write-Log "Verification de l'existence du groupe: $GroupName" -Level INFO
    try {
        $group = Get-ADGroup -Identity $GroupName -ErrorAction Stop
        Write-Log "Groupe trouve: $($group.DistinguishedName)" -Level SUCCESS
    }
    catch {
        throw "Le groupe '$GroupName' n'existe pas ou est inaccessible: $($_.Exception.Message)"
    }

    # Recuperer tous les usagers avec l'attribut extensionAttribute1 = valeur cible
    Write-Log "Recherche des usagers avec extensionAttribute1 = '$AttributeValue'" -Level INFO
    $usersWithAttribute = Get-ADUser -Filter "extensionAttribute1 -eq '$AttributeValue'" -Properties extensionAttribute1, Enabled |
                          Where-Object { $_.Enabled -eq $true }

    Write-Log "Nombre d'usagers actifs avec l'attribut: $($usersWithAttribute.Count)" -Level INFO

    # Recuperer les membres actuels du groupe
    Write-Log "Recuperation des membres actuels du groupe" -Level INFO
    $currentMembers = Get-ADGroupMember -Identity $GroupName | Where-Object { $_.objectClass -eq 'user' }
    Write-Log "Nombre de membres actuels dans le groupe: $($currentMembers.Count)" -Level INFO

    # Convertir en tableaux de SamAccountName pour faciliter la comparaison
    $usersWithAttributeSAM = $usersWithAttribute | Select-Object -ExpandProperty SamAccountName
    $currentMembersSAM = $currentMembers | Select-Object -ExpandProperty SamAccountName

    # Determiner les usagers a ajouter (ont l'attribut mais ne sont pas dans le groupe)
    $usersToAdd = $usersWithAttributeSAM | Where-Object { $_ -notin $currentMembersSAM }

    # Determiner les usagers a retirer (sont dans le groupe mais n'ont plus l'attribut)
    $usersToRemove = $currentMembersSAM | Where-Object { $_ -notin $usersWithAttributeSAM }

    Write-Log "----------------------------------------" -Level INFO
    Write-Log "Analyse terminee:" -Level INFO
    Write-Log "  - Usagers a ajouter: $($usersToAdd.Count)" -Level INFO
    Write-Log "  - Usagers a retirer: $($usersToRemove.Count)" -Level INFO
    Write-Log "----------------------------------------" -Level INFO

    # Compteurs pour le resume
    $addedCount = 0
    $removedCount = 0
    $errorCount = 0

    # Ajouter les usagers au groupe
    if ($usersToAdd.Count -gt 0) {
        Write-Log "Debut de l'ajout des usagers au groupe" -Level INFO
        foreach ($user in $usersToAdd) {
            try {
                if ($PSCmdlet.ShouldProcess($user, "Ajouter au groupe $GroupName")) {
                    Add-ADGroupMember -Identity $GroupName -Members $user -ErrorAction Stop
                    Write-Log "  [AJOUTE] $user" -Level SUCCESS
                    $addedCount++
                }
            }
            catch {
                Write-Log "  [ERREUR] Impossible d'ajouter $user : $($_.Exception.Message)" -Level ERROR
                $errorCount++
            }
        }
    }
    else {
        Write-Log "Aucun usager a ajouter" -Level INFO
    }

    # Retirer les usagers du groupe
    if ($usersToRemove.Count -gt 0) {
        Write-Log "Debut du retrait des usagers du groupe" -Level INFO
        foreach ($user in $usersToRemove) {
            try {
                if ($PSCmdlet.ShouldProcess($user, "Retirer du groupe $GroupName")) {
                    Remove-ADGroupMember -Identity $GroupName -Members $user -Confirm:$false -ErrorAction Stop
                    Write-Log "  [RETIRE] $user" -Level SUCCESS
                    $removedCount++
                }
            }
            catch {
                Write-Log "  [ERREUR] Impossible de retirer $user : $($_.Exception.Message)" -Level ERROR
                $errorCount++
            }
        }
    }
    else {
        Write-Log "Aucun usager a retirer" -Level INFO
    }

    # Resume final
    Write-Log "========================================" -Level INFO
    Write-Log "RESUME DE LA SYNCHRONISATION" -Level INFO
    Write-Log "========================================" -Level INFO
    Write-Log "Groupe: $GroupName" -Level INFO
    Write-Log "Attribut verifie: extensionAttribute1 = '$AttributeValue'" -Level INFO
    Write-Log "Usagers ajoutes: $addedCount" -Level SUCCESS
    Write-Log "Usagers retires: $removedCount" -Level SUCCESS
    Write-Log "Erreurs rencontrees: $errorCount" -Level $(if ($errorCount -gt 0) { 'WARNING' } else { 'INFO' })
    Write-Log "Synchronisation terminee avec succes" -Level SUCCESS
    Write-Log "========================================" -Level INFO
}
catch {
    Write-Log "========================================" -Level ERROR
    Write-Log "ERREUR CRITIQUE DANS LE SCRIPT" -Level ERROR
    Write-Log $_.Exception.Message -Level ERROR
    Write-Log "Ligne: $($_.InvocationInfo.ScriptLineNumber)" -Level ERROR
    Write-Log "========================================" -Level ERROR
    exit 1
}

# Forcer la replication AD (a executer sur un DC)
repadmin /syncall /AdeP

exit 0
