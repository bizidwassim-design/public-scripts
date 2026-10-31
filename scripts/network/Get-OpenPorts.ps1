<#
.SYNOPSIS
    Inventory established TCP connections and listening UDP endpoints of the local computer with owning process.
.DESCRIPTION
    Lists every established TCP connection and every UDP endpoint, resolves the owning process name,
    attempts a reverse lookup of local/remote addresses, de-duplicates on LocalPort/RemotePort and writes
    <COMPUTERNAME>_Open_TCP_UDP_Ports.csv to C:\temp, then copies it to a central share.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin (to see owning processes) | write access to the central share
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-OpenPorts.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$DnsServer    = "dc01.corp.contoso.local"                          # internal DNS server used for the reachability check
$ShareFolder  = "\\SRV-FILE01.corp.contoso.local\IT-Support\output" # central collection share
# -------------------------------------------------------------------------

$result = $connection = @()

$computername = $env:COMPUTERNAME

cd c: ; if (Test-Path c:\temp){cd c:\temp} else {mkdir c:\temp ; cd c:\temp}

function FQDN {
Param(
        [Parameter(Mandatory=$True)]
        [string]$IP
    )

$LocalAddressFQDN = $null

$localIP = @()

$localIP = (get-NetIPAddress -AddressFamily IPV4 -InterfaceAlias Ethernet).IPAddress

$computername = $env:COMPUTERNAME

# retrieve FQDN based on IP
if ($localIP.Contains($IP))  {$LocalAddressFQDN = $computername}

else {  # check on local DNS
        $NSLOOKUP = ((Test-Connection $DnsServer -ErrorAction SilentlyContinue |select IPV4Address -First 1 ).IPV4Address).IPAddressToString
        if (!($NSLOOKUP)) {$LocalAddressFQDN = "not found in DNS"}
        if ($NSLOOKUP -like "192.168.*"){$LocalAddressFQDN = "not found in DNS"} else {$LocalAddressFQDN = $NSLOOKUP}
     }

Return $LocalAddressFQDN

}




function Application {
Param(
        [Parameter(Mandatory=$True)]
        [string]$Port,
        [Parameter(Mandatory=$True)]
        [string]$Protocol
    )

    if ($protocol -like "TCP"){
    $Application = (Get-Process -Id (Get-NetTCPConnection -LocalPort $Port).OwningProcess -ErrorAction SilentlyContinue| Select-Object ProcessName).ProcessName
    if ($Application){$ApplicationName = $Application}else{$ApplicationName = "Unknown"}
    }

    if ($protocol -like "UDP"){
    $Application = (Get-Process -Id (Get-NetUDPEndpoint -LocalPort $Port).OwningProcess -ErrorAction SilentlyContinue| Select-Object ProcessName).ProcessName
    if ($Application){$ApplicationName = $Application}else{$ApplicationName = "Unknown"}
    }


Return $ApplicationName

}

# 1) list all established connections, source destination port status, protocol (tcp/udp)
$connectionsTCP = Get-NetTCPConnection | Where-Object {$_.State -eq "Established"} | Select-Object LocalAddress, LocalPort,RemoteAddress,RemotePort, State,AppliedSetting,OwningProcess

foreach ($connection in $connectionsTCP)
{
write-host "TCP" -ForegroundColor Yellow
$result += [pscustomobject]@{
        'Computer' = $env:COMPUTERNAME
        'protocol' = "TCP"
        'LocalAddress' = $connection.LocalAddress
        'LocalAddressFQDN' = FQDN -IP $connection.LocalAddress
        'LocalPort' = $connection.LocalPort
        'RemoteAddress' = $connection.RemoteAddress
        'RemoteAddressFQDN' = FQDN -IP $connection.RemoteAddress
        'RemotePort' = $connection.RemotePort
        'State' = $connection.State
        'AppliedSetting' = $connection.AppliedSetting
        'OwningProcess' = $connection.OwningProcess
        'Application' =  Application -Port $connection.LocalPort -Protocol TCP
        }

}


$connectionsUDP = Get-NetUDPEndpoint | Select-Object LocalAddress,LocalPort,OwningProcess

foreach ($connection in $connectionsUDP)
{
write-host "udp" -ForegroundColor green
$result += [pscustomobject]@{
        'Computer' = $env:COMPUTERNAME
        'protocol' = "UDP"
        'LocalAddress' = $connection.LocalAddress
        'LocalAddressFQDN' = FQDN -IP $connection.LocalAddress
        'LocalPort' = $connection.LocalPort
        'RemoteAddress' = "N/A"
        'RemoteAddressFQDN' = "N/A"
        'RemotePort' = "N/A"
        'State' = "Listening"
        'AppliedSetting' = "N/A"
        'OwningProcess' = $connection.OwningProcess
        'Application' =  Application -Port $connection.LocalPort -Protocol UDP
        }

}


# 2) export this result to csv file named the computername

$filename = $computername + "_Open_TCP_UDP_Ports.csv"

$result | Export-Csv -Path $filename -NoTypeInformation -Append


# 4) parse the csv file and remove the duplication lines, keep the unique result
$unique = Import-Csv -Path $filename | Sort-Object -Property LocalPort, RemotePort -Unique
$unique| Export-Csv -Path $filename -NoTypeInformation

# 5) copy the csv file over network to a central share
$destination = "$ShareFolder\$filename"
Copy-Item -Path $filename -Destination $destination
