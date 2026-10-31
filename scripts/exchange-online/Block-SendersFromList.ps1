<#
.SYNOPSIS
    Block a list of sender addresses in the Exchange Online Tenant Allow/Block List.
.DESCRIPTION
    Reads one email address per line from a text file and creates a Block entry of type Sender
    for each one with New-TenantAllowBlockListItems. Requires PowerShell 7 and an Exchange Online
    session. Use Unblock-SendersFromList.ps1 to roll back.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ExchangeOnlineManagement | PowerShell 7 | Security Administrator role
    Impact      : Modifies Exchange Online (tenant block list)
    License     : MIT
.EXAMPLE
    .\Block-SendersFromList.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$AdminUpn    = "admin@contoso.com"
$txtFilePath = "C:\Scripts\Input\spammers.txt"   # one sender address per line
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

# Loop through each email and report as spam
foreach ($email in $spammerEmails) {
    try {
        # Report the spammer to Microsoft
        New-TenantAllowBlockListItems -Block -Entries $email -ListType Sender

        Write-Host "Reported and blocked: $email" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to report: $email" -ForegroundColor Red
        Write-Host $_.Exception.Message
    }
}

Write-Host "Process completed!" -ForegroundColor Cyan
