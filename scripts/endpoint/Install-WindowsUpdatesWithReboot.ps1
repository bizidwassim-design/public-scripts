<#
.SYNOPSIS
    Installs all pending Windows updates on a server in repeated cycles, rebooting and resuming until none remain.
.DESCRIPTION
    Installs PSWindowsUpdate if needed, runs up to MaxCycles of Get/Install-WindowsUpdate, detects a
    pending reboot, registers a startup scheduled task to resume after reboot, reboots, and removes
    the task when done. Writes an HTML report + log copy to a central share (falls back to %TEMP%).
    Compatible: Windows Server 2019, 2022, 2025.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin | PSWindowsUpdate (auto-installed) | write access to the report share
    Impact      : Modifies the server (installs updates, creates a scheduled task, REBOOTS the server)
    License     : MIT
.EXAMPLE
    .\Install-WindowsUpdatesWithReboot.ps1
    .\Install-WindowsUpdatesWithReboot.ps1 -ReportPath "\\SRV-APP01\Reports\WindowsUpdate\" -MaxCycles 3
#>

<#
.SYNOPSIS
    Script de mise a jour Windows avec cycles multiples et rapports centralises
.DESCRIPTION
    Effectue des cycles de mise a jour Windows jusqu'a ce qu'il n'y ait plus de mises a jour disponibles.
    Genere un rapport centralise sur le partage ReportPath
#>
# l'endroit ou les rapports seront déposés
# nombre de redémarrage maximum
# le temps d'attente pour le redémarrage

[CmdletBinding()]
param(
    # ---- EDIT ME (defaults) ------------------------------------------------
    [string]$ReportPath = "\\SRV-APP01\Reports\WindowsUpdate\",
    [int]$MaxCycles = 3,
    [int]$RebootTimeout = 300
    # -------------------------------------------------------------------------
)

# ---- EDIT ME ------------------------------------------------------------
$TaskName    = "Contoso_WindowsUpdate_Continue"   # scheduled task used to resume after reboot
$ReportOwner = "Contoso - IT Infrastructure"      # footer of the HTML report
# -------------------------------------------------------------------------

# Variables globales
$ServerName = $env:COMPUTERNAME
$ScriptStart = Get-Date
$LogFile = "$env:TEMP\WindowsUpdate_$(Get-Date -Format 'yyyyMMdd').log"
$UpdateHistory = @()
$TotalCycles = 0
$TotalUpdatesInstalled = 0

#region Fonctions

# declaration des parametres d'affichage et d'informations pour les logs

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARNING','ERROR','SUCCESS')]
        [string]$Level = 'INFO'
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"

    $Color = switch($Level) {
        'INFO'    { 'White' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
        'SUCCESS' { 'Green' }
    }

    Write-Host $LogMessage -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $LogMessage
}

# Appel de la tache des mises a jour

function Install-PSWindowsUpdate {
    Write-Log "Verification du module PSWindowsUpdate..."

    if (!(Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Log "Installation du module PSWindowsUpdate..." -Level WARNING
        try {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
            Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck -ErrorAction Stop
            Write-Log "Module PSWindowsUpdate installe avec succes" -Level SUCCESS
        }
        catch {
            Write-Log "Erreur lors de l'installation de PSWindowsUpdate: $_" -Level ERROR
            return $false
        }
    }

    Import-Module PSWindowsUpdate -Force
    Write-Log "Module PSWindowsUpdate charge" -Level SUCCESS
    return $true
}

# Verification si il y a un redemarrage necessaire

function Get-PendingReboot {
    $PendingReboot = $false

    # Verification Component-Based Servicing
    if (Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue) {
        $PendingReboot = $true
    }

    # Verification Windows Update
    if (Get-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue) {
        $PendingReboot = $true
    }

    # Verification PendingFileRenameOperations
    $PendingFileRename = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($PendingFileRename) {
        $PendingReboot = $true
    }

    return $PendingReboot
}

# Installation des mises a jour

function Install-WindowsUpdates {
    param([int]$CycleNumber)

    Write-Log "=== DeBUT DU CYCLE $CycleNumber ===" -Level INFO

    try {
        Write-Log "Recherche des mises a jour disponibles..."

        # Recherche des mises a jour
        $Updates = Get-WindowsUpdate -MicrosoftUpdate -Verbose

        if ($Updates.Count -eq 0) {
            Write-Log "Aucune mise a jour disponible" -Level SUCCESS
            return @{
                UpdatesFound = 0
                UpdatesInstalled = 0
                RebootRequired = $false
                Success = $true
            }
        }

        Write-Log "Mises a jour trouvees: $($Updates.Count)" -Level INFO

        foreach ($Update in $Updates) {
            Write-Log "  - $($Update.Title) [Taille: $([math]::Round($Update.Size/1MB,2)) MB]"
        }

        # Installation des mises a jour
        Write-Log "Installation des mises a jour en cours..."

        $InstallResult = Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Verbose

        $InstalledCount = ($InstallResult | Where-Object {$_.Result -eq 'Installed' -or $_.Result -eq 'InstalledPendingReboot'}).Count

        Write-Log "Mises a jour installees: $InstalledCount" -Level SUCCESS

        # Enregistrement de l'historique
        foreach ($Update in $InstallResult) {
            $script:UpdateHistory += [PSCustomObject]@{
                Cycle = $CycleNumber
                Titre = $Update.Title
                KB = $Update.KB
                Taille = "$([math]::Round($Update.Size/1MB,2)) MB"
                Resultat = $Update.Result
                Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }

        $script:TotalUpdatesInstalled += $InstalledCount

        # Verification si redemarrage necessaire
        $RebootNeeded = Get-PendingReboot

        if ($RebootNeeded) {
            Write-Log "Redemarrage requis pour finaliser les installations" -Level WARNING
        }

        return @{
            UpdatesFound = $Updates.Count
            UpdatesInstalled = $InstalledCount
            RebootRequired = $RebootNeeded
            Success = $true
        }
    }
    catch {
        Write-Log "Erreur lors de l'installation des mises a jour: $_" -Level ERROR
        return @{
            UpdatesFound = 0
            UpdatesInstalled = 0
            RebootRequired = $false
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Appel le redemarrage si necessaire

function Invoke-ServerReboot {
    param([string]$Reason = "Installation de mises a jour Windows")

    Write-Log "Preparation du redemarrage du serveur..." -Level WARNING
    Write-Log "Le serveur redemarrera dans 60 secondes" -Level WARNING

    # Sauvegarde du rapport avant redemarrage
    Save-Report -Partial

    Start-Sleep -Seconds 5

    # Redemarrage avec notification
    shutdown /r /t 60 /c $Reason /d p:2:17
}

# Sauvegarde du rapport sur le partage central et ajout d'information si plus d'un redemarrage

function Save-Report {
    param([switch]$Partial)

    try {
        # Creation du dossier si necessaire
        if (!(Test-Path $ReportPath)) {
            New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
        }

        $ReportFile = Join-Path $ReportPath "${ServerName}_UpdateReport_$(Get-Date -Format 'yyyyMMdd').html"

        $ScriptEnd = Get-Date
        $Duration = $ScriptEnd - $ScriptStart

        # Generation du rapport HTML
        $HTML = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Rapport de mise a jour - $ServerName</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #0066cc; border-bottom: 3px solid #0066cc; padding-bottom: 10px; }
        h2 { color: #333; background-color: #e7f3ff; padding: 10px; border-left: 4px solid #0066cc; }
        .info-box { background-color: #f0f8ff; border: 1px solid #0066cc; padding: 15px; margin: 10px 0; border-radius: 5px; }
        .success { color: #28a745; font-weight: bold; }
        .warning { color: #ffc107; font-weight: bold; }
        .error { color: #dc3545; font-weight: bold; }
        table { border-collapse: collapse; width: 100%; margin: 15px 0; }
        th { background-color: #0066cc; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 10px; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .footer { margin-top: 20px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 0.9em; }
        .status-partial { color: #ffc107; }
        .status-complete { color: #28a745; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Rapport de mise a jour Windows</h1>

        <div class="info-box">
            <h3>Informations du serveur</h3>
            <p><strong>Serveur:</strong> $ServerName</p>
            <p><strong>Domaine:</strong> $env:USERDNSDOMAIN</p>
            <p><strong>Systeme:</strong> $(Get-WmiObject Win32_OperatingSystem | Select-Object -ExpandProperty Caption)</p>
            <p><strong>Date de debut:</strong> $($ScriptStart.ToString("yyyy-MM-dd HH:mm:ss"))</p>
            <p><strong>Date de fin:</strong> $($ScriptEnd.ToString("yyyy-MM-dd HH:mm:ss"))</p>
            <p><strong>Duree totale:</strong> $($Duration.Hours)h $($Duration.Minutes)m $($Duration.Seconds)s</p>
            <p><strong>Statut:</strong> <span class="$(if($Partial){'status-partial'}else{'status-complete'})">$(if($Partial){'En cours (partiel)'}else{'Termine'})</span></p>
        </div>

        <h2>Resume</h2>
        <div class="info-box">
            <p><strong>Cycles executes:</strong> $TotalCycles</p>
            <p><strong>Mises a jour installees:</strong> <span class="success">$TotalUpdatesInstalled</span></p>
        </div>

        <h2>Detail des mises a jour</h2>
"@

        if ($UpdateHistory.Count -gt 0) {
            $HTML += @"
        <table>
            <tr>
                <th>Cycle</th>
                <th>Titre</th>
                <th>KB</th>
                <th>Taille</th>
                <th>Resultat</th>
                <th>Date</th>
            </tr>
"@
            foreach ($Update in $UpdateHistory) {
                $ResultClass = switch($Update.Resultat) {
                    'Installed' { 'success' }
                    'InstalledPendingReboot' { 'warning' }
                    default { 'error' }
                }

                $HTML += @"
            <tr>
                <td>$($Update.Cycle)</td>
                <td>$($Update.Titre)</td>
                <td>$($Update.KB)</td>
                <td>$($Update.Taille)</td>
                <td class="$ResultClass">$($Update.Resultat)</td>
                <td>$($Update.Date)</td>
            </tr>
"@
            }
            $HTML += "        </table>"
        }
        else {
            $HTML += "        <p>Aucune mise a jour installee durant cette session.</p>"
        }

        $HTML += @"

        <div class="footer">
            <p>Rapport genere le $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
            <p>$ReportOwner</p>
            <p>Fichier de log: $LogFile</p>
        </div>
    </div>
</body>
</html>
"@

        $HTML | Out-File -FilePath $ReportFile -Encoding UTF8 -Force
        Write-Log "Rapport sauvegarde: $ReportFile" -Level SUCCESS

        # Copie du fichier de log
        $LogDestination = Join-Path $ReportPath "UpdateLog_${ServerName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        Copy-Item -Path $LogFile -Destination $LogDestination -Force

        return $ReportFile
    }
    catch {
        Write-Log "Erreur lors de la sauvegarde du rapport: $_" -Level ERROR
        return $null
    }
}

#endregion

#region Script Principal

Write-Log "========================================" -Level INFO
Write-Log "DEMARRAGE DU SCRIPT DE MISE A JOUR" -Level INFO
Write-Log "========================================" -Level INFO
Write-Log "Serveur: $ServerName"
Write-Log "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Cycles maximum: $MaxCycles"

# Verification des privileges administrateur
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "Ce script doit etre execute en tant qu'administrateur!" -Level ERROR
    exit 1
}

# Verification de la connectivite au serveur de rapport
Write-Log "Verification de l'acces au serveur de rapports..."
if (!(Test-Path $ReportPath)) {
    try {
        New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
        Write-Log "Dossier de rapport cree: $ReportPath" -Level SUCCESS
    }
    catch {
        Write-Log "Impossible d'acceder au chemin de rapport: $ReportPath" -Level ERROR
        Write-Log "Le rapport sera sauvegarde localement dans $env:TEMP" -Level WARNING
        $ReportPath = $env:TEMP
    }
}
else {
    Write-Log "Acces au serveur de rapports confirme" -Level SUCCESS
}

# Installation du module PSWindowsUpdate
if (!(Install-PSWindowsUpdate)) {
    Write-Log "Impossible de continuer sans le module PSWindowsUpdate" -Level ERROR
    exit 1
}

# Boucle de cycles de mise a jour
$ContinueUpdating = $true
$CycleNumber = 0

while ($ContinueUpdating -and $CycleNumber -lt $MaxCycles) {
    $CycleNumber++
    $TotalCycles = $CycleNumber

    # Installation des mises a jour
    $Result = Install-WindowsUpdates -CycleNumber $CycleNumber

    if (!$Result.Success) {
        Write-Log "echec du cycle $CycleNumber" -Level ERROR
        break
    }

    if ($Result.UpdatesFound -eq 0) {
        Write-Log "Plus de mises a jour disponibles. Arret des cycles." -Level SUCCESS
        $ContinueUpdating = $false
        break
    }

    # Gestion du redemarrage si necessaire
    # avant le redemarrage, creation d'une tache qui va reprendre les mises a jour suite au redemarrage


    if ($Result.RebootRequired) {
        Write-Log "Un redemarrage est necessaire apres le cycle $CycleNumber" -Level WARNING

        if ($CycleNumber -lt $MaxCycles) {
            Write-Log "Il reste $($MaxCycles - $CycleNumber) cycle(s) apres redemarrage" -Level INFO

            # Creer une tâche planifiee pour continuer apres redemarrage
            $TaskAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
            $TaskTrigger = New-ScheduledTaskTrigger -AtStartup
            $TaskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            $TaskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

            try {
                # Supprime la tâche si elle existe deja
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

                Register-ScheduledTask -TaskName $TaskName -Action $TaskAction -Trigger $TaskTrigger -Principal $TaskPrincipal -Settings $TaskSettings | Out-Null
                Write-Log "Tâche planifiee creee pour continuer apres redemarrage" -Level SUCCESS
            }
            catch {
                Write-Log "Erreur lors de la creation de la tâche planifiee: $_" -Level ERROR
            }
        }

        Invoke-ServerReboot -Reason "Cycle $CycleNumber - Installation de mises a jour Windows"
        exit 0
    }
    else {
        Write-Log "Aucun redemarrage necessaire, verification du cycle suivant..." -Level INFO
        Start-Sleep -Seconds 10
    }
}

# Suppression de la tâche planifiee si elle existe

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Log "Tâche planifiee supprimee" -Level INFO
}

# Generation du rapport final

Write-Log "========================================" -Level INFO
Write-Log "FIN DU SCRIPT DE MISE A JOUR" -Level INFO
Write-Log "========================================" -Level INFO
Write-Log "Cycles executes: $TotalCycles" -Level SUCCESS
Write-Log "Mises a jour installees: $TotalUpdatesInstalled" -Level SUCCESS

$FinalReport = Save-Report
if ($FinalReport) {
    Write-Log "Rapport final disponible: $FinalReport" -Level SUCCESS
}

Write-Log "Script termine avec succes!" -Level SUCCESS

#endregion
