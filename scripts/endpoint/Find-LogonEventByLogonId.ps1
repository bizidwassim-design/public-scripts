<#
.SYNOPSIS
    Finds Security log logon events (4624) matching a given Logon ID and prints the logon details.
.DESCRIPTION
    Queries the local Security log for event 4624, filters on the Logon ID (hex, e.g. 0x3e7),
    parses the event XML and prints subject/target account and domain, logon type, workstation,
    source IP and process for each match. Useful to trace back a session seen in another event.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin (Security log read)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Find-LogonEventByLogonId.ps1 -LogonId "0x3e7"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$LogonId
)

# Ensure script is run with admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "This script requires administrator privileges to read the Security log."
    exit
}

Write-Host "Searching for Logon ID: $LogonId" -ForegroundColor Cyan

try {
    # Query Security log for logon events (Event ID 4624)
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        Id = 4624
    } -ErrorAction Stop | Where-Object {
        $_.Message -match "Logon ID:\s+$([regex]::Escape($LogonId))"
    }

    if ($events) {
        Write-Host "`nFound $($events.Count) matching event(s):" -ForegroundColor Green

        foreach ($event in $events) {
            Write-Host "`n================================================" -ForegroundColor Yellow
            Write-Host "Time Created: $($event.TimeCreated)"
            Write-Host "Event ID: $($event.Id)"
            Write-Host "Record ID: $($event.RecordId)"

            # Parse event properties
            $xml = [xml]$event.ToXml()
            $eventData = $xml.Event.EventData.Data

            Write-Host "`nLogon Details:"
            Write-Host "  Subject Account: $($eventData | Where-Object {$_.Name -eq 'SubjectUserName'} | Select-Object -ExpandProperty '#text')"
            Write-Host "  Subject Domain: $($eventData | Where-Object {$_.Name -eq 'SubjectDomainName'} | Select-Object -ExpandProperty '#text')"
            Write-Host "  Target Account: $($eventData | Where-Object {$_.Name -eq 'TargetUserName'} | Select-Object -ExpandProperty '#text')"
            Write-Host "  Target Domain: $($eventData | Where-Object {$_.Name -eq 'TargetDomainName'} | Select-Object -ExpandProperty '#text')"
            Write-Host "  Logon Type: $($eventData | Where-Object {$_.Name -eq 'LogonType'} | Select-Object -ExpandProperty '#text')"
            Write-Host "  Logon ID: $($eventData | Where-Object {$_.Name -eq 'TargetLogonId'} | Select-Object -ExpandProperty '#text')"
            Write-Host "  Workstation: $($eventData | Where-Object {$_.Name -eq 'WorkstationName'} | Select-Object -ExpandProperty '#text')"
            Write-Host "  Source IP: $($eventData | Where-Object {$_.Name -eq 'IpAddress'} | Select-Object -ExpandProperty '#text')"
            Write-Host "  Process: $($eventData | Where-Object {$_.Name -eq 'ProcessName'} | Select-Object -ExpandProperty '#text')"
        }
    } else {
        Write-Host "`nNo events found matching Logon ID: $LogonId" -ForegroundColor Yellow
    }
} catch {
    Write-Error "Error querying Security log: $_"
}
