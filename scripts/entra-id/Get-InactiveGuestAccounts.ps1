<#
.SYNOPSIS
    Deep inactivity analysis of Entra ID guest accounts (audit log, mail flow, group membership).
.DESCRIPTION
    For every guest: last Unified Audit Log event (UserLoggedIn / SecureLinkUsed / TeamsSessionStarted),
    number of emails received in the last N days (message trace), M365 group memberships and account age.
    A guest is flagged Inactive when older than the threshold and member of no M365 group.
    Writes GuestActivity.csv (full report) and InactiveGuests.csv (ObjectId, Name, UPN, Age) and prints stats.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Microsoft.Graph.Authentication | Microsoft.Graph.Users | ExchangeOnlineManagement (connected)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-InactiveGuestAccounts.ps1 -InactiveDaysThreshold 365 -AuditLogLookbackDays 90
#>

[CmdletBinding()]
param (
    [Parameter()]
    [int]$InactiveDaysThreshold = 365,

    [Parameter()]
    [int]$AuditLogLookbackDays = 90,

    [Parameter()]
    [int]$EmailLookbackDays = 10,

    [Parameter()]
    [string]$OutputPath = "$env:USERPROFILE\Documents\GuestAudit"
)

function Test-ModuleAvailable {
    param (
        [string]$ModuleName
    )

    $module = Get-Module -Name $ModuleName -ListAvailable
    return $null -ne $module
}

function Initialize-Requirements {
    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Users',
        'ExchangeOnlineManagement'
    )

    foreach ($module in $requiredModules) {
        if (-not (Test-ModuleAvailable -ModuleName $module)) {
            Write-Host "Required module '$module' is not installed. Please install it using:" -ForegroundColor Yellow
            Write-Host "Install-Module $module" -ForegroundColor Cyan
            throw "Missing required module: $module"
        }
    }
}

function Get-GuestActivity {
    param (
        [Parameter(Mandatory)]
        $Guest,
        [datetime]$AuditStartDate,
        [datetime]$EmailStartDate,
        [datetime]$EndDate
    )

    # Get audit records
    $auditRecord = $null
    try {
        $auditRecord = Search-UnifiedAuditLog -UserIds $Guest.Mail, $Guest.UserPrincipalName `
            -Operations UserLoggedIn, SecureLinkUsed, TeamsSessionStarted `
            -StartDate $AuditStartDate -EndDate $EndDate -ResultSize 1 |
            Select-Object -First 1
    }
    catch {
        Write-Verbose "Unable to get audit logs for user $($Guest.UserPrincipalName): $_"
    }

    $lastAuditRecord = if ($auditRecord) { $auditRecord.CreationDate } else { "None found" }
    $lastAuditAction = if ($auditRecord) { $auditRecord.Operations } else { "N/A" }

    # Get email activity
    $emailCount = 0
    if ($Guest.Mail) {
        try {
            $emailCount = @(Get-MessageTrace -StartDate $EmailStartDate -EndDate $EndDate -Recipient $Guest.Mail).Count
        }
        catch {
            Write-Verbose "Unable to get message trace for user $($Guest.Mail): $_"
        }
    }

    # Get group memberships
    $groups = @()
    try {
        $groups = Get-MgUserMemberOf -UserId $Guest.Id -All |
            Where-Object { $_.AdditionalProperties.groupTypes -eq 'Unified' } |
            Select-Object -ExpandProperty AdditionalProperties |
            Select-Object -ExpandProperty displayName
    }
    catch {
        Write-Verbose "Unable to get group memberships for user $($Guest.UserPrincipalName): $_"
    }

    return @{
        LastAuditRecord = $lastAuditRecord
        LastAuditAction = $lastAuditAction
        EmailCount = $emailCount
        Groups = if ($groups) { $groups -join ", " } else { "" }
    }
}

# Main script execution
try {
    Initialize-Requirements

    # Create output directory if it doesn't exist
    if (!(Test-Path -Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $startDate = (Get-Date).AddDays(-$AuditLogLookbackDays)
    $emailStartDate = (Get-Date).AddDays(-$EmailLookbackDays)
    $endDate = Get-Date

    Write-Host "Fetching guest accounts..." -ForegroundColor Cyan
    $guests = Get-MgUser -Filter "userType eq 'Guest'" -All -Property id,
        userPrincipalName, displayName, createdDateTime, mail |
        Sort-Object DisplayName

    if (!$guests) {
        throw "No guest accounts found"
    }

    $report = [System.Collections.Generic.List[object]]::new()
    $stats = @{
        TotalGuests = $guests.Count
        ActiveGuests = 0
        AuditRecords = 0
        EmailActive = 0
        Domains = @{}
    }

    $guestCount = 0
    foreach ($guest in $guests) {
        $guestCount++
        Write-Progress -Activity "Analyzing Guest Accounts" -Status "Processing $($guest.DisplayName)" -PercentComplete (($guestCount / $guests.Count) * 100)

        $activity = Get-GuestActivity -Guest $guest -AuditStartDate $startDate `
            -EmailStartDate $emailStartDate -EndDate $endDate

        if ($guest.Mail) {
            $domain = ($guest.Mail -split '@')[1]
            if ($stats.Domains.ContainsKey($domain)) {
                $stats.Domains[$domain] += 1
            } else {
                $stats.Domains[$domain] = 1
            }
        }

        $accountAge = (New-TimeSpan -Start $guest.CreatedDateTime).Days
        $isInactive = $accountAge -gt $InactiveDaysThreshold -and !$activity.Groups

        if ($activity.LastAuditRecord -ne "None found") { $stats.AuditRecords++ }
        if ($activity.EmailCount -gt 0) { $stats.EmailActive++ }
        if (!$isInactive) { $stats.ActiveGuests++ }

        $report.Add([PSCustomObject]@{
            Guest = $guest.Mail
            Name = $guest.DisplayName
            Domain = if ($guest.Mail) { ($guest.Mail -split '@')[1] } else { "N/A" }
            Inactive = $isInactive
            Created = $guest.CreatedDateTime
            AgeInDays = $accountAge
            EmailCount = $activity.EmailCount
            'Last Audit record' = $activity.LastAuditRecord
            'Last Audit action' = $activity.LastAuditAction
            'Member of' = $activity.Groups
            UPN = $guest.UserPrincipalName
            ObjectId = $guest.Id
        })
    }

    # Export reports
    $reportPath = Join-Path $OutputPath "GuestActivity.csv"
    $inactivePath = Join-Path $OutputPath "InactiveGuests.csv"

    $report | Sort-Object Name | Export-Csv -Path $reportPath -NoTypeInformation
    $report | Where-Object { $_.Inactive } |
        Select-Object ObjectId, Name, UPN, AgeInDays |
        Export-Csv -Path $inactivePath -NoTypeInformation

    # Display statistics
    $topDomain = $stats.Domains.GetEnumerator() |
        Sort-Object Value -Descending |
        Select-Object -First 1

    Write-Host "`nGuest Account Statistics" -ForegroundColor Green
    Write-Host "----------------------" -ForegroundColor Green
    @{
        'Total Guest Accounts' = $stats.TotalGuests
        'Active Guests' = $stats.ActiveGuests
        'Inactive Guests' = ($stats.TotalGuests - $stats.ActiveGuests)
        'Percent Inactive' = "{0:P2}" -f (($stats.TotalGuests - $stats.ActiveGuests) / $stats.TotalGuests)
        'Audit Records Found' = $stats.AuditRecords
        'Email Active' = $stats.EmailActive
        'Unique Domains' = $stats.Domains.Count
        'Top Domain' = if ($topDomain) { "$($topDomain.Key) ($($topDomain.Value) guests)" } else { "N/A" }
    }.GetEnumerator() | ForEach-Object {
        Write-Host ("{0,-25} : {1}" -f $_.Key, $_.Value)
    }

    Write-Host "`nReport files saved to: $OutputPath" -ForegroundColor Cyan
}
catch {
    Write-Error "Error occurred: $_"
    throw
}

start $OutputPath
