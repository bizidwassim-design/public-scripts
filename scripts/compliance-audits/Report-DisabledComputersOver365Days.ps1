<#
.SYNOPSIS
    Report AD computers disabled (no logon) for more than 365 days that could be deleted.
.DESCRIPTION
    Selects disabled AD computer objects whose LastLogonDate is older than $days, exports Name /
    LastLogonDate / Description to a CSV and emails an HTML table of the candidates to the IT team.
    No email is sent when nothing is found. The Description is only changed in the exported data,
    not in AD.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | SMTP relay
    Impact      : Read-only (sends an email)
    License     : MIT
.EXAMPLE
    .\Report-DisabledComputersOver365Days.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$days         = 365
$csvPath      = "C:\Scripts\Reports\DisabledComputersOnAD.csv"
$smtpServer   = "smtp.contoso.com"
$from         = "it-support@contoso.com"
$emailaddress = "it-support@contoso.com"
$Bcc          = "security@contoso.com"
# -------------------------------------------------------------------------

# Get the current date and calculate the cutoff date
$cutoffDate = (Get-Date).AddDays(-$days)

# Get all disabled AD computers that have not been enabled for more than 365 days
$disabledComputers = Get-ADComputer -Filter {Enabled -eq $false} -Property Enabled, LastLogonDate, Description |

# Filter out computers that have been disabled for more than 365 days
Where-Object { $_.LastLogonDate -lt $cutoffDate }

# Update the Description field to mention the computers could be deleted
$disabledComputers | ForEach-Object {
    $_.Description = "Disabled for more than 365 days, could be deleted permanently from AD."
}

# Export results to CSV
$disabledComputers | Select-Object Name, LastLogonDate, Description | Export-Csv -Path $csvPath -NoTypeInformation

# Prepare HTML tables for the email body
$disabledComputersTable = $disabledComputers | ForEach-Object {
    "<tr><td>$($_.Name)</td><td>$($_.LastLogonDate)</td><td>$($_.Description)</td></tr>"
}
$disabledComputersTable = "<table border='1'><thead><tr><th>Name</th><th>Last Logon Date</th><th>Description</th></tr></thead><tbody>$($disabledComputersTable -join "`n")</tbody></table>"

# Define the email details
$subject = "Disabled Computers Audit Report"
$body = @"
<p>Hello Team,</p>
<p>Attached, you will find the Disabled Computers Audit report for Active Directory.</p>

<p>The following computers have been disabled for more than 365 days and could be permanently deleted from AD:</p>

<h3>Disabled Computers in AD (Disabled for more than 365 days and could be deleted permanently):</h3>
$disabledComputersTable

<p>Thank you for your prompt attention to this matter.</p>
<p>Best regards,<br>The Contoso Cybersecurity Team</p>
"@

# Don't send email if no disabled computers are found
if ($disabledComputers.Count -ne 0) {
    # Send the email with the attachment and HTML body
    try {
        Send-MailMessage -SmtpServer $smtpServer `
                         -From $from `
                         -To $emailaddress `
                         -Bcc $Bcc `
                         -Subject $subject `
                         -Body $body `
                         -BodyAsHtml `
                         -Priority High `
                         -Encoding ([System.Text.Encoding]::UTF8) `
                         -Attachments $csvPath
        Write-Host "Email sent successfully."
    } catch {
        Write-Host "Error sending the email: $_"
    }
} else {
    Write-Host "No disabled computers found. Email not sent."
}

# Optional: Clean up the CSV file after sending the email
# Remove-Item -Path $csvPath
