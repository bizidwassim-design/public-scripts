<#
.SYNOPSIS
    Triggers a Jira Cloud backup (with attachments), waits for completion, downloads the ZIP and emails the result.
.DESCRIPTION
    Calls the Jira Cloud backup REST endpoints (export/runbackup, lastTaskId, getProgress) with an
    API token, shows progress, downloads the ZIP to a local folder, purges backups older than
    120 days and sends a success or failure email. Meant to run weekly as a scheduled task.
    Warning: Atlassian changed the backup API in 2025; this script is kept for reference and may
    need the endpoints updated before use.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Atlassian API token (site admin) | SMTP relay | PowerShell 4+
    Impact      : Read-only on Jira (creates a backup export); deletes local backups older than 120 days
    License     : MIT
.EXAMPLE
    .\Backup-JiraCloud.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Configuration pour l'email
$smtpFrom = "jira-backup@contoso.com"
$smtpTo = "it-support@contoso.com"
$smtpServer = "smtp.contoso.com"
$smtpPort = 25
$smtpCredentialFile = "C:\Scripts\Backups\smtp.cred.xml"   # created once with: Get-Credential | Export-Clixml <file>
$smtpCredential = if (Test-Path $smtpCredentialFile) { Import-Clixml $smtpCredentialFile } else { Get-Credential -Message "SMTP relay account" }

# Atlassian site and credentials
$account     = 'contoso'                    # https://<account>.atlassian.net
$username    = 'admin@contoso.com'
$token       = '<API-KEY>'
$destination = 'C:\Scripts\Jira\Backup\'
$attachments = 'true'
$cloud       = 'true'
# -------------------------------------------------------------------------

$today       = Get-Date -format yyyyMMdd-HHmm
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

if(!(Test-Path -path $destination)){
    Write-Host "Folder is not present, creating folder"
    mkdir $destination
} else {
    Write-Host "Path is already present"
}

# Supprimer les fichiers de plus de 3 mois
$files = Get-ChildItem -Path $destination -File
foreach ($file in $files) {
    $fileAge = (Get-Date) - $file.CreationTime
    if ($fileAge.Days -gt 120) {
        Write-Host "Suppression du fichier ancien : $($file.Name)"
        Remove-Item -Path $file.FullName -Force
    }
}

function ConvertTo-Base64($string) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($string);
    $encoded = [System.Convert]::ToBase64String($bytes);
    return $encoded;
}

$b64 = ConvertTo-Base64($username + ":" + $token);
$auth = $b64;

$body = @{
    cbAttachments=$attachments
    exportToCloud=$cloud
}
$bodyjson = $body | ConvertTo-Json

if ($PSVersionTable.PSVersion.Major -lt 4) {
    throw "Script requires at least PowerShell version 4. Get it here: https://www.microsoft.com/en-us/download/details.aspx?id=40855"
}

[string]$ContentType = "application/json"
[string]$URI = "https://$account.atlassian.net/rest/backup/1/export/runbackup"

$header = @{
    "Authorization" = "Basic "+$auth
    "Content-Type"="application/json"
}

try {
    $InitiateBackup = Invoke-RestMethod -Method Post -Headers $header -Uri $URI -ContentType $ContentType -Body $bodyjson -Verbose
} catch {
    $InitiateBackup = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($InitiateBackup)
    $reader.BaseStream.Position = 0
    $reader.DiscardBufferedData()
    $responseBody = $reader.ReadToEnd();
    $errorMessage = "Backup initiation failed: $responseBody"

    # Envoi d'un email en cas d'échec
    Send-MailMessage -From $smtpFrom -To $smtpTo -Subject "Échec de la sauvegarde Jira" -Body $errorMessage -SmtpServer $smtpServer -Port $smtpPort -Credential $smtpCredential -UseSsl
    throw $errorMessage
}

$GetBackupID = Invoke-WebRequest -Method Get -Headers $header "https://$account.atlassian.net/rest/backup/1/export/lastTaskId"
$LatestBackupID = $GetBackupID.content

do {
    $status = Invoke-RestMethod -Method Get -Headers $header -Uri "https://$account.atlassian.net/rest/backup/1/export/getProgress?taskId=$LatestBackupID"
    $statusoutput = $status.result

    if ($status.progress -match "(\d+)") {
        $percentage = $Matches[1]
        if ([int]$percentage -gt 100) {
            $percentage = "100"
        }
        Write-Progress -Activity 'Creating backup' -Status $status.progress -PercentComplete $percentage
    }
    Start-Sleep -Seconds 5
} while ($status.status -ne 'Success')

if ([bool]($status.PSObject.Properties.Name -match "failedMessage")) {
    $errorMessage = "Backup failed: $status.failedMessage"
    Send-MailMessage -From $smtpFrom -To $smtpTo -Subject "Échec de la sauvegarde Jira" -Body $errorMessage -SmtpServer $smtpServer -Port $smtpPort
    throw $errorMessage
}

$BackupDetails = $status.result
$BackupURI = "https://$account.atlassian.net/plugins/servlet/$BackupDetails"

Invoke-WebRequest -Method Get -Headers $header -Uri $BackupURI -OutFile (Join-Path -Path $destination -ChildPath "JIRA-backup-$today.zip")

# Envoi d'un email en cas de succès
$successMessage = "La sauvegarde Jira a été complétée avec succès. Le fichier se trouve à : $destination"
Send-MailMessage -From $smtpFrom -To $smtpTo -Subject "Succès de la sauvegarde Jira" -Body $successMessage -SmtpServer $smtpServer -Port $smtpPort
