<#
.SYNOPSIS
    Exports every DHCP reservation from all DHCP servers registered in Active Directory to a CSV.
.DESCRIPTION
    Enumerates the authorised DHCP servers of the forest (Get-DhcpServerInDC), then for each
    server and each IPv4 scope lists the reservations (IP, hostname, MAC, description, lease expiry)
    and exports them to a single CSV file. Must be run from a DHCP server (or a host with the
    DhcpServer RSAT module) with rights on every DHCP server.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : DhcpServer module (RSAT) | run from a DHCP server
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Export-DhcpReservations.ps1

    # Single-server variant (run locally on one DHCP server):
    # Get-DhcpServerV4Scope | ForEach-Object { Get-DhcpServerv4Lease -ScopeID $_.ScopeID | Where-Object { $_.AddressState -like '*Reservation' } } |
    #   Select-Object ScopeId,IPAddress,HostName,ClientID,AddressState | Export-Csv "C:\Scripts\Reports\$($env:COMPUTERNAME)-Reservations.csv" -NoTypeInformation
#>

# ---- EDIT ME ------------------------------------------------------------
# Define the output CSV file path
$outputFilePath = "C:\Scripts\Reports\DhcpReservations.csv"
# -------------------------------------------------------------------------

# Create an empty array to store reservation details
$reservations = @()

# Get all DHCP servers in the current Active Directory forest
$dhcpServers = Get-DhcpServerInDC

# Loop through each DHCP server
foreach ($dhcpServer in $dhcpServers) {
    # Get all DHCP scopes on the current server
    $scopes = Get-DhcpServerv4Scope -ComputerName $dhcpServer.DnsName

    # Loop through each DHCP scope
    foreach ($scope in $scopes) {
        # Get all reservations in the current scope
        $scopeReservations = Get-DhcpServerv4Reservation -ComputerName $dhcpServer.DnsName -ScopeId $scope.ScopeId

        # Add each reservation to the reservations array
        foreach ($reservation in $scopeReservations) {
            $reservations += [PSCustomObject]@{
                Server         = $dhcpServer.DnsName
                Scope          = $scope.Name
                IPAddress      = $reservation.IPAddress
                Hostname       = $reservation.Name
                MACAddress     = $reservation.ClientID
                Description    = $reservation.Description
                LeaseExpires   = $reservation.LeaseExpiryTime
            }
        }
    }
}

# Export the reservations to a CSV file
$reservations | Export-Csv -Path $outputFilePath -NoTypeInformation

Write-Host "DHCP reservations exported to $outputFilePath"
