<#
.SYNOPSIS
    Report enabled AD users missing department, employeeID, employeeNumber, manager or title, and email HR.
.DESCRIPTION
    Queries the corporate users OU (excluding admin/disabled/external OUs), exports the users whose
    HR attributes are empty to a timestamped CSV with "MISSING" markers, writes a log file and sends
    a French HTML compliance email (with statistics) to HR, Bcc security. Opens the CSV at the end.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only (sends an email)
    License     : MIT
.EXAMPLE
    .\Get-UsersWithMissingAttributes.ps1
#>

#Requires -Modules ActiveDirectory

[CmdletBinding()]
param()

# ---- EDIT ME ------------------------------------------------------------
$Config = @{
    # AD Configuration
    OUPath              = "OU=Corporate,OU=Users,DC=corp,DC=contoso,DC=local"
    ExcludedOUs         = @('OU=Admins', 'OU=Disabled', 'OU=External')

    # File Paths
    OutputDirectory     = "C:\Scripts\Reports"
    OutputFileName      = "Users_Missing_Attributes_{0:yyyyMMdd_HHmmss}.csv"
    LogFileName         = "Users_Missing_Attributes_{0:yyyyMMdd}.log"
    RetentionDays       = 90

    # Email Configuration
    SMTPServer          = "smtp.contoso.com"
    FromAddress         = "it-support@contoso.com"
    ToAddress           = "hr@contoso.com"
    BccAddress          = "security@contoso.com"
    EmailSubject        = "AD Compliance: Utilisateurs avec attributs manquants - {0:yyyy-MM-dd}"
    SecurityContact     = "security@contoso.com"
    OrgName             = "Contoso"
}
# -------------------------------------------------------------------------

#region Helper Functions
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Message = "",

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    if ([string]::IsNullOrWhiteSpace($Message)) {
        Write-Host ""
        return
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'Info'    { Write-Host $logEntry -ForegroundColor Cyan }
        'Warning' { Write-Warning $logEntry }
        'Error'   { Write-Host $logEntry -ForegroundColor Red }
        'Success' { Write-Host $logEntry -ForegroundColor Green }
    }

    try {
        Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log file: $_"
    }
}

function Get-UsersWithMissingAttributes {
    [CmdletBinding()]
    param()

    Write-Log "Querying Active Directory for users with missing attributes..." -Level Info

    try {
        $users = Get-ADUser -Filter 'Enabled -eq $true' `
            -SearchBase $Config.OUPath `
            -Properties department, employeeID, employeeNumber, manager, title, DistinguishedName, GivenName, Surname, Enabled, whenCreated `
            -ErrorAction Stop

        Write-Log "Retrieved $($users.Count) active users from AD" -Level Info

        # Filter users
        $filteredUsers = $users | Where-Object {
            $dn = $_.DistinguishedName
            $excluded = $false
            foreach ($ou in $Config.ExcludedOUs) {
                if ($dn -match [regex]::Escape($ou)) {
                    $excluded = $true
                    break
                }
            }

            -not $excluded -and (
                -not $_.department -or
                -not $_.employeeID -or
                -not $_.employeeNumber -or
                -not $_.manager -or
                -not $_.title
            )
        }

        Write-Log "Found $($filteredUsers.Count) users with missing attributes after filtering" -Level Info

        return $filteredUsers

    } catch {
        Write-Log "Error querying Active Directory: $_" -Level Error
        throw
    }
}

function Export-UserReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Users,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    Write-Log "Exporting report to: $OutputPath" -Level Info

    try {
        $exportData = $Users | Select-Object `
            @{N='CardAccessNumber';E={if($_.employeeID){$_.employeeID}else{'MISSING'}}},
            @{N='EmployeeNumber';E={if($_.employeeNumber){$_.employeeNumber}else{'MISSING'}}},
            SamAccountName,
            @{N='FirstName';E={$_.GivenName}},
            @{N='LastName';E={$_.Surname}},
            Name,
            @{N='Status';E={if($_.Enabled){'Enabled'}else{'Disabled'}}},
            @{N='Title';E={if($_.title){$_.title}else{'MISSING'}}},
            @{N='Department';E={if($_.department){$_.department}else{'MISSING'}}},
            @{N='Manager';E={if($_.manager){($_.manager -split ',')[0] -replace 'CN=',''}else{'MISSING'}}},
            @{N='CreatedDate';E={$_.whenCreated.ToString('yyyy-MM-dd')}},
            @{N='OUPath';E={$_.DistinguishedName -replace '^CN=.+?,(OU=.+)$','$1'}} |
        Sort-Object Name

        $exportData | ConvertTo-Csv -NoTypeInformation | Out-File -FilePath $OutputPath -Encoding UTF8 -ErrorAction Stop

        Write-Log "Report exported successfully: $($Users.Count) records" -Level Success
        return $exportData

    } catch {
        Write-Log "Error exporting report: $_" -Level Error
        throw
    }
}

function Send-ComplianceEmail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AttachmentPath,

        [Parameter(Mandatory = $true)]
        [array]$ReportData
    )

    Write-Log "Preparing to send email notification..." -Level Info

    $totalUsers = $ReportData.Count
    $emailSubject = $Config.EmailSubject -f (Get-Date)

    # Calculate statistics
    $missingDepartment = ($ReportData | Where-Object { $_.Department -eq 'MISSING' }).Count
    $missingCardAccess = ($ReportData | Where-Object { $_.CardAccessNumber -eq 'MISSING' }).Count
    $missingEmployeeNumber = ($ReportData | Where-Object { $_.EmployeeNumber -eq 'MISSING' }).Count
    $missingManager = ($ReportData | Where-Object { $_.Manager -eq 'MISSING' }).Count
    $missingTitle = ($ReportData | Where-Object { $_.Title -eq 'MISSING' }).Count

    $emailBody = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; line-height: 1.6; color: #333; }
        .header { background-color: #0066cc; color: white; padding: 20px; border-radius: 5px 5px 0 0; }
        .content { padding: 20px; background-color: #f9f9f9; }
        .highlight { background-color: #fff3cd; padding: 15px; border-left: 4px solid #ffc107; margin: 15px 0; }
        .footer { background-color: #e9ecef; padding: 15px; border-radius: 0 0 5px 5px; font-size: 0.9em; }
        .stats { background-color: #d1ecf1; padding: 10px; border-radius: 5px; margin: 10px 0; }
        table { border-collapse: collapse; width: 100%; margin: 15px 0; background-color: white; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #0066cc; color: white; }
        tr:hover { background-color: #f5f5f5; }
        .action-required { color: #d9534f; font-weight: bold; }
        .ok { color: #5cb85c; }
    </style>
</head>
<body>
    <div class="header">
        <h2>Rapport de conformité - Attributs utilisateurs AD</h2>
        <p>Généré le: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    </div>

    <div class="content">
        <p>Bonjour équipe RH,</p>

        <p>Voici le rapport de conformité des attributs des utilisateurs actifs dans Active Directory qui nécessite votre attention.</p>

        <div class="stats">
            <strong>Résumé du rapport:</strong><br>
            • Date du rapport: $(Get-Date -Format "yyyy-MM-dd")<br>
            • Nombre total d'utilisateurs avec attributs manquants: <strong class="action-required">$totalUsers</strong>
        </div>

        <table>
            <tr>
                <th>Attribut</th>
                <th>Manquants</th>
                <th>Statut</th>
            </tr>
            <tr>
                <td>Department</td>
                <td>$missingDepartment</td>
                <td>$(if ($missingDepartment -gt 0) { '<span class="action-required">Action requise</span>' } else { '<span class="ok">OK</span>' })</td>
            </tr>
            <tr>
                <td>Card Access Number (EmployeeID)</td>
                <td>$missingCardAccess</td>
                <td>$(if ($missingCardAccess -gt 0) { '<span class="action-required">Action requise</span>' } else { '<span class="ok">OK</span>' })</td>
            </tr>
            <tr>
                <td>Employee Number</td>
                <td>$missingEmployeeNumber</td>
                <td>$(if ($missingEmployeeNumber -gt 0) { '<span class="action-required">Action requise</span>' } else { '<span class="ok">OK</span>' })</td>
            </tr>
            <tr>
                <td>Manager</td>
                <td>$missingManager</td>
                <td>$(if ($missingManager -gt 0) { '<span class="action-required">Action requise</span>' } else { '<span class="ok">OK</span>' })</td>
            </tr>
            <tr>
                <td>Title</td>
                <td>$missingTitle</td>
                <td>$(if ($missingTitle -gt 0) { '<span class="action-required">Action requise</span>' } else { '<span class="ok">OK</span>' })</td>
            </tr>
        </table>

        <div class="highlight">
            <strong>Action requise</strong><br>
            <strong>$totalUsers</strong> compte(s) utilisateur(s) ont des attributs manquants dans Active Directory.
        </div>

        <p><strong>Instructions:</strong></p>
        <ol>
            <li>Ouvrir le fichier Excel en pièce jointe</li>
            <li>Compléter les informations manquantes (identifiées par "MISSING")</li>
            <li>Retourner le fichier complété à l'équipe TI à <a href="mailto:$($Config.SecurityContact)">$($Config.SecurityContact)</a></li>
        </ol>

        <p>Une fois le fichier reçu, nous procéderons à l'injection des informations mises à jour dans notre Active Directory.</p>

        <p>Merci de votre collaboration.</p>
    </div>

    <div class="footer">
        <p><strong>$($Config.OrgName) - Équipe Cybersécurité & TI</strong><br>
        Pour toute question: <a href="mailto:$($Config.SecurityContact)">$($Config.SecurityContact)</a></p>
        <p style="font-size: 0.85em; color: #666;">
        ID du rapport: $(New-Guid)<br>
        Version: 1.0
        </p>
    </div>
</body>
</html>
"@

    try {
        $mailParams = @{
            SmtpServer  = $Config.SMTPServer
            From        = $Config.FromAddress
            To          = $Config.ToAddress
            Bcc         = $Config.BccAddress
            Subject     = $emailSubject
            Body        = $emailBody
            BodyAsHtml  = $true
            Priority    = if ($totalUsers -gt 10) { "High" } else { "Normal" }
            Encoding    = [System.Text.Encoding]::UTF8
            Attachments = $AttachmentPath
            ErrorAction = 'Stop'
        }

        Send-MailMessage @mailParams

        Write-Log "Email sent successfully to $($Config.ToAddress)" -Level Success
        return $true

    } catch {
        Write-Log "Failed to send email: $_" -Level Error
        return $false
    }
}
#endregion

#region Main Execution
try {
    # Initialize
    $timestamp = Get-Date
    $script:LogFile = Join-Path -Path $Config.OutputDirectory -ChildPath ($Config.LogFileName -f $timestamp)
    $csvPath = Join-Path -Path $Config.OutputDirectory -ChildPath ($Config.OutputFileName -f $timestamp)

    # Ensure output directory exists
    if (-not (Test-Path -Path $Config.OutputDirectory)) {
        New-Item -Path $Config.OutputDirectory -ItemType Directory -Force | Out-Null
    }

    Write-Log "=====================================" -Level Info
    Write-Log "Users Missing Attributes Report - Starting" -Level Info
    Write-Log "=====================================" -Level Info

    # Get users with missing attributes
    $users = Get-UsersWithMissingAttributes

    if ($users.Count -gt 0) {
        # Export report
        $reportData = Export-UserReport -Users $users -OutputPath $csvPath

        # Send email
        $emailSuccess = Send-ComplianceEmail -AttachmentPath $csvPath -ReportData $reportData

        if ($emailSuccess) {
            Write-Log "Report completed - Email sent successfully" -Level Success
        }

        # Open CSV
        Invoke-Item $csvPath

    } else {
        Write-Log "No users with missing attributes found" -Level Success
    }

    Write-Log "=====================================" -Level Info
    Write-Log "Report Completed" -Level Info
    Write-Log "=====================================" -Level Info

} catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)" -Level Error
    exit 1
}
#endregion
