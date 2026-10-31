<#
.SYNOPSIS
    Report every IP-enabled adapter's configuration and flag the ones still on DHCP (with ready-made static commands).
.DESCRIPTION
    Reads Win32_NetworkAdapterConfiguration, prints IP / mask / CIDR / gateway / DNS / WINS per adapter,
    detects DHCP vs static and, for each DHCP adapter, prints the PowerShell (New-NetIPAddress...) and
    netsh commands that would pin the current lease as a static configuration. Nothing is changed.
    Useful before converting servers or printers to static IPs.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : nothing (local, WMI)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-NetworkAdapterIPConfig.ps1
#>

# Network IP Configuration Check Script - Enhanced Output
# This script checks all network adapters and shows their IP configuration method

Write-Host "=== NETWORK ADAPTER IP CONFIGURATION REPORT ===" -ForegroundColor Green
Write-Host "Computer: $env:COMPUTERNAME" -ForegroundColor White
Write-Host "Date: $(Get-Date)" -ForegroundColor White
Write-Host "User: $env:USERNAME" -ForegroundColor White
Write-Host ""

# Get all network adapter configurations
$adapters = @(Get-WmiObject -Class Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true })

if ($adapters.Count -eq 0) {
    Write-Host "NO IP-ENABLED NETWORK ADAPTERS FOUND!" -ForegroundColor Red
    Write-Host "Checking all adapters (including disabled ones)..." -ForegroundColor Yellow
    Write-Host ""

    $allAdapters = Get-WmiObject -Class Win32_NetworkAdapterConfiguration
    foreach ($adapter in $allAdapters) {
        Write-Host "Adapter: $($adapter.Description)" -ForegroundColor Gray
        Write-Host "  Index: $($adapter.Index)"
        Write-Host "  IP Enabled: $($adapter.IPEnabled)"
        Write-Host "  DHCP Enabled: $($adapter.DHCPEnabled)"
        Write-Host ""
    }
    exit
}

Write-Host "FOUND $($adapters.Count) ACTIVE NETWORK ADAPTER(S)" -ForegroundColor Green
Write-Host "=" * 50 -ForegroundColor Green
Write-Host ""

$adapterNumber = 1
$dhcpAdaptersFound = @()

foreach ($adapter in $adapters) {
    Write-Host "[$adapterNumber] ADAPTER: $($adapter.Description)" -ForegroundColor Yellow -BackgroundColor DarkBlue
    Write-Host "Interface Index: $($adapter.InterfaceIndex)"
    Write-Host "MAC Address: $($adapter.MACAddress)"
    Write-Host ""

    # Display IP configuration
    if ($adapter.IPAddress) {
        Write-Host "IP CONFIGURATION:" -ForegroundColor White
        Write-Host "-" * 20 -ForegroundColor White

        for ($i = 0; $i -lt $adapter.IPAddress.Count; $i++) {
            $ipAddr = $adapter.IPAddress[$i]
            $subnet = if ($adapter.IPSubnet[$i]) { $adapter.IPSubnet[$i] } else { "N/A" }

            Write-Host "IP Address [$($i+1)]: $ipAddr" -ForegroundColor Cyan
            Write-Host "Subnet Mask [$($i+1)]: $subnet" -ForegroundColor Cyan

            # Calculate CIDR if IPv4
            if ($ipAddr -match "^\d+\.\d+\.\d+\.\d+$" -and $subnet -ne "N/A") {
                $cidr = 0
                $subnet.Split('.') | ForEach-Object {
                    $octet = [int]$_
                    for ($bit = 7; $bit -ge 0; $bit--) {
                        if ($octet -band (1 -shl $bit)) { $cidr++ }
                        else { break }
                    }
                }
                Write-Host "CIDR Notation [$($i+1)]: /$cidr" -ForegroundColor Cyan
            }
        }

        # Configuration type
        if ($adapter.DHCPEnabled) {
            Write-Host ""
            Write-Host "CONFIGURATION TYPE: DHCP" -ForegroundColor Red -BackgroundColor Yellow
            $dhcpAdaptersFound += $adapter

            Write-Host "DHCP Server: $($adapter.DHCPServer)" -ForegroundColor Red

            if ($adapter.DHCPLeaseObtained) {
                $leaseObtained = [Management.ManagementDateTimeConverter]::ToDateTime($adapter.DHCPLeaseObtained)
                Write-Host "DHCP Lease Obtained: $leaseObtained" -ForegroundColor Red
            }
            if ($adapter.DHCPLeaseExpires) {
                $leaseExpires = [Management.ManagementDateTimeConverter]::ToDateTime($adapter.DHCPLeaseExpires)
                Write-Host "DHCP Lease Expires: $leaseExpires" -ForegroundColor Red
            }
        } else {
            Write-Host ""
            Write-Host "CONFIGURATION TYPE: STATIC IP" -ForegroundColor Green -BackgroundColor Black
        }

        # Network details
        Write-Host ""
        Write-Host "NETWORK DETAILS:" -ForegroundColor White
        Write-Host "-" * 20 -ForegroundColor White

        if ($adapter.DefaultIPGateway) {
            Write-Host "Default Gateway: $($adapter.DefaultIPGateway -join ', ')" -ForegroundColor White
        } else {
            Write-Host "Default Gateway: Not configured" -ForegroundColor Gray
        }

        if ($adapter.DNSServerSearchOrder) {
            Write-Host "DNS Servers: $($adapter.DNSServerSearchOrder -join ', ')" -ForegroundColor White
        } else {
            Write-Host "DNS Servers: Not configured" -ForegroundColor Gray
        }

        if ($adapter.DNSDomainSuffixSearchOrder) {
            Write-Host "DNS Domain Suffix: $($adapter.DNSDomainSuffixSearchOrder -join ', ')" -ForegroundColor White
        }

        if ($adapter.WINSPrimaryServer -or $adapter.WINSSecondaryServer) {
            Write-Host "WINS Primary: $($adapter.WINSPrimaryServer)" -ForegroundColor White
            Write-Host "WINS Secondary: $($adapter.WINSSecondaryServer)" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor DarkGray
    Write-Host ""
    $adapterNumber++
}

# Summary
Write-Host "SUMMARY:" -ForegroundColor Green -BackgroundColor Black
Write-Host "Total Active Adapters: $($adapters.Count)" -ForegroundColor Green
Write-Host "DHCP Adapters: $($dhcpAdaptersFound.Count)" -ForegroundColor Red
Write-Host "Static IP Adapters: $($adapters.Count - $dhcpAdaptersFound.Count)" -ForegroundColor Green
Write-Host ""

# If DHCP adapters found, show conversion details
if ($dhcpAdaptersFound.Count -gt 0) {
    Write-Host "WARNING: DHCP ADAPTERS DETECTED!" -ForegroundColor Red -BackgroundColor Yellow
    Write-Host "The following adapters are using DHCP and can be converted to Static IP:" -ForegroundColor Yellow
    Write-Host ""

    $dhcpCount = 1
    foreach ($dhcpAdapter in $dhcpAdaptersFound) {
        Write-Host "[$dhcpCount] DHCP ADAPTER TO CONVERT:" -ForegroundColor Red -BackgroundColor White
        Write-Host "Adapter: $($dhcpAdapter.Description)" -ForegroundColor Red
        Write-Host ""

        # Get interface alias for PowerShell commands
        $interfaceAlias = "Unknown"
        try {
            $netAdapter = Get-NetAdapter | Where-Object { $_.InterfaceIndex -eq $dhcpAdapter.InterfaceIndex } -ErrorAction SilentlyContinue
            if ($netAdapter) {
                $interfaceAlias = $netAdapter.InterfaceAlias
            }
        } catch {
            # Fallback - use description
            $interfaceAlias = $dhcpAdapter.Description
        }

        Write-Host "CURRENT DHCP SETTINGS TO PRESERVE:" -ForegroundColor Yellow
        Write-Host "IP Address: $($dhcpAdapter.IPAddress[0])" -ForegroundColor Cyan
        Write-Host "Subnet Mask: $($dhcpAdapter.IPSubnet[0])" -ForegroundColor Cyan
        if ($dhcpAdapter.DefaultIPGateway) {
            Write-Host "Gateway: $($dhcpAdapter.DefaultIPGateway[0])" -ForegroundColor Cyan
        }
        if ($dhcpAdapter.DNSServerSearchOrder) {
            Write-Host "DNS Servers: $($dhcpAdapter.DNSServerSearchOrder -join ', ')" -ForegroundColor Cyan
        }
        Write-Host ""

        Write-Host "POWERSHELL COMMANDS TO CONVERT TO STATIC:" -ForegroundColor Green
        Write-Host "# 1. Remove DHCP configuration" -ForegroundColor Gray
        Write-Host "Remove-NetIPAddress -InterfaceAlias '$interfaceAlias' -Confirm:`$false" -ForegroundColor White
        Write-Host "Remove-NetRoute -InterfaceAlias '$interfaceAlias' -Confirm:`$false" -ForegroundColor White
        Write-Host ""
        Write-Host "# 2. Set static IP" -ForegroundColor Gray

        # Calculate prefix length for static IP
        if ($dhcpAdapter.IPSubnet -and $dhcpAdapter.IPSubnet[0]) {
            $subnetMask = $dhcpAdapter.IPSubnet[0]
            $prefixLength = 0
            $subnetMask.Split('.') | ForEach-Object {
                $octet = [int]$_
                for ($bit = 7; $bit -ge 0; $bit--) {
                    if ($octet -band (1 -shl $bit)) { $prefixLength++ }
                    else { break }
                }
            }

            Write-Host "New-NetIPAddress -InterfaceAlias '$interfaceAlias' -IPAddress '$($dhcpAdapter.IPAddress[0])' -PrefixLength $prefixLength" -ForegroundColor White
        }

        if ($dhcpAdapter.DefaultIPGateway) {
            Write-Host "New-NetRoute -InterfaceAlias '$interfaceAlias' -DestinationPrefix '0.0.0.0/0' -NextHop '$($dhcpAdapter.DefaultIPGateway[0])'" -ForegroundColor White
        }

        if ($dhcpAdapter.DNSServerSearchOrder) {
            $dnsServers = "'" + ($dhcpAdapter.DNSServerSearchOrder -join "','") + "'"
            Write-Host "Set-DnsClientServerAddress -InterfaceAlias '$interfaceAlias' -ServerAddresses $dnsServers" -ForegroundColor White
        }

        Write-Host ""
        Write-Host "NETSH ALTERNATIVE COMMANDS:" -ForegroundColor Green
        if ($dhcpAdapter.IPAddress -and $dhcpAdapter.IPSubnet -and $dhcpAdapter.DefaultIPGateway) {
            Write-Host "netsh interface ip set address '$interfaceAlias' static $($dhcpAdapter.IPAddress[0]) $($dhcpAdapter.IPSubnet[0]) $($dhcpAdapter.DefaultIPGateway[0])" -ForegroundColor White
        }
        if ($dhcpAdapter.DNSServerSearchOrder) {
            Write-Host "netsh interface ip set dns '$interfaceAlias' static $($dhcpAdapter.DNSServerSearchOrder[0])" -ForegroundColor White
        }

        Write-Host ""
        Write-Host "=" * 60 -ForegroundColor DarkRed
        Write-Host ""
        $dhcpCount++
    }
} else {
    Write-Host "EXCELLENT: All adapters are using Static IP configuration!" -ForegroundColor Green -BackgroundColor Black
}

Write-Host ""
Write-Host "SCRIPT COMPLETED SUCCESSFULLY" -ForegroundColor Green -BackgroundColor Black
Write-Host "Timestamp: $(Get-Date)" -ForegroundColor White
