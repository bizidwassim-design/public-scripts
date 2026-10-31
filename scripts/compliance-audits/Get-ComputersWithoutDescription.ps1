<#
.SYNOPSIS
    Monthly check: enabled AD computer objects that have no Description (owner) defined.
.DESCRIPTION
    Lists enabled computers of the workstation OU whose Description attribute is empty, exports
    them to a CSV, purges report files older than 3 months and emails the report (with the count)
    to the IT team when at least one computer is found.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | SMTP relay
    Impact      : Read-only (deletes its own old CSV reports, sends an email)
    License     : MIT
.EXAMPLE
    .\Get-ComputersWithoutDescription.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$OUPath     = "OU=Workstations,DC=corp,DC=contoso,DC=local"
$ExportDir  = "C:\Scripts\ComputerWithoutDescription\Log"
$SmtpServer = "smtp.contoso.com"
$From       = "it-support@contoso.com"
$To         = "it-support@contoso.com"
$Bcc        = "security@contoso.com"
# -------------------------------------------------------------------------

# Import the Active Directory module
Import-Module ActiveDirectory

$ExportPath = Join-Path $ExportDir "ExportFile.csv"

# Create the export directory if it doesn't exist
if (-not (Test-Path -Path $ExportDir)) {
    New-Item -ItemType Directory -Path $ExportDir | Out-Null
}

# Get all active computer objects in the specified OU without a description
$Computers = Get-ADComputer -Filter {(Enabled -eq $true) -and (Description -notlike "*")} -SearchBase $OUPath -Properties Name, DistinguishedName, Enabled, Description

# Export the results to a CSV file
$Computers | Select-Object Name, DistinguishedName, Enabled, Description | Export-Csv -Path $ExportPath -NoTypeInformation

# Display the number of computers found and the export file path
$ComputerCount = $Computers.Count
Write-Host "Found $ComputerCount active computers without a description."
Write-Host "Results exported to: $ExportPath"

# Delete CSV files older than 3 months
$OldFiles = Get-ChildItem -Path $ExportDir -Filter "*.csv" | Where-Object { $_.LastWriteTime -lt (Get-Date).AddMonths(-3) }

if ($OldFiles) {
    foreach ($file in $OldFiles) {
        Remove-Item $file.FullName -Force
        Write-Host "Deleted old file: $($file.Name)"
    }
} else {
    Write-Host "No CSV files older than 3 months found."
}

# Email settings
$Subject = "Monthly Check: computers Without Defined Owner"
$Body = @"
<html>
<body>
<p>Hello Team,</p>
<p>Attached, you will find the monthly report for Active Directory (AD) regarding computers without a defined owner.</p>
<p>This report covers computers objects that currently do not have a owner assigned.</p>
<p>Please note that the <strong>fourth column</strong> of the report highlights a total of <strong>$ComputerCount</strong> computers without a defined owner.</p>
<p>Please define the manager information in Active Directory. I kindly request that you review these details carefully and take the appropriate actions to ensure system compliance.</p>
<p>Thank you for your prompt attention to this matter.</p>
<p>Best regards,<br> The Contoso Cybersecurity Team</p>
</body>
</html>
"@

# Check if the output file is not empty
if ($ComputerCount -gt 0) {
    # Send email with attachment
    try {
        $SmtpClient = New-Object Net.Mail.SmtpClient($SmtpServer)
        $MailMessage = New-Object System.Net.Mail.MailMessage($From, $To, $Subject, $Body)
        $MailMessage.IsBodyHtml = $true
        $MailMessage.Bcc.Add($Bcc)
        $MailMessage.Attachments.Add($ExportPath)

        $SmtpClient.Send($MailMessage)

        Write-Host "Email sent successfully with the attachment."
    }
    catch {
        Write-Host "Failed to send email: $_"
    }
    finally {
        if ($null -ne $MailMessage) {
            $MailMessage.Dispose()
        }
        if ($null -ne $SmtpClient) {
            $SmtpClient.Dispose()
        }
    }
} else {
    Write-Host "No computers without a defined owner found. No email sent."
}

Write-Host "Script execution completed."
