<#
.SYNOPSIS
    Windows Server 2008-compatible network connections logger (netstat based) with a schtasks installer.
.DESCRIPTION
    Parses "netstat -ano" and appends every ESTABLISHED and LISTENING TCP connection plus all UDP
    endpoints (protocol, state, inferred direction, IPs, resolved host names, ports, process name,
    PID) to a CSV. Run with -Install to copy itself to $ScriptDir and register a schtasks job that
    runs every 5 minutes as SYSTEM. Used to collect a 30-day traffic baseline before creating
    firewall ACLs on legacy servers where Get-NetTCPConnection is not available.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin | PowerShell 2.0+ (Windows Server 2008 compatible)
    Impact      : With -Install creates/replaces a scheduled task; otherwise read-only (appends to a CSV)
    License     : MIT
.EXAMPLE
    powershell -File .\Start-NetworkConnectionsMonitoringLegacy.ps1 -Install
.EXAMPLE
    powershell -File .\Start-NetworkConnectionsMonitoringLegacy.ps1
#>

param(
    [switch]$Install
)

# ---- EDIT ME ------------------------------------------------------------
$ScriptDir = "C:\NetworkConnections"
$CsvPath   = "C:\NetworkConnections\network_connections.csv"
$ErrorLog  = "C:\NetworkConnections\error_log.txt"
$TaskName  = "NetworkConnectionsMonitoring"
# -------------------------------------------------------------------------

# Ensure directory exists
if (-not (Test-Path $ScriptDir)) {
    New-Item -ItemType Directory -Path $ScriptDir -Force | Out-Null
}

# =============================================================================
# INSTALL SCHEDULED TASK (schtasks.exe - Server 2008 compatible)
# =============================================================================
if ($Install) {
    $scriptPath = Join-Path $ScriptDir "Start-NetworkConnectionsMonitoringLegacy.ps1"
    $currentScript = $MyInvocation.MyCommand.Path
    if ($currentScript -and ($currentScript -ne $scriptPath)) {
        Copy-Item -Path $currentScript -Destination $scriptPath -Force
    }

    # Remove existing task
    & schtasks /Delete /TN $TaskName /F 2>$null

    # Create task - every 5 minutes, SYSTEM, highest privileges
    & schtasks /Create `
        /TN $TaskName `
        /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
        /SC MINUTE `
        /MO 5 `
        /RL HIGHEST `
        /RU "SYSTEM" `
        /F

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Tache planifiee '$TaskName' creee avec succes." -ForegroundColor Green
        Write-Host "  Frequence  : aux 5 minutes" -ForegroundColor White
        Write-Host "  Script     : $scriptPath" -ForegroundColor White
        Write-Host "  CSV output : $CsvPath" -ForegroundColor White
    }
    else {
        Write-Host "ERREUR: Impossible de creer la tache planifiee." -ForegroundColor Red
    }
    exit
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

function Resolve-IPToHostname {
    param([string]$IPAddress)
    if ([string]::IsNullOrEmpty($IPAddress) -or $IPAddress -eq "::1" -or
        $IPAddress -eq "127.0.0.1" -or $IPAddress -eq "0.0.0.0" -or $IPAddress -eq "*") {
        return $IPAddress
    }
    try {
        return [System.Net.Dns]::GetHostEntry($IPAddress).HostName
    }
    catch {
        return $IPAddress
    }
}

function Get-ProcessNameSafe {
    param([int]$ProcessId)
    if ($ProcessId -eq 0) { return "System Idle" }
    if ($ProcessId -eq 4) { return "System" }
    try {
        return (Get-Process -Id $ProcessId -ErrorAction Stop).ProcessName
    }
    catch {
        return "PID:$ProcessId"
    }
}

# =============================================================================
# MAIN - Parse netstat -ano and append to CSV
# =============================================================================

try {
    $timestamp   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $connections = @()

    $netstatOutput = & netstat -ano 2>$null

    foreach ($line in $netstatOutput) {
        $line = $line.Trim()

        # Skip headers / empty
        if ([string]::IsNullOrEmpty($line))       { continue }
        if ($line -match "^(Active|Proto|\s*$)")   { continue }

        $parts = $line -split '\s+' | Where-Object { $_ -ne '' }
        if ($parts.Count -lt 4) { continue }

        $protocol       = $parts[0]
        $localEndpoint  = $parts[1]
        $remoteEndpoint = $parts[2]

        # --- State and PID ---
        $state = ""; $pid = 0

        if ($protocol -eq "TCP") {
            if ($parts.Count -lt 5) { continue }
            $state = $parts[3]
            try { $pid = [int]$parts[4] } catch { continue }
        }
        elseif ($protocol -eq "UDP") {
            $state = "UDP"
            try { $pid = [int]$parts[3] } catch { continue }
        }
        else { continue }

        # --- Filter: ESTABLISHED + LISTENING (TCP) and all UDP ---
        if ($protocol -eq "TCP" -and $state -ne "ESTABLISHED" -and $state -ne "LISTENING") {
            continue
        }

        # --- Parse local IP:Port ---
        $localIP = ""; $localPort = ""
        if ($localEndpoint -match '^\[(.+)\]:(\d+)$') {
            $localIP = $Matches[1]; $localPort = $Matches[2]
        }
        elseif ($localEndpoint -match '^(.+):(\d+)$') {
            $localIP = $Matches[1]; $localPort = $Matches[2]
        }

        # --- Parse remote IP:Port ---
        $remoteIP = ""; $remotePort = ""
        if ($remoteEndpoint -match '^\[(.+)\]:(\d+)$') {
            $remoteIP = $Matches[1]; $remotePort = $Matches[2]
        }
        elseif ($remoteEndpoint -match '^(.+):(\d+)$') {
            $remoteIP = $Matches[1]; $remotePort = $Matches[2]
        }
        elseif ($remoteEndpoint -eq "*:*") {
            $remoteIP = "*"; $remotePort = "*"
        }

        # Skip loopback
        if ($localIP -eq "127.0.0.1" -and $remoteIP -eq "127.0.0.1") { continue }
        if ($localIP -eq "::1" -and $remoteIP -eq "::1") { continue }

        # --- Direction ---
        $direction = "Unknown"
        if ($state -eq "LISTENING" -or ($protocol -eq "UDP" -and ($remoteIP -eq "*" -or $remoteIP -eq "0.0.0.0"))) {
            $direction = "Inbound-Listen"
        }
        elseif ($state -eq "ESTABLISHED") {
            $lp = 0; $rp = 0
            [int]::TryParse($localPort, [ref]$lp)  | Out-Null
            [int]::TryParse($remotePort, [ref]$rp) | Out-Null
            if ($lp -gt 0 -and $lp -le 1024)     { $direction = "Inbound" }
            elseif ($rp -gt 0 -and $rp -le 1024) { $direction = "Outbound" }
            elseif ($lp -lt $rp)                  { $direction = "Inbound" }
            else                                   { $direction = "Outbound" }
        }

        # --- Resolve hostnames ---
        $processName    = Get-ProcessNameSafe -ProcessId $pid
        $sourceHostname = $localIP
        $destHostname   = $remoteIP
        if ($remoteIP -ne "*" -and $remoteIP -ne "0.0.0.0" -and $remoteIP -ne "[::]") {
            $destHostname = Resolve-IPToHostname -IPAddress $remoteIP
        }

        # --- Build record ---
        $obj = New-Object PSObject -Property @{
            Timestamp           = $timestamp
            Protocol            = $protocol
            State               = $state
            Direction           = $direction
            SourceIP            = $localIP
            SourceHostname      = $sourceHostname
            SourcePort          = $localPort
            DestinationIP       = $remoteIP
            DestinationHostname = $destHostname
            DestinationPort     = $remotePort
            ProcessName         = $processName
            PID                 = $pid
        }

        $connections += $obj
    }

    # --- Append all connections to CSV ---
    if ($connections.Count -gt 0) {

        # Ordered columns for clean CSV
        $ordered = $connections | Select-Object `
            Timestamp, Protocol, State, Direction,
            SourceIP, SourceHostname, SourcePort,
            DestinationIP, DestinationHostname, DestinationPort,
            ProcessName, PID

        if (-not (Test-Path $CsvPath)) {
            # First run - create with headers
            $ordered | Export-Csv -Path $CsvPath -NoTypeInformation
        }
        else {
            # Subsequent runs - append
            $ordered | Export-Csv -Path $CsvPath -NoTypeInformation -Append
        }
    }
}
catch {
    $errorMsg = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - ERROR: $($_.Exception.Message)"
    Add-Content -Path $ErrorLog -Value $errorMsg
}
