<#
.SYNOPSIS
    Triggers a Confluence Cloud site backup, waits for it, downloads the ZIP and emails the result.
.DESCRIPTION
    Calls the Confluence Cloud backup REST endpoints (runbackup / getprogress) with an API token,
    handles Atlassian's backup-frequency limitation (re-uses an existing finished backup if one is
    available), polls progress up to one hour, downloads the ZIP to a local folder, purges backups
    older than 120 days and sends a success / failure / postponed email. Meant to run weekly as a
    scheduled task.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Atlassian API token (site admin) | SMTP relay | PowerShell 5.1+
    Impact      : Read-only on Confluence (creates a backup export); deletes local backups older than 120 days
    License     : MIT
.EXAMPLE
    .\Backup-ConfluenceCloud.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Set Atlassian API credentials, headers, and other specifics
$email    = "admin@contoso.com"
$apiToken = "<API-KEY>"

# Email settings
$smtpServer = "smtp.contoso.com"
$smtpFrom   = "confluence-backup@contoso.com"
$smtpTo     = "it-support@contoso.com"

$domain = "contoso.atlassian.net"

$attachments = 'true' # Tells the script whether or not to pull down the attachments as well
$cloud = 'true' # Tells the script whether to export the backup for Cloud or Server

# Location on server where script is run to dump the backup zip file.
$destination = 'C:\Scripts\Confluence\Backup\'
# -------------------------------------------------------------------------

# Prepare authentication and headers with improvements
$auth = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($email):$($apiToken)"))
$headers = @{
    "Authorization" = "Basic $auth"
    "Content-Type" = "application/json; charset=utf-8"
    "Accept" = "application/json"
    "X-Atlassian-Token" = "no-check"
    "User-Agent" = "PowerShell"
}

# Check if destination folder exists, create if missing
if (!(Test-Path -path $destination)) {
    Write-Host "Folder is not present, creating folder"
    mkdir $destination
} else {
    Write-Host "Path is already present"
}

# Supprimer les fichiers de plus de 3 mois (120 jours)
Write-Host "Nettoyage des anciens fichiers de sauvegarde..."
$files = Get-ChildItem -Path $destination -File
foreach ($file in $files) {
    $fileAge = (Get-Date) - $file.CreationTime
    if ($fileAge.Days -gt 120) {
        Write-Host "Suppression du fichier ancien : $($file.Name)"
        Remove-Item -Path $file.FullName -Force
    }
}

# Set body with proper boolean conversion
$body = @{
    cbAttachments = [bool]::Parse($attachments)
    exportToCloud = [bool]::Parse($cloud)
}
$bodyjson = $body | ConvertTo-Json -Depth 3

# Set Atlassian Cloud backup endpoint
$backupEndpoint = "https://$domain/wiki/rest/obm/1.0/runbackup"
$backupStatusURL = "https://$domain/wiki/rest/obm/1.0/getprogress"

Write-Host "=== DÉBUT DE LA SAUVEGARDE CONFLUENCE ==="
Write-Host "Tentative de création de sauvegarde..."

# Create a Confluence Cloud backup with improved error handling
try {
    $backupResponse = Invoke-WebRequest -Method POST -Uri $backupEndpoint -Headers $headers -Body $bodyjson
    Write-Host "Sauvegarde initiée avec succès - Status: $($backupResponse.StatusCode)"
} catch {
    # Gestion détaillée des erreurs
    $statusCode = $_.Exception.Response.StatusCode.value__

    # Lire le contenu de la réponse d'erreur
    $responseStream = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($responseStream)
    $responseBody = $reader.ReadToEnd()
    $reader.Close()
    $responseStream.Close()

    Write-Host "=== ERREUR LORS DE LA CRÉATION DE SAUVEGARDE ==="
    Write-Host "Code d'erreur: $statusCode"
    Write-Host "Détail de l'erreur: $responseBody"

    # Vérifier si c'est une limitation de fréquence
    if ($responseBody -match "Backup frequency is limited" -or $responseBody -match "You can not make another backup right now") {
        Write-Host "LIMITATION DE FRÉQUENCE DÉTECTÉE - Tentative de récupération de la sauvegarde existante"

        # Extraire le temps d'attente si disponible
        $waitMessage = "Temps d'attente non spécifié"
        if ($responseBody -match "(\d+)h (\d+)m") {
            $hours = [int]$matches[1]
            $minutes = [int]$matches[2]
            $totalMinutes = ($hours * 60) + $minutes
            $waitMessage = "Prochaine sauvegarde possible dans $hours heures et $minutes minutes ($totalMinutes minutes au total)"
        }

        Write-Host $waitMessage
        Write-Host "Vérification de l'existence d'une sauvegarde récente..."

        # Tenter de récupérer le statut actuel pour voir s'il y a une sauvegarde disponible
        try {
            $currentStatus = Invoke-WebRequest -Method GET -Uri $backupStatusURL -Headers $headers
            $currentStatusContent = $currentStatus.Content | ConvertFrom-Json

            Write-Host "Statut actuel: $($currentStatusContent.alternativePercentage)%"

            # Si une sauvegarde est terminée (100%), tenter de la télécharger
            if ($currentStatusContent.alternativePercentage -eq "100" -and $currentStatusContent.fileName) {
                Write-Host "Sauvegarde existante trouvée et terminée! Téléchargement en cours..."

                # Forcer le téléchargement de la sauvegarde existante
                $backupReady = $true
                $backupStatus = $currentStatus  # Utiliser le statut actuel pour le téléchargement

                # Continuer avec la logique de téléchargement (on sort du catch)

            } elseif ($currentStatusContent.alternativePercentage -ne "0" -and $currentStatusContent.alternativePercentage -ne "100") {
                # Une sauvegarde est en cours
                Write-Host "Une sauvegarde est déjà en cours ($($currentStatusContent.alternativePercentage)%). Attente de sa finalisation..."
                $backupReady = $false
                # Continuer avec la logique d'attente normale

            } else {
                # Pas de sauvegarde disponible ou en cours
                Write-Host "Aucune sauvegarde récente disponible."

                # Envoyer un email d'information pour limitation
                $emailSubject = "Sauvegarde Confluence reportée - Limitation de fréquence"
                $emailBody = @"
                <html>
                <body>
                <h3>Sauvegarde Confluence reportée</h3>
                <p>La sauvegarde Confluence a été reportée en raison des limitations de fréquence imposées par Atlassian.</p>
                <p><strong>Détail:</strong> $responseBody</p>
                <p><strong>Prochaine tentative recommandée:</strong> $waitMessage</p>
                <p><strong>Statut vérifié:</strong> Aucune sauvegarde récente disponible</p>
                <p><em>Script exécuté le: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</em></p>
                </body>
                </html>
"@

                Send-MailMessage -SmtpServer $smtpServer -From $smtpFrom -To $smtpTo -Subject $emailSubject -Body $emailBody -BodyAsHtml

                Write-Host "Email de notification envoyé. Script terminé."
                exit 0
            }

        } catch {
            Write-Host "Erreur lors de la vérification du statut existant: $($_.Exception.Message)"

            # Envoyer un email d'information pour limitation (sans vérification de statut)
            $emailSubject = "Sauvegarde Confluence reportée - Limitation de fréquence"
            $emailBody = @"
            <html>
            <body>
            <h3>Sauvegarde Confluence reportée</h3>
            <p>La sauvegarde Confluence a été reportée en raison des limitations de fréquence imposées par Atlassian.</p>
            <p><strong>Détail:</strong> $responseBody</p>
            <p><strong>Prochaine tentative recommandée:</strong> $waitMessage</p>
            <p><strong>Note:</strong> Impossible de vérifier s'il existe une sauvegarde récente</p>
            <p><em>Script exécuté le: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</em></p>
            </body>
            </html>
"@

            Send-MailMessage -SmtpServer $smtpServer -From $smtpFrom -To $smtpTo -Subject $emailSubject -Body $emailBody -BodyAsHtml

            Write-Host "Email de notification envoyé. Script terminé."
            exit 0
        }
    } else {
        # Autre type d'erreur
        Write-Host "Erreur non liée à la limitation de fréquence"

        # Envoyer un email d'erreur
        $emailSubject = "Erreur lors de la sauvegarde Confluence"
        $emailBody = @"
        <html>
        <body>
        <h3>Erreur lors de la sauvegarde Confluence</h3>
        <p>Une erreur s'est produite lors de la tentative de sauvegarde.</p>
        <p><strong>Code d'erreur:</strong> $statusCode</p>
        <p><strong>Détail de l'erreur:</strong> $responseBody</p>
        <p><em>Script exécuté le: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</em></p>
        </body>
        </html>
"@

        Send-MailMessage -SmtpServer $smtpServer -From $smtpFrom -To $smtpTo -Subject $emailSubject -Body $emailBody -BodyAsHtml

        Write-Host "Email d'erreur envoyé. Script terminé avec erreur."
        exit 1
    }
}

# Si on arrive ici, soit la sauvegarde a été créée avec succès,
# soit on a trouvé une sauvegarde existante à télécharger
if ($backupReady) {
    Write-Host "Sauvegarde disponible, préparation du téléchargement..."
} else {
    Write-Host "Sauvegarde créée, attente de la finalisation..."
}

# Wait for the backup to be ready (seulement si pas déjà prête)
if (-not $backupReady) {
    $maxAttempts = 60  # Maximum 60 tentatives (1 heure)
    $attempts = 0

    while (-not $backupReady -and $attempts -lt $maxAttempts) {
        Write-Host "Vérification du statut de sauvegarde (tentative $($attempts + 1)/$maxAttempts)..."
        Start-Sleep -Seconds 60

        try {
            # Get Backup Session ID
            $backupStatus = Invoke-WebRequest -Method GET -Uri $backupStatusURL -Headers $headers
            $statusContent = $backupStatus.Content | ConvertFrom-Json
            $backupReady = $statusContent.alternativePercentage -eq "100"
            Write-Host "Statut actuel de la sauvegarde: $($statusContent.alternativePercentage)%"

            $attempts++
        } catch {
            Write-Host "Erreur lors de la vérification du statut: $($_.Exception.Message)"
            $attempts++

            if ($attempts -ge $maxAttempts) {
                Write-Host "Nombre maximum de tentatives atteint. Abandon de la sauvegarde."

                # Envoyer email d'échec de suivi
                Send-MailMessage -SmtpServer $smtpServer -From $smtpFrom -To $smtpTo -Subject "Échec du suivi de sauvegarde Confluence" -Body "Impossible de suivre le progrès de la sauvegarde Confluence après $maxAttempts tentatives." -BodyAsHtml
                exit 1
            }
        }
    }

    if (-not $backupReady) {
        Write-Host "Timeout: La sauvegarde n'a pas été finalisée dans le délai imparti."
        Send-MailMessage -SmtpServer $smtpServer -From $smtpFrom -To $smtpTo -Subject "Timeout de sauvegarde Confluence" -Body "La sauvegarde Confluence n'a pas été finalisée dans le délai d'une heure." -BodyAsHtml
        exit 1
    }
}

# La sauvegarde est prête, procéder au téléchargement
Write-Host "Sauvegarde finalisée! Début du téléchargement..."

try {
    # Identify file location to download
    $parseResults = $backupStatus.Content | ConvertFrom-Json
    $backupLocation = $parseResults.fileName

    # Download the backup file
    $backupUrl = "https://$domain/wiki/download/$backupLocation"
    $backupFilename = "confluence-backup-$(Get-Date -Format "yyyyMMdd-HHmm").zip"
    $fullBackupPath = "$destination$backupFilename"

    Write-Host "Téléchargement depuis: $backupUrl"
    Write-Host "Sauvegarde vers: $fullBackupPath"

    Invoke-WebRequest -Method Get -Uri $backupUrl -Headers $headers -OutFile $fullBackupPath

    # Vérifier que le fichier a été créé et n'est pas vide
    if (Test-Path $fullBackupPath) {
        $fileSize = (Get-Item $fullBackupPath).Length
        if ($fileSize -gt 0) {
            $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
            Write-Host "Sauvegarde réussie! Fichier: $backupFilename (Taille: $fileSizeMB MB)"

            # Send success email
            $emailSubject = "Sauvegarde Confluence reussie"
            $emailBody = @"
            <html>
            <body>
            <h3>Sauvegarde Confluence réussie</h3>
            <p>La sauvegarde Confluence s'est effectuee avec succes.</p>
            <p><strong>Nom du fichier:</strong> $backupFilename</p>
            <p><strong>Taille du fichier:</strong> $fileSizeMB MB</p>
            <p><strong>Emplacement:</strong> $fullBackupPath</p>
            <p><em>Sauvegarde effectuee le: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</em></p>
            </body>
            </html>
"@

            Send-MailMessage -SmtpServer $smtpServer -From $smtpFrom -To $smtpTo -Subject $emailSubject -Body $emailBody -BodyAsHtml

            Write-Host "=== SAUVEGARDE TERMINEE AVEC SUCCES ==="
        } else {
            throw "Le fichier telecharge est vide"
        }
    } else {
        throw "Le fichier de sauvegarde n'a pas été cree"
    }

} catch {
    Write-Host "Erreur lors du telechargement: $($_.Exception.Message)"

    # Send failure email
    $emailSubject = "Échec du téléchargement de sauvegarde Confluence"
    $emailBody = @"
    <html>
    <body>
    <h3>echec du telechargement de sauvegarde Confluence</h3>
    <p>La sauvegarde a ete creee avec succes sur Atlassian, mais le telechargement a echoue.</p>
    <p><strong>Erreur:</strong> $($_.Exception.Message)</p>
    <p><em>Tentative effectuee le: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</em></p>
    </body>
    </html>
"@

    Send-MailMessage -SmtpServer $smtpServer -From $smtpFrom -To $smtpTo -Subject $emailSubject -Body $emailBody -BodyAsHtml
    exit 1
}
