<#
.SYNOPSIS
    Roll back Block-SendersFromList: remove listed sender addresses from the Tenant Allow/Block List.
.DESCRIPTION
    Reads one email address per line from a text file, finds the matching block-list entry and removes
    it with Remove-TenantAllowBlockListItems. Requires PowerShell 7 and an Exchange Online session.
    Note: the original uses -ListType BulkSender; change it to Sender if the entries were created
    as Sender blocks.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ExchangeOnlineManagement | PowerShell 7 | Security Administrator role
    Impact      : Modifies Exchange Online (tenant block list)
    License     : MIT
.EXAMPLE
    .\Unblock-SendersFromList.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$AdminUpn    = "admin@contoso.com"
$txtFilePath = "C:\Scripts\Input\Legit_Sender.txt"   # one sender address per line
# -------------------------------------------------------------------------

# Connect to Exchange Online (Run this first if not already connected)
Connect-ExchangeOnline -UserPrincipalName $AdminUpn

# Check if the file exists
if (-Not (Test-Path $txtFilePath)) {
    Write-Host "File not found: $txtFilePath" -ForegroundColor Red
    exit
}

# Read the email addresses from the file
$spammerEmails = Get-Content $txtFilePath

# Loop through each email and unblock it
foreach ($email in $spammerEmails) {
    try {
        # Get the ID associated with the email
        $entry = Get-TenantAllowBlockListItems -ListType BulkSender | Where-Object { $_.Value -eq $email }

        if ($entry) {
            # Remove the email from the block list using its ID
            Remove-TenantAllowBlockListItems -Ids $entry.Identity -ListType BulkSender
            Write-Host "Unblocked: $email" -ForegroundColor Green
        } else {
            Write-Host "No block entry found for: $email" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "Failed to unblock: $email" -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
}

Write-Host "Process completed!" -ForegroundColor Cyan
