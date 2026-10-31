<#
.SYNOPSIS
    Exports Entra ID sign-ins from outside the organisation's home countries over the last N days.
.DESCRIPTION
    Queries Microsoft Graph auditLogs/signIns (with pagination) for sign-ins whose country is not in
    the home-country list, exports every record to a timestamped CSV and prints summaries by
    country, by user, top user/country combinations and failed sign-ins by country.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Microsoft.Graph (Connect-MgGraph with AuditLog.Read.All, Directory.Read.All) | Entra ID P1/P2 for sign-in logs
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ForeignSignIns.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$HomeCountries = @('CA', 'US')          # ISO country codes considered "home" (excluded from the report)
$DaysBack      = 90                     # how far back to query
$OutputDir     = "C:\Scripts\Reports"   # where the CSV is written
# -------------------------------------------------------------------------

# Already connected to Microsoft Graph? Otherwise uncomment:
# Connect-MgGraph -Scopes "AuditLog.Read.All", "Directory.Read.All"

# Calculate start date
$startDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "Querying sign-ins from the last $DaysBack days (excluding $($HomeCountries -join ', '))..." -ForegroundColor Cyan
Write-Host "Start Date: $startDate" -ForegroundColor Yellow

# Query sign-ins excluding the home countries
$countryFilter = ($HomeCountries | ForEach-Object { "location/countryOrRegion ne '$_'" }) -join ' and '
$uri = "https://graph.microsoft.com/v1.0/auditLogs/signIns?`$filter=createdDateTime ge $startDate and $countryFilter"

$allSignIns = @()
$response = Invoke-MgGraphRequest -Uri $uri -Method GET

$allSignIns += $response.value
Write-Host "Fetched page 1 - Records: $($response.value.Count)" -ForegroundColor Yellow

# Handle pagination
$pageCount = 1
while ($response.'@odata.nextLink') {
    $pageCount++
    Write-Host "Fetching page $pageCount..." -ForegroundColor Yellow
    $response = Invoke-MgGraphRequest -Uri $response.'@odata.nextLink' -Method GET
    $allSignIns += $response.value
    Write-Host "  Page $pageCount - Records: $($response.value.Count) | Total so far: $($allSignIns.Count)" -ForegroundColor Yellow
}

Write-Host "`nTotal sign-ins found: $($allSignIns.Count)" -ForegroundColor Green

# Ensure output directory exists
if (!(Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
    Write-Host "Created $OutputDir directory" -ForegroundColor Yellow
}

# Export to CSV with Country column
$exportPath = Join-Path $OutputDir "ForeignSignIns_Last${DaysBack}Days_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

$allSignIns | Select-Object `
    createdDateTime,
    userPrincipalName,
    @{N='Country';E={$_.location.countryOrRegion}},
    @{N='City';E={$_.location.city}},
    @{N='State';E={$_.location.state}},
    ipAddress,
    appDisplayName,
    @{N='Status';E={$_.status.errorCode}},
    @{N='StatusDetails';E={$_.status.failureReason}},
    @{N='OS';E={$_.deviceDetail.operatingSystem}},
    @{N='Browser';E={$_.deviceDetail.browser}},
    @{N='IsInteractive';E={$_.isInteractive}},
    @{N='RiskLevel';E={$_.riskLevelDuringSignIn}},
    @{N='DeviceName';E={$_.deviceDetail.displayName}},
    @{N='DeviceId';E={$_.deviceDetail.deviceId}} |
    Export-Csv $exportPath -NoTypeInformation -Encoding UTF8

Write-Host "`n[OK] Exported to: $exportPath" -ForegroundColor Green
Write-Host "  Total records: $($allSignIns.Count)" -ForegroundColor Green

# Summary by Country
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "     SUMMARY BY COUNTRY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$countrySummary = $allSignIns | Group-Object {$_.location.countryOrRegion} |
    Select-Object @{N='Country';E={$_.Name}}, Count |
    Sort-Object Count -Descending

$countrySummary | Format-Table -AutoSize
Write-Host "Total Countries: $($countrySummary.Count)" -ForegroundColor Yellow

# Summary by User
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "     SUMMARY BY USER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$userSummary = $allSignIns | Group-Object userPrincipalName |
    Select-Object Name, Count |
    Sort-Object Count -Descending

$userSummary | Format-Table -AutoSize
Write-Host "Total Users: $($userSummary.Count)" -ForegroundColor Yellow

# Summary by Country and User (Top 20)
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "     TOP 20 USER/COUNTRY COMBINATIONS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$allSignIns | Group-Object userPrincipalName, {$_.location.countryOrRegion} |
    Select-Object @{N='User';E={$_.Group[0].userPrincipalName}},
                  @{N='Country';E={$_.Group[0].location.countryOrRegion}},
                  Count |
    Sort-Object Count -Descending |
    Select-Object -First 20 |
    Format-Table -AutoSize

# Failed sign-ins summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "     FAILED SIGN-INS BY COUNTRY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$failedSignIns = $allSignIns | Where-Object {$_.status.errorCode -ne 0}
if ($failedSignIns.Count -gt 0) {
    $failedSignIns | Group-Object {$_.location.countryOrRegion} |
        Select-Object @{N='Country';E={$_.Name}}, Count |
        Sort-Object Count -Descending |
        Format-Table -AutoSize
    Write-Host "Total Failed Sign-ins: $($failedSignIns.Count)" -ForegroundColor Red
} else {
    Write-Host "No failed sign-ins found." -ForegroundColor Green
}

Write-Host "`n[OK] Done!" -ForegroundColor Green
Write-Host "`nCSV File Location: $exportPath" -ForegroundColor White -BackgroundColor DarkGreen
