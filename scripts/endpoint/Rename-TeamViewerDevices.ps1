<#
.SYNOPSIS
    Bulk-rename TeamViewer devices (alias) from an Excel sheet through the web API.
.DESCRIPTION
    Reads devices.xlsx (columns: "Device ID", "Current Name", "New Name") with ImportExcel and sends
    POST /api/v1/devices/<id> with {"alias": "<New Name>"} for every non-empty row.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ImportExcel | TeamViewer API script token (Computers & Contacts: edit)
    Impact      : Modifies TeamViewer (device aliases)
    License     : MIT
.EXAMPLE
    .\Rename-TeamViewerDevices.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$ApiToken      = "<API-KEY>"
$ExcelFilePath = "C:\Scripts\Input\devices.xlsx"   # columns: Device ID, Current Name, New Name
# -------------------------------------------------------------------------

# Install-Module -Name ImportExcel -Force -Scope CurrentUser
Import-Module ImportExcel

# Check if the Excel file exists
if (-Not (Test-Path $ExcelFilePath)) {
    Write-Host "Error: File '$ExcelFilePath' not found!" -ForegroundColor Red
    exit
}

# Import the Excel file
$DeviceList = Import-Excel -Path $ExcelFilePath

# Loop through each row and update device name
foreach ($Device in $DeviceList) {
    $DeviceId = $Device.'Device ID'
    $CurrentName = $Device.'Current Name'
    $NewName = $Device.'New Name'

    # Skip empty rows
    if ([string]::IsNullOrWhiteSpace($DeviceId) -or [string]::IsNullOrWhiteSpace($NewName)) {
        continue
    }

    # Construct API URL
    $Url = "https://webapi.teamviewer.com/api/v1/devices/$DeviceId"

    # Define JSON payload to update device alias
    $Body = @{
        alias = $NewName
    } | ConvertTo-Json -Compress

    # Set Authorization Header
    $Headers = @{
        "Authorization" = "Bearer $ApiToken"
        "Content-Type"  = "application/json"
    }

    # Try updating the device name
    try {
        $Response = Invoke-RestMethod -Uri $Url -Headers $Headers -Method Post -Body $Body -ErrorAction Stop
        Write-Host "[OK] Successfully renamed '$CurrentName' to '$NewName' (Device ID: $DeviceId)" -ForegroundColor Green
    } catch {
        Write-Host "[X] Failed to rename '$CurrentName' (Device ID: $DeviceId)" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)"
    }
}

Write-Host "Process completed." -ForegroundColor Cyan
