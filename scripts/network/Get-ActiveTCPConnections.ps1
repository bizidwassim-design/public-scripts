<#
.SYNOPSIS
    Lists the established TCP connections of the local host with resolved remote host names and owning process.
.DESCRIPTION
    Wraps Get-NetTCPConnection -State Established, resolves each remote IP to a DNS name and
    maps the owning PID to its process name. Output is printed to the console (one line per
    connection). Useful during triage to see where a workstation is talking to.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Windows 8 / Server 2012 or later (NetTCPIP module) | run as admin to see all processes
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ActiveTCPConnections.ps1

    # One-liner variant with the full process path:
    # Get-NetTCPConnection -State Established | Select-Object LocalAddress, LocalPort, @{n='RemoteHostName';e={ (Resolve-DnsName $_.RemoteAddress).NameHost }}, RemoteAddress, RemotePort, State, @{n='ProcessName';e={ (Get-Process -Id $_.OwningProcess).Path }}, OffloadState, CreationTime | Format-Table
#>

# Get all active TCP connections with RemoteHostName
$connections = Get-NetTCPConnection -State Established | Select-Object -Property LocalAddress, LocalPort, @{name='RemoteHostName';expression={ (Resolve-DnsName $_.RemoteAddress).NameHost }}, RemoteAddress, RemotePort, State, OwningProcess

# Output headers
Write-Host "LocalAddress   LocalPort   RemoteHostName   RemoteAddress   RemotePort   State         ProcessName"

# Loop through each connection
foreach ($connection in $connections) {
    $localAddress = $connection.LocalAddress
    $localPort = $connection.LocalPort
    $remoteHostName = $connection.RemoteHostName
    $remoteAddress = $connection.RemoteAddress
    $remotePort = $connection.RemotePort
    $state = $connection.State
    $processId = $connection.OwningProcess
    $processName = (Get-Process -Id $processId).ProcessName

    Write-Host "$localAddress     $localPort      $remoteHostName     $remoteAddress     $remotePort     $state       $processName"
}
