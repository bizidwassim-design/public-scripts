<#
.SYNOPSIS
    Purge a specific email (by sender and subject) from every mailbox in the tenant using a compliance search.
.DESCRIPTION
    Connects to Security & Compliance PowerShell, creates and starts a compliance search over all
    Exchange locations matching the sender/subject KQL query, waits for completion and then runs a
    SoftDelete purge action (HardDelete left commented). Typical use: phishing or mis-sent email recall.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ExchangeOnlineManagement | Compliance Search / eDiscovery Manager role
    Impact      : Modifies Exchange (soft-deletes matching messages from all mailboxes)
    License     : MIT
.EXAMPLE
    .\Remove-EmailFromAllMailboxes.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$SearchName   = "purge-email-001"
$SenderEmail  = "sender@example.com"
$SubjectText  = "Subject of the message to remove"     # wildcards (*) allowed
# -------------------------------------------------------------------------

install-Module ExchangeOnlineManagement
Import-Module ExchangeOnlineManagement
Connect-IPPSSession

$Search=New-ComplianceSearch -Name $SearchName -ExchangeLocation All -ContentMatchQuery "(From:$SenderEmail) AND (Subject:`"$SubjectText`")"

Start-ComplianceSearch -Identity $Search.Identity

Get-ComplianceSearch -Identity $SearchName | select status

do{$status = Get-ComplianceSearch -Identity $SearchName | select status}while ($status.status -notlike "Completed")

#New-ComplianceSearchAction -SearchName $SearchName -Purge -PurgeType HardDelete

New-ComplianceSearchAction -SearchName $SearchName -Purge -PurgeType SoftDelete

Get-ComplianceSearchAction -Identity "$($SearchName)_Purge" | select status
