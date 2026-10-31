<#
.SYNOPSIS
    Monthly report of Exchange Online mailboxes that have a forwarding address configured.
.DESCRIPTION
    Connects to Exchange Online, selects mailboxes with ForwardingAddress or ForwardingSmtpAddress set,
    exports Name / forwarding targets / DeliverToMailboxAndForward to CSV and emails an HTML summary
    with the CSV attached. Sends nothing when no forwarding is found.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ExchangeOnlineManagement
    Impact      : Read-only (sends an email)
    License     : MIT
.EXAMPLE
    .\Get-MailboxForwarding.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$CsvFileName  = "C:\Scripts\Reports\ForwardingReport.csv"
$smtpServer   = "smtp.contoso.com"
$from         = "it-support@contoso.com"
$emailaddress = "it-support@contoso.com"
$Bcc          = "security@contoso.com"
$subject      = "Monthly Forwarding Rule Report"
$TeamName     = "The Contoso Cybersecurity Team"
# -------------------------------------------------------------------------

# Import Exchange Online Module and connect
Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline

# Get mailboxes with forwarding rules and store them in a variable
$forwardingReport = Get-Mailbox -ResultSize Unlimited |
    Where {($_.ForwardingAddress -ne $Null) -or ($_.ForwardingsmtpAddress -ne $Null) -and ($_.DeliverToMailboxAndForward -eq $true)} |
    Select Name, ForwardingAddress, ForwardingsmtpAddress, DeliverToMailboxAndForward

# Check if the result is empty
if ($forwardingReport.Count -eq 0) {
    Write-Host "No forwarding rules found. No email will be sent."
    return
}

# Export the report to a CSV file
$forwardingReport | Export-Csv -Path $CsvFileName -NoTypeInformation

# Generate HTML table for the email body
$tableRows = $forwardingReport | ForEach-Object {
    "<tr><td>$($_.Name)</td><td>$($_.ForwardingAddress)</td><td>$($_.ForwardingsmtpAddress)</td><td>$($_.DeliverToMailboxAndForward)</td></tr>"
}

$htmlTable = @"
<table border="1">
    <thead>
        <tr>
            <th>Name</th>
            <th>Forwarding Address</th>
            <th>Forwarding SMTP Address</th>
            <th>Deliver To Mailbox And Forward</th>
        </tr>
    </thead>
    <tbody>
        $($tableRows -join "`n")
    </tbody>
</table>
"@

# Define the email body
$body = @"
   <p>Hello Team,</p>
   <p>Attached, you will find the latest report on mailboxes with active forwarding rules.</p>
   <p>This report includes details about the forward addresses and the mailboxes they belong to. Please review the information to ensure everything is in compliance.</p>
   <p>Here is the forwarding rule summary:</p>
   $htmlTable
   <p>Best regards,<br>
   $TeamName</p>
"@

# Attach the CSV report to the email
$attachment = $CsvFileName

# Send the email with the report attached and the forwarding rules displayed in the body
try {
    Send-MailMessage -smtpServer $smtpServer `
                     -from $from `
                     -to $emailaddress `
                     -Bcc $Bcc `
                     -subject $subject `
                     -body $body `
                     -bodyasHTML `
                     -priority High `
                     -Encoding ([System.Text.Encoding]::UTF8) `
                     -Attachment $attachment
    Write-Host "Email sent successfully."
} catch {
    Write-Host "Error sending the email: $_"
}
