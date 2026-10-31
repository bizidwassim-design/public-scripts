<#
.SYNOPSIS
    Lists Kerberos/NTLM authentication events (4768/4769/4770/4771/4776) from a DC Security log in a time window.
.DESCRIPTION
    Queries the Security log (or an archived .evtx) for the Kerberos authentication event IDs
    between a start and end time, filters the message with a wildcard substring (e.g. a
    pre-authentication type, an account, a hostname or an IP) and prints TimeCreated, ID and
    the full message to the console.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin on a domain controller (or access to an exported .evtx)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-KerberosAuthEvents.ps1
#>

# Check recent Kerberos authentication events

# Event IDs:
# 4768 TGT request
# 4769 Service ticket
# 4770 TGT renewal
# 4771 Kerberos pre-authentication failed
# 4776 NTLM credential validation

# ---- EDIT ME ------------------------------------------------------------
$eventIDs  = 4768, 4769, 4770, 4771, 4776
$logName   = 'Security'
#$logPath  = 'C:\Scripts\Archive-Security.evtx'              # uncomment (and the Path line below) to read an archived log
$startTime = (Get-Date "2025-12-21 00:00:00")
$endTime   = (Get-Date "2025-12-21 06:00:00")
# Wildcard substring to look for in the event message. Examples:
#$substringToFind = "*<CERTIFICATE-THUMBPRINT>*"
#$substringToFind = "*DC01*"
#$substringToFind = "*192.0.2.10*"
#$substringToFind = "*jdoe*"
$substringToFind = "*Pre-Authentication Type:	16*"
# -------------------------------------------------------------------------

$filter = @{
    LogName = $logName
#    Path = $logPath
    ID = $eventIDs
    StartTime = $startTime
    EndTime = $endTime
}

Get-WinEvent -FilterHashtable $filter |
    Where-Object { $_.Message -like $substringToFind } |
    Select-Object TimeCreated, ID, Message |
    Format-List
