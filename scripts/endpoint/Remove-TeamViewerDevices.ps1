<#
.SYNOPSIS
    Delete TeamViewer devices listed in a text file (one device ID per line) through the web API.
.DESCRIPTION
    Reads device IDs from devices.txt and sends DELETE /api/v1/devices/<id> for each one, reporting
    success or failure per device. Use Export-TeamViewerDevices.ps1 to get the IDs.
    API doc: https://webapi.teamviewer.com/api/v1/docs/index
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : TeamViewer API script token (Computers & Contacts: delete)
    Impact      : Modifies TeamViewer (removes devices from the Computers & Contacts list)
    License     : MIT
.EXAMPLE
    .\Remove-TeamViewerDevices.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$ApiToken       = "<API-KEY>"
$DeviceListPath = "C:\Scripts\Input\devices.txt"   # one TeamViewer device ID per line
# -------------------------------------------------------------------------

# Check if the file exists
if (-Not (Test-Path $DeviceListPath)) {
    Write-Host "Error: File '$DeviceListPath' not found!" -ForegroundColor Red
    exit
}

# Read all Device IDs from the file
$DeviceIds = Get-Content $DeviceListPath

# Loop through each Device ID and attempt deletion
foreach ($DeviceId in $DeviceIds) {
    if ($DeviceId -match "^\s*$") { continue }  # Skip empty lines

    # Construct API URL
    $Url = "https://webapi.teamviewer.com/api/v1/devices/$DeviceId"

    # Set Authorization Header
    $Headers = @{
        "Authorization" = "Bearer $ApiToken"
        "Accept"        = "application/json"
    }

    # Try deleting the device
    try {
        $response = Invoke-RestMethod -Uri $Url -Headers $Headers -Method Delete -ErrorAction Stop
        Write-Host "[OK] Successfully deleted Device ID: $DeviceId" -ForegroundColor Green
    } catch {
        Write-Host "[X] Failed to delete Device ID: $DeviceId" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)"
    }
}

Write-Host "Process completed." -ForegroundColor Cyan
