<#
.SYNOPSIS
    Logs the listening/established TCP connections on a given local port to a text log file.
.DESCRIPTION
    Takes a snapshot of Get-NetTCPConnection for the configured local port (default 135 / RPC)
    and appends one timestamped line per connection (remote address:port -> local address:port,
    state) to the log file, or a "no active connections" line. Schedule it to track who uses a port
    before closing it on the firewall.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Windows 8 / Server 2012 or later (NetTCPIP module)
    Impact      : Read-only (appends to a log file)
    License     : MIT
.EXAMPLE
    .\Watch-LocalPort.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Define the port to monitor
$Port = 135
# Define the log file path
$LogFile = "C:\Scripts\Logs\PortMonitor.log"
# -------------------------------------------------------------------------

# Get the current date and time
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
# Get the current TCP connections and filter by the specified port
$Connections = Get-NetTCPConnection -LocalPort $Port -State Listen, Established

# Log the results
if ($Connections) {
    foreach ($Connection in $Connections) {
        $LogEntry = "$Timestamp - Connection from $($Connection.RemoteAddress):$($Connection.RemotePort) to $($Connection.LocalAddress):$($Connection.LocalPort) - State: $($Connection.State)"
        Add-Content -Path $LogFile -Value $LogEntry
    }
} else {
    $LogEntry = "$Timestamp - No active connections on port $Port"
    Add-Content -Path $LogFile -Value $LogEntry
}
