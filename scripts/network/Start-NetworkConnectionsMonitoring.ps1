<#
.SYNOPSIS
    Logs the established TCP connections of a host to a CSV and registers itself as a recurring scheduled task.
.DESCRIPTION
    Captures every established TCP connection (source/destination IP, resolved host names, ports,
    process name), appends it to a CSV, de-duplicates the CSV on destination IP + port (keeping the
    most recent entry) and registers a scheduled task that re-runs the script at startup and every
    15 minutes. Used to build a baseline of a server's traffic before writing firewall ACLs.
    Copy this file to $ScriptPath before running so the scheduled task can find it.
    For Windows Server 2008 / PowerShell 2.0 hosts use Start-NetworkConnectionsMonitoringLegacy.ps1.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin | Windows 8 / Server 2012 or later (NetTCPIP, ScheduledTasks modules)
    Impact      : Creates/replaces a scheduled task; writes a CSV and an error log
    License     : MIT
.EXAMPLE
    .\Start-NetworkConnectionsMonitoring.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$csvPath    = "C:\NetworkConnections\network_connections.csv"
$ScriptPath = "C:\NetworkConnections\Start-NetworkConnectionsMonitoring.ps1"   # where this script lives for the scheduled task
$taskName   = "NetworkConnectionsMonitoring"
# -------------------------------------------------------------------------

# Network Connections Monitoring and Logging Script

# Ensure the directory exists
$logDirectory = Split-Path -Path $csvPath -Parent
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory | Out-Null
}

# Function to resolve IP to hostname
function Resolve-IPToHostname {
    param (
        [string]$IPAddress
    )

    # Skip resolution for localhost or empty IP
    if ($IPAddress -eq '::1' -or $IPAddress -eq '127.0.0.1' -or [string]::IsNullOrWhiteSpace($IPAddress)) {
        return $IPAddress
    }

    try {
        # Try to resolve hostname
        $hostname = [System.Net.Dns]::GetHostEntry($IPAddress).HostName
        return $hostname
    }
    catch {
        # If resolution fails, return original IP
        return $IPAddress
    }
}

# Function to get network connections
function Get-NetworkConnections {
    # Get established TCP connections
    $connections = Get-NetTCPConnection -State Established |
    Where-Object {
        # Exclude connections where source and destination are the same
        $_.LocalAddress -ne $_.RemoteAddress
    } |
    ForEach-Object {
        # Resolve hostnames
        $sourceHostname = Resolve-IPToHostname -IPAddress $_.LocalAddress
        $destHostname = Resolve-IPToHostname -IPAddress $_.RemoteAddress

        [PSCustomObject]@{
            Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            SourceIP = $_.LocalAddress
            SourceHostname = $sourceHostname
            SourcePort = $_.LocalPort
            DestinationIP = $_.RemoteAddress
            DestinationHostname = $destHostname
            DestinationPort = $_.RemotePort
            ProcessName = (Get-Process -Id $_.OwningProcess).ProcessName
        }
    }
    return $connections
}

# Function to log network connections to CSV
function Log-NetworkConnections {
    param (
        [Parameter(Mandatory=$true)]
        $Connections
    )

    # Append to CSV, create if not exists
    $Connections | Export-Csv -Path $csvPath -Append -NoTypeInformation
}

# Function to remove duplicate entries
function Remove-DuplicateEntries {
    # Read the CSV
    $connections = Import-Csv -Path $csvPath

    # Remove duplicates based on destination IP and destination port
    $uniqueConnections = $connections |
        Group-Object -Property DestinationIP, DestinationPort |
        ForEach-Object {
            # For each group, take the most recent entry
            $_.Group |
            Sort-Object -Property Timestamp -Descending |
            Select-Object -First 1
        }

    # Overwrite the original CSV with unique entries
    $uniqueConnections | Export-Csv -Path $csvPath -NoTypeInformation
}

# Main monitoring function
function Start-NetworkMonitoring {
    # Get and log current connections
    $currentConnections = Get-NetworkConnections

    # Only log if there are connections
    if ($currentConnections) {
        Log-NetworkConnections -Connections $currentConnections
    }
}

# Create a scheduled task to run on startup and periodically
function Set-PersistentMonitoring {
    # Remove existing task if it exists
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    # Create a new scheduled task
    $action = New-ScheduledTaskAction -Execute 'Powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

    # Trigger on startup and run every 15 minutes
    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $recurringTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 15)

    # Create the task
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($startupTrigger, $recurringTrigger) -RunLevel Highest
}

# Main script execution
try {
    # Start monitoring and logging
    Start-NetworkMonitoring

    # Remove duplicate entries
    Remove-DuplicateEntries

    # Ensure persistent monitoring
    Set-PersistentMonitoring
}
catch {
    # Log any errors
    $errorMessage = "Error: $_"
    Add-Content -Path (Join-Path $logDirectory "error_log.txt") -Value "$((Get-Date).ToString()) - $errorMessage"
}
