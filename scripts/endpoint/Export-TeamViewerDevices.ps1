<#
.SYNOPSIS
    Export the TeamViewer device list (web API) to a CSV.
.DESCRIPTION
    Calls https://webapi.teamviewer.com/api/v1/devices with a script token and writes every device
    (device_id, alias, online_state, last_seen, ...) to a CSV file.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : TeamViewer API script token (Computers & Contacts: view)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Export-TeamViewerDevices.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$ApiToken   = "<API-KEY>"
$OutputPath = "C:\Scripts\Reports\TeamViewer_Devices.csv"
# -------------------------------------------------------------------------

$Headers = @{
    "Authorization" = "Bearer $ApiToken"
    "Content-Type" = "application/json"
}
$Url = "https://webapi.teamviewer.com/api/v1/devices"
$Devices = Invoke-RestMethod -Uri $Url -Headers $Headers -Method Get
$Devices.devices | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Output "Export completed: $OutputPath"
