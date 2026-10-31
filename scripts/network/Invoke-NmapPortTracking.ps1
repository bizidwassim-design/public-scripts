<#
.SYNOPSIS
    Scan a list of hosts with Nmap and keep a cumulative, de-duplicated list of open ports per host.
.DESCRIPTION
    Reads an Excel sheet (columns: IP, Hostname), runs several Nmap scans against each IP (SYN+UDP,
    full TCP range, no-ping, default) and merges the open ports found into a text file
    "<ip>: port,port,...". Re-running the script adds newly discovered ports without duplicates.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ImportExcel | Nmap in PATH | run as admin (SYN/UDP scans)
    Impact      : Read-only (active network scanning: only scan hosts you are authorised to test)
    License     : MIT
.EXAMPLE
    .\Invoke-NmapPortTracking.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$excelFile  = "C:\Scripts\Input\hosts.xlsx"          # columns: IP, Hostname
$outputFile = "C:\Scripts\Reports\scan_results.txt"  # Output file for results
# -------------------------------------------------------------------------

# Import Excel module
Import-Module ImportExcel

# Read Excel data
$data = Import-Excel -Path $excelFile

# Function to run Nmap scan
function Run-NmapScan {
    param (
        [string]$ip
    )

    $scanCommands = @(
        "nmap -sS -sU -T4 -A -v $ip",
        "nmap -p 1-65535 -T4 -A -v $ip",
        "nmap -T4 -A -v -Pn $ip",
        "nmap -T4 -A -v $ip"
    )

    $openPorts = @()

    foreach ($cmd in $scanCommands) {
        $result = Invoke-Expression -Command $cmd | Out-String
        $ports = $result -match "(\d{1,5})/open"
        if ($ports) {
            $openPorts += $matches[1]
        }
    }

    return ($openPorts | Sort-Object -Unique)
}

# Function to update result file
function Update-Results {
    param (
        [string]$ip,
        [array]$ports
    )

    # Read existing results
    if (Test-Path $outputFile) {
        $existingData = Get-Content $outputFile
    } else {
        $existingData = @()
    }

    $newData = @()
    $existingPorts = @()

    foreach ($line in $existingData) {
        if ($line -match "^$([regex]::Escape($ip)): (.+)$") {
            $existingPorts = $matches[1] -split ","
        } else {
            $newData += $line
        }
    }

    # Merge new and existing ports
    $allPorts = ($existingPorts + $ports) | Sort-Object -Unique
    $newData += "${ip}: $(($allPorts -join ","))"

    # Write back to file
    $newData | Set-Content $outputFile
}

# Main script loop
foreach ($entry in $data) {
    $ip = $entry.IP
    Write-Host "Scanning $ip..."
    $ports = Run-NmapScan -ip $ip
    if ($ports.Count -gt 0) {
        Update-Results -ip $ip -ports $ports
        Write-Host "Updated results for $ip"
    } else {
        Write-Host "No open ports found for $ip"
    }
}
