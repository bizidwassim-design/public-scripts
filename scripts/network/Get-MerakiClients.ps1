<#
.SYNOPSIS
    Export every client seen on all Meraki networks of an organisation to a timestamped CSV.
.DESCRIPTION
    Calls the Meraki Dashboard API: lists the organisation's networks, then the clients of each
    network, and writes network / VLAN / status / MAC / IP / switchport / SSID / OS / manufacturer /
    first & last seen to CSV, then opens it.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Meraki Dashboard API key with read access to the organisation
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-MerakiClients.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$MerakiApiKey = "<API-KEY>"
$MerakiOrgId  = "<ORG-ID>"
$OutputFolder = "C:\Scripts\Reports\meraki"
# -------------------------------------------------------------------------

# Get the current date and time as a string
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Specify the path to your log file
$outputfile = "$OutputFolder\extractdevices$timestamp.csv"


$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("X-Cisco-Meraki-API-Key", $MerakiApiKey)
$headers.Add("Accept", "application/json")
$headers.Add("tagsFilterType", "withAnyTags")

$response = Invoke-RestMethod "https://api.meraki.com/api/v1/organizations/$MerakiOrgId/networks" -Method 'GET' -Headers $headers
#$response | ConvertTo-Json

$networks = $response
$result = @()
$i = 0
foreach ($network in $networks.id)
{

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("X-Cisco-Meraki-API-Key", $MerakiApiKey)
$headers.Add("Accept", "application/json")
$headers.Add("tagsFilterType", "withAnyTags")

$response = Invoke-RestMethod "https://api.meraki.com/api/v1/networks/$network/clients" -Method 'GET' -Headers $headers
#$response | ConvertTo-Json


$clients = $response


foreach ($client in $clients) {


    $result += [pscustomobject]@{
        'switch' = $networks[$i].name
        'vlan' = $client.vlan
        'status' = $client.status
        'mac' = $client.mac
        'recentDeviceMac' = $client.recentDeviceMac
        'switchport' = $client.switchport
        'IP' = $client.ip
        'recentDeviceConnection' = $client.recentDeviceConnection
        'ssid' = $client.ssid
        'description' = $client.description
        'firstSeen' = $client.firstSeen
        'lastSeen' = $client.lastSeen
        'manufacturer' = $client.manufacturer
        'os' = $client.os
        'recentDeviceName' = $client.recentDeviceName
        }
    }
$i++
}
$result|Export-Csv -NoTypeInformation -path $outputfile

start $outputfile
