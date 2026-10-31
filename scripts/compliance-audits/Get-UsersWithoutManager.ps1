<#
.SYNOPSIS
    Monthly check: enabled AD user accounts that have no Manager attribute defined.
.DESCRIPTION
    Lists enabled users of a given OU whose Manager attribute is empty (excluding admin / test /
    support accounts and users tagged in extensionAttribute13), exports them to a CSV and emails
    the report to the IT team only when at least one account is found.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | SMTP relay
    Impact      : Read-only (sends an email)
    License     : MIT
.EXAMPLE
    .\Get-UsersWithoutManager.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$ouPath       = "OU=Users,DC=corp,DC=contoso,DC=local"
$outputCsv    = "C:\Scripts\Reports\UsersWithoutManager.csv"
$smtpServer   = "smtp.contoso.com"
$from         = "it-support@contoso.com"
$emailaddress = "it-support@contoso.com"
$Bcc          = "security@contoso.com"
$ExcludedUpn  = "user@contoso.com"      # one-off exception (e.g. the CEO)
# -------------------------------------------------------------------------

# Import the Active Directory module
Import-Module ActiveDirectory

# Get all active user accounts (enabled) in the specified OU that do not have the 'Manager' attribute defined
$usersWithoutManager = Get-ADUser -Filter {Enabled -eq $true -and (SamAccountName -notlike "*admin*" -and SamAccountName -notlike "*test*" -and SamAccountName -notlike "*support*")} `
    -SearchBase $ouPath -Properties Manager, DisplayName, SamAccountName, UserPrincipalName, Enabled, extensionAttribute13 | Where-Object { $_.Manager -eq $null -and $_.extensionAttribute13 -eq $null -and $_.UserPrincipalName -ne $ExcludedUpn }

# Check if any users were found
if ($usersWithoutManager) {
    # Select relevant properties and add the 'Manager' column with the value 'Not Defined'
    $usersWithoutManager | Select-Object DisplayName, SamAccountName, UserPrincipalName, Enabled, @{Name='Manager';Expression={'Not Defined'}} |
        Export-Csv -Path $outputCsv -NoTypeInformation

    Write-Output "Exported users without a manager to $outputCsv"

    # Define the email details
    $subject = "Monthly Check: Accounts Without Defined Manager"
    $body = @"
    <p>Hello Team,</p>
    <p>Attached, you will find the monthly report for Active Directory (AD) regarding accounts without a defined manager.</p>
    <p>This report covers user accounts that currently do not have a manager assigned.</p>
    <p>Please note that the <strong>fifth column</strong> of the report highlights a total of <strong>$($usersWithoutManager.Count)</strong> users without a manager.</p>
    <p> Please define the manager information in Active Directory. I kindly request that you review these details carefully and take the appropriate actions to ensure system compliance and security.</p>
    <p>Thank you for your prompt attention to this matter.</p>
    <p>Best regards,<br>
    The Contoso Cybersecurity Team</p>
"@

    # Attach the CSV report to the email
    $attachment = $outputCsv

    # Only send the email if there are users without a manager
    if ($usersWithoutManager.Count -gt 0) {
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

        # Open the CSV file after creation
        Start-Process $outputCsv
    } else {
        Write-Output "No active users without a defined manager were found, so no email will be sent."
    }
} else {
    Write-Output "No active users without a defined manager were found in the specified OU."
}
