<#
.SYNOPSIS
    Shows the TCP connections (local/remote address and port, state) opened by a given process.
.DESCRIPTION
    Finds the process by name (default: OneDrive), then filters Get-NetTCPConnection on its PID
    and prints the connections as a table. Quick way to see which remote IPs an application talks to.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Windows 8 / Server 2012 or later (NetTCPIP module)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ProcessNetworkConnections.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$ProcessName = "OneDrive"
# -------------------------------------------------------------------------

# Get the process
$oneDriveProcess = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

# Check if the process is running
if ($oneDriveProcess) {
    # Get the process ID
    $oneDriveProcessId = $oneDriveProcess.Id

    # Get the network connections associated with the process
    $oneDriveConnections = Get-NetTCPConnection | Where-Object { $_.OwningProcess -eq $oneDriveProcessId }

    # Display the connections with local and remote addresses and ports
    $oneDriveConnections | Select-Object -Property LocalAddress, LocalPort, RemoteAddress, RemotePort, State | Format-Table -AutoSize
} else {
    Write-Host "$ProcessName process is not running."
}
