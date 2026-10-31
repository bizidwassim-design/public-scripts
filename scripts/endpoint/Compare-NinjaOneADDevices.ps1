<#
.SYNOPSIS
    Compare NinjaOne RMM devices with enabled Active Directory computers in both directions.
.DESCRIPTION
    Authenticates to the NinjaOne API (OAuth2 client credentials), pulls the devices of one NinjaOne
    organisation and all enabled AD computers (excluding cluster/HMI/NVR names), matches them on
    system name / DNS name / hostname and exports "in NinjaOne only", "in AD only", matched pairs,
    a debug log and a summary text file to the export folder.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | NinjaOne API client (client_credentials, scope "monitoring management control")
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Compare-NinjaOneADDevices.ps1
.EXAMPLE
    .\Compare-NinjaOneADDevices.ps1 -OrganizationId 1 -ExportPath "C:\Scripts\Reports"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [int]$OrganizationId = 1,

    [Parameter(Mandatory = $false)]
    [string]$ExportPath = "C:\Scripts\Reports"
)

#Requires -Version 5.1

# ---- EDIT ME ------------------------------------------------------------
$baseUrl = "https://app.ninjarmm.com"     # your NinjaOne instance: app. / eu. / ca. / oc. ninjarmm.com
# -------------------------------------------------------------------------

# ==============================
# Script Configuration
# ==============================
$ErrorActionPreference = "Continue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# ==============================
# Console Colors
# ==============================
function Write-Success { param([string]$Message) Write-Host "[OK]   $Message" -ForegroundColor Green }
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning2 { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-ErrorMsg { param([string]$Message) Write-Host "[ERR]  $Message" -ForegroundColor Red }

# ==============================
# Banner
# ==============================
Clear-Host
Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "   NinjaOne vs Active Directory Comparison Tool" -ForegroundColor White
Write-Host "   Version 3.0 - OAuth2 Edition" -ForegroundColor Gray
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# ==============================
# Step 1: Get OAuth Credentials
# ==============================
Write-Info "Step 1: OAuth2 Authentication"
Write-Host ""

if ([string]::IsNullOrEmpty($ClientId)) {
    $ClientId = Read-Host "Enter NinjaOne Client ID"
}

if ([string]::IsNullOrEmpty($ClientSecret)) {
    $secureSecret = Read-Host "Enter NinjaOne Client Secret" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureSecret)
    $ClientSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
}

# ==============================
# Step 2: Authenticate with NinjaOne
# ==============================
Write-Info "Step 2: Connecting to NinjaOne API..."

try {
    $body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        redirect_uri  = "https://localhost"
        scope         = "monitoring management control"
    }

    $authHeaders = @{
        "accept"       = "application/json"
        "Content-Type" = "application/x-www-form-urlencoded"
    }

    $auth_token = Invoke-RestMethod -Uri "$baseUrl/oauth/token" `
        -Method POST -Headers $authHeaders -Body $body -ErrorAction Stop

    $access_token = $auth_token.access_token

    $headers = @{
        "accept"        = "application/json"
        "Authorization" = "Bearer $access_token"
    }

    Write-Success "Successfully authenticated with NinjaOne API"
}
catch {
    Write-ErrorMsg "Failed to authenticate with NinjaOne"
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    cmd /c pause
    exit 1
}

# ==============================
# Step 3: Verify Organization
# ==============================
Write-Host ""
Write-Info "Step 3: Verifying organization..."

try {
    $organizations = Invoke-RestMethod -Uri "$baseUrl/v2/organizations" `
        -Headers $headers -Method GET -ErrorAction Stop

    $targetOrg = $organizations | Where-Object { $_.id -eq $OrganizationId }

    if ($targetOrg) {
        Write-Success "Found organization: $($targetOrg.name) (ID: $OrganizationId)"
    }
    else {
        Write-ErrorMsg "Organization ID $OrganizationId not found"
        Write-Host "Available organizations:" -ForegroundColor Yellow
        $organizations | Format-Table name, id -AutoSize
        cmd /c pause
        exit 1
    }
}
catch {
    Write-ErrorMsg "Failed to retrieve organizations"
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    cmd /c pause
    exit 1
}

# ==============================
# Step 4: Get NinjaOne Devices
# ==============================
Write-Host ""
Write-Info "Step 4: Retrieving NinjaOne devices..."

try {
    $allNinjaDevices = Invoke-RestMethod -Uri "$baseUrl/v2/devices" `
        -Headers $headers -Method GET -ErrorAction Stop

    $ninjaDevices = $allNinjaDevices | Where-Object { $_.organizationId -eq $OrganizationId }

    Write-Success "Retrieved $($ninjaDevices.Count) devices from NinjaOne (Org ID: $OrganizationId)"
}
catch {
    Write-ErrorMsg "Failed to retrieve NinjaOne devices"
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    cmd /c pause
    exit 1
}

# ==============================
# Step 5: Get Active Directory Devices
# ==============================
Write-Host ""
Write-Info "Step 5: Retrieving Active Directory devices..."

try {
    # Check if AD module is available
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "Active Directory module not found. Please install RSAT tools."
    }

    Import-Module ActiveDirectory -ErrorAction Stop

    $allADDevices = Get-ADComputer -Filter { Enabled -eq $true } `
        -Property Name, DNSHostName, OperatingSystem, LastLogonDate, DistinguishedName, Description `
        -ErrorAction Stop |
        Select-Object Name, DNSHostName, OperatingSystem, LastLogonDate, DistinguishedName, Description

    # Exclude devices with specific keywords (cluster nodes, HMI systems, NVR systems)
    $excludeKeywords = @('cluster', 'HMI', 'NVR')
    $excludedDevices = @()
    $adDevices = @()

    foreach ($device in $allADDevices) {
        $deviceName = $device.Name
        $shouldExclude = $false
        $excludeReason = ""

        foreach ($keyword in $excludeKeywords) {
            if ($deviceName -like "*$keyword*") {
                $shouldExclude = $true
                $excludeReason = $keyword
                break
            }
        }

        if ($shouldExclude) {
            $excludedDevices += [PSCustomObject]@{
                Name = $device.Name
                DNSHostName = $device.DNSHostName
                Reason = "Contains keyword: $excludeReason"
            }
        }
        else {
            $adDevices += $device
        }
    }

    Write-Success "Retrieved $($allADDevices.Count) total active devices from Active Directory"
    if ($excludedDevices.Count -gt 0) {
        Write-Host "   Excluded $($excludedDevices.Count) devices (cluster/HMI/NVR systems)" -ForegroundColor Yellow
        Write-Host "   Final count for comparison: $($adDevices.Count)" -ForegroundColor Cyan
    }
}
catch {
    Write-ErrorMsg "Failed to retrieve Active Directory devices"
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    cmd /c pause
    exit 1
}

# ==============================
# Step 6: Compare - Devices in NinjaOne but NOT in AD
# ==============================
Write-Host ""
Write-Info "Step 6: Finding devices in NinjaOne but NOT in Active Directory..."
Write-Host "   Using enhanced matching algorithm..." -ForegroundColor Gray

$notInAD = @()
$matchedDevices = @()
$debugLog = @()

foreach ($ninjaDevice in $ninjaDevices) {
    # Get both names and clean them
    $ninjaSystemName = if ($ninjaDevice.systemName) { $ninjaDevice.systemName.Trim().ToLower() } else { "" }
    $ninjaDnsName = if ($ninjaDevice.dnsName) { $ninjaDevice.dnsName.Trim().ToLower() } else { "" }

    # Extract hostname from FQDN if present
    $ninjaDnsHostOnly = if ($ninjaDnsName -match '^([^.]+)') { $matches[1] } else { "" }

    # Skip if we have no valid names
    if ([string]::IsNullOrWhiteSpace($ninjaSystemName) -and [string]::IsNullOrWhiteSpace($ninjaDnsName)) {
        $debugLog += "SKIP: NinjaDevice ID $($ninjaDevice.id) - No valid names"
        continue
    }

    # Try to find match in AD with multiple criteria
    $existsInAD = $null

    foreach ($adDevice in $adDevices) {
        $adName = if ($adDevice.Name) { $adDevice.Name.Trim().ToLower() } else { "" }
        $adDnsName = if ($adDevice.DNSHostName) { $adDevice.DNSHostName.Trim().ToLower() } else { "" }
        $adDnsHostOnly = if ($adDnsName -match '^([^.]+)') { $matches[1] } else { "" }

        # Check multiple matching conditions
        $nameMatch = $false
        $matchReason = ""

        # Condition 1: Exact system name match
        if (-not [string]::IsNullOrWhiteSpace($ninjaSystemName) -and
            -not [string]::IsNullOrWhiteSpace($adName) -and
            $ninjaSystemName -eq $adName) {
            $nameMatch = $true
            $matchReason = "SystemName exact match"
        }

        # Condition 2: Full DNS name match
        if (-not $nameMatch -and
            -not [string]::IsNullOrWhiteSpace($ninjaDnsName) -and
            -not [string]::IsNullOrWhiteSpace($adDnsName) -and
            $ninjaDnsName -eq $adDnsName) {
            $nameMatch = $true
            $matchReason = "DNS FQDN exact match"
        }

        # Condition 3: System name matches AD hostname (no domain)
        if (-not $nameMatch -and
            -not [string]::IsNullOrWhiteSpace($ninjaSystemName) -and
            -not [string]::IsNullOrWhiteSpace($adDnsHostOnly) -and
            $ninjaSystemName -eq $adDnsHostOnly) {
            $nameMatch = $true
            $matchReason = "SystemName matches AD hostname"
        }

        # Condition 4: DNS hostname (no domain) matches AD name
        if (-not $nameMatch -and
            -not [string]::IsNullOrWhiteSpace($ninjaDnsHostOnly) -and
            -not [string]::IsNullOrWhiteSpace($adName) -and
            $ninjaDnsHostOnly -eq $adName) {
            $nameMatch = $true
            $matchReason = "DNS hostname matches AD name"
        }

        # Condition 5: DNS hostname matches AD hostname
        if (-not $nameMatch -and
            -not [string]::IsNullOrWhiteSpace($ninjaDnsHostOnly) -and
            -not [string]::IsNullOrWhiteSpace($adDnsHostOnly) -and
            $ninjaDnsHostOnly -eq $adDnsHostOnly) {
            $nameMatch = $true
            $matchReason = "DNS hostnames match"
        }

        if ($nameMatch) {
            $existsInAD = $adDevice
            $debugLog += "MATCH: Ninja '$ninjaSystemName' <-> AD '$adName' | Reason: $matchReason"

            # Track matched pairs for verification
            $matchedDevices += [PSCustomObject]@{
                NinjaSystemName = $ninjaDevice.systemName
                NinjaDNSName    = $ninjaDevice.dnsName
                ADName          = $adDevice.Name
                ADDNSName       = $adDevice.DNSHostName
                MatchReason     = $matchReason
            }
            break
        }
    }

    if (-not $existsInAD) {
        $debugLog += "NO MATCH: Ninja '$ninjaSystemName' (DNS: $ninjaDnsName) - Not found in AD"

        $notInAD += [PSCustomObject]@{
            DeviceID          = $ninjaDevice.id
            SystemName        = $ninjaDevice.systemName
            DNSName           = $ninjaDevice.dnsName
            NodeClass         = $ninjaDevice.nodeClass
            LastContact       = $ninjaDevice.lastContact
            Offline           = $ninjaDevice.offline
            ApprovalStatus    = $ninjaDevice.approvalStatus
            Status            = "Not in AD"
            SearchedNames     = "$ninjaSystemName | $ninjaDnsName | $ninjaDnsHostOnly"
        }
    }
}

Write-Success "Found $($notInAD.Count) devices in NinjaOne but NOT in AD"
Write-Host "   Matched devices: $($matchedDevices.Count)" -ForegroundColor Gray

# ==============================
# Step 7: Compare - Devices in AD but NOT in NinjaOne
# ==============================
Write-Host ""
Write-Info "Step 7: Finding devices in Active Directory but NOT in NinjaOne..."
Write-Host "   Using enhanced matching algorithm..." -ForegroundColor Gray

$notInNinja = @()

foreach ($adDevice in $adDevices) {
    # Get both names and clean them
    $adName = if ($adDevice.Name) { $adDevice.Name.Trim().ToLower() } else { "" }
    $adDnsName = if ($adDevice.DNSHostName) { $adDevice.DNSHostName.Trim().ToLower() } else { "" }

    # Extract hostname from FQDN if present
    $adDnsHostOnly = if ($adDnsName -match '^([^.]+)') { $matches[1] } else { "" }

    # Skip if we have no valid names
    if ([string]::IsNullOrWhiteSpace($adName) -and [string]::IsNullOrWhiteSpace($adDnsName)) {
        $debugLog += "SKIP: AD Device '$($adDevice.Name)' - No valid names"
        continue
    }

    # Try to find match in NinjaOne with multiple criteria
    $existsInNinja = $null

    foreach ($ninjaDevice in $ninjaDevices) {
        $ninjaSystemName = if ($ninjaDevice.systemName) { $ninjaDevice.systemName.Trim().ToLower() } else { "" }
        $ninjaDnsName = if ($ninjaDevice.dnsName) { $ninjaDevice.dnsName.Trim().ToLower() } else { "" }
        $ninjaDnsHostOnly = if ($ninjaDnsName -match '^([^.]+)') { $matches[1] } else { "" }

        # Check multiple matching conditions
        $nameMatch = $false
        $matchReason = ""

        # Condition 1: Exact name match
        if (-not [string]::IsNullOrWhiteSpace($adName) -and
            -not [string]::IsNullOrWhiteSpace($ninjaSystemName) -and
            $adName -eq $ninjaSystemName) {
            $nameMatch = $true
            $matchReason = "Name exact match"
        }

        # Condition 2: Full DNS name match
        if (-not $nameMatch -and
            -not [string]::IsNullOrWhiteSpace($adDnsName) -and
            -not [string]::IsNullOrWhiteSpace($ninjaDnsName) -and
            $adDnsName -eq $ninjaDnsName) {
            $nameMatch = $true
            $matchReason = "DNS FQDN exact match"
        }

        # Condition 3: AD name matches Ninja hostname (no domain)
        if (-not $nameMatch -and
            -not [string]::IsNullOrWhiteSpace($adName) -and
            -not [string]::IsNullOrWhiteSpace($ninjaDnsHostOnly) -and
            $adName -eq $ninjaDnsHostOnly) {
            $nameMatch = $true
            $matchReason = "AD name matches Ninja hostname"
        }

        # Condition 4: AD hostname (no domain) matches Ninja system name
        if (-not $nameMatch -and
            -not [string]::IsNullOrWhiteSpace($adDnsHostOnly) -and
            -not [string]::IsNullOrWhiteSpace($ninjaSystemName) -and
            $adDnsHostOnly -eq $ninjaSystemName) {
            $nameMatch = $true
            $matchReason = "AD hostname matches Ninja name"
        }

        # Condition 5: Hostnames match (no domains)
        if (-not $nameMatch -and
            -not [string]::IsNullOrWhiteSpace($adDnsHostOnly) -and
            -not [string]::IsNullOrWhiteSpace($ninjaDnsHostOnly) -and
            $adDnsHostOnly -eq $ninjaDnsHostOnly) {
            $nameMatch = $true
            $matchReason = "Hostnames match"
        }

        if ($nameMatch) {
            $existsInNinja = $ninjaDevice
            $debugLog += "MATCH: AD '$adName' <-> Ninja '$ninjaSystemName' | Reason: $matchReason"
            break
        }
    }

    if (-not $existsInNinja) {
        $debugLog += "NO MATCH: AD '$adName' (DNS: $adDnsName) - Not found in NinjaOne"

        $notInNinja += [PSCustomObject]@{
            ComputerName      = $adDevice.Name
            DNSHostName       = $adDevice.DNSHostName
            OperatingSystem   = $adDevice.OperatingSystem
            LastLogonDate     = $adDevice.LastLogonDate
            DistinguishedName = $adDevice.DistinguishedName
            Description       = $adDevice.Description
            Status            = "Not in NinjaOne"
            SearchedNames     = "$adName | $adDnsName | $adDnsHostOnly"
        }
    }
}

Write-Success "Found $($notInNinja.Count) devices in AD but NOT in NinjaOne"

# ==============================
# Step 8: Export Results
# ==============================
Write-Host ""
Write-Info "Step 8: Exporting results to $ExportPath..."

# Create export directory if it doesn't exist
if (-not (Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
}

# Export: Devices in NinjaOne but NOT in AD
$notInAD_File = Join-Path $ExportPath "NinjaOne_NotInAD_$timestamp.csv"
$notInAD | Export-Csv -Path $notInAD_File -NoTypeInformation -Encoding UTF8
Write-Success "Exported: NinjaOne_NotInAD_$timestamp.csv"

# Export: Devices in AD but NOT in NinjaOne
$notInNinja_File = Join-Path $ExportPath "AD_NotInNinjaOne_$timestamp.csv"
$notInNinja | Export-Csv -Path $notInNinja_File -NoTypeInformation -Encoding UTF8
Write-Success "Exported: AD_NotInNinjaOne_$timestamp.csv"

# Export: All NinjaOne devices
$allNinja_File = Join-Path $ExportPath "NinjaOne_AllDevices_$timestamp.csv"
$ninjaDevices | Select-Object id, systemName, dnsName, nodeClass, lastContact, organizationId |
    Export-Csv -Path $allNinja_File -NoTypeInformation -Encoding UTF8
Write-Success "Exported: NinjaOne_AllDevices_$timestamp.csv"

# Export: All AD devices
$allAD_File = Join-Path $ExportPath "AD_AllDevices_$timestamp.csv"
$adDevices | Export-Csv -Path $allAD_File -NoTypeInformation -Encoding UTF8
Write-Success "Exported: AD_AllDevices_$timestamp.csv"

# Export: Excluded AD devices (cluster/HMI/NVR)
if ($excludedDevices.Count -gt 0) {
    $excluded_File = Join-Path $ExportPath "AD_ExcludedDevices_$timestamp.csv"
    $excludedDevices | Export-Csv -Path $excluded_File -NoTypeInformation -Encoding UTF8
    Write-Success "Exported: AD_ExcludedDevices_$timestamp.csv (cluster/HMI/NVR systems)"
}

# Export: Matched devices for verification
$matched_File = Join-Path $ExportPath "Matched_Devices_$timestamp.csv"
$matchedDevices | Export-Csv -Path $matched_File -NoTypeInformation -Encoding UTF8
Write-Success "Exported: Matched_Devices_$timestamp.csv (for verification)"

# Export: Debug log
$debugLog_File = Join-Path $ExportPath "Debug_Matching_Log_$timestamp.txt"
$debugLog | Out-File -FilePath $debugLog_File -Encoding UTF8
Write-Success "Exported: Debug_Matching_Log_$timestamp.txt"

# ==============================
# Step 9: Summary Statistics
# ==============================
Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "                    SUMMARY REPORT" -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Organization: " -NoNewline -ForegroundColor Gray
Write-Host "$($targetOrg.name) (ID: $OrganizationId)" -ForegroundColor White
Write-Host ""

Write-Host "Total Devices:" -ForegroundColor Yellow
Write-Host "  - NinjaOne Devices:  " -NoNewline -ForegroundColor Gray
Write-Host "$($ninjaDevices.Count)" -ForegroundColor White
Write-Host "  - AD Devices (all):  " -NoNewline -ForegroundColor Gray
Write-Host "$($allADDevices.Count)" -ForegroundColor White
if ($excludedDevices.Count -gt 0) {
    Write-Host "  - AD Excluded:       " -NoNewline -ForegroundColor Gray
    Write-Host "$($excludedDevices.Count) " -NoNewline -ForegroundColor Yellow
    Write-Host "(cluster/HMI/NVR)" -ForegroundColor Gray
    Write-Host "  - AD Used:           " -NoNewline -ForegroundColor Gray
    Write-Host "$($adDevices.Count)" -ForegroundColor Cyan
}
Write-Host ""

Write-Host "Comparison Results:" -ForegroundColor Yellow
Write-Host "  - In NinjaOne only:  " -NoNewline -ForegroundColor Gray
if ($notInAD.Count -gt 0) {
    Write-Host "$($notInAD.Count)" -ForegroundColor Red
} else {
    Write-Host "0" -ForegroundColor Green
}

Write-Host "  - In AD only:        " -NoNewline -ForegroundColor Gray
if ($notInNinja.Count -gt 0) {
    Write-Host "$($notInNinja.Count)" -ForegroundColor Red
} else {
    Write-Host "0" -ForegroundColor Green
}
Write-Host ""

# Calculate match statistics
$matchedCount = $matchedDevices.Count
$matchRate = if ($adDevices.Count -gt 0) {
    [math]::Round(($matchedCount / $adDevices.Count) * 100, 2)
} else {
    0
}

Write-Host "Match Statistics:" -ForegroundColor Yellow
Write-Host "  - Devices in both:   " -NoNewline -ForegroundColor Gray
Write-Host "$matchedCount" -ForegroundColor Green
Write-Host "  - Match rate:        " -NoNewline -ForegroundColor Gray
Write-Host "$matchRate%" -ForegroundColor $(if ($matchRate -ge 90) { "Green" } elseif ($matchRate -ge 75) { "Yellow" } else { "Red" })
Write-Host ""

Write-Host "Export Location:" -ForegroundColor Yellow
Write-Host "  $ExportPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "  VERIFICATION FILES:" -ForegroundColor Yellow
Write-Host "     - Matched_Devices_$timestamp.csv - Shows all successful matches" -ForegroundColor Cyan
Write-Host "     - Debug_Matching_Log_$timestamp.txt - Detailed matching log" -ForegroundColor Cyan
Write-Host ""

# Summary text file
$summaryFile = Join-Path $ExportPath "Summary_$timestamp.txt"
$summaryText = @"
NinjaOne vs Active Directory Comparison Report
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Export Location: $ExportPath
=======================================================

Organization: $($targetOrg.name) (ID: $OrganizationId)

DEVICE COUNTS:
- Total NinjaOne Devices: $($ninjaDevices.Count)
- Total AD Devices (all): $($allADDevices.Count)
- AD Devices Excluded: $($excludedDevices.Count) (cluster/HMI/NVR systems)
- AD Devices Used for Comparison: $($adDevices.Count)

EXCLUSION CRITERIA:
Devices containing these keywords in their name are automatically excluded:
- "cluster" (cluster nodes)
- "HMI" (Human-Machine Interface systems)
- "NVR" (Network Video Recorder systems)

COMPARISON RESULTS:
- Devices in NinjaOne but NOT in AD: $($notInAD.Count)
- Devices in AD but NOT in NinjaOne: $($notInNinja.Count)
- Devices successfully matched: $matchedCount
- Match rate: $matchRate%

EXPORTED FILES:
- NinjaOne_NotInAD_$timestamp.csv ($($notInAD.Count) records)
- AD_NotInNinjaOne_$timestamp.csv ($($notInNinja.Count) records)
- NinjaOne_AllDevices_$timestamp.csv ($($ninjaDevices.Count) records)
- AD_AllDevices_$timestamp.csv ($($adDevices.Count) records)
$(if ($excludedDevices.Count -gt 0) { "- AD_ExcludedDevices_$timestamp.csv ($($excludedDevices.Count) records) <- EXCLUDED SYSTEMS`n" })- Matched_Devices_$timestamp.csv ($matchedCount records) <- VERIFICATION FILE
- Debug_Matching_Log_$timestamp.txt (detailed matching log)

MATCHING CRITERIA USED:
1. Exact system name match (case-insensitive)
2. Full DNS FQDN match (case-insensitive)
3. System name vs hostname (without domain)
4. Hostname vs hostname (without domains)
5. Cross-matching with whitespace trimming

VERIFICATION INSTRUCTIONS:
If you find devices in NinjaOne_NotInAD.csv that you believe exist in AD:
1. Open Matched_Devices_$timestamp.csv to see all successful matches
2. Open Debug_Matching_Log_$timestamp.txt for detailed matching process
3. Search for the device name in the debug log
4. Check what names were used for matching (in SearchedNames column)
5. Verify the device names match exactly (check for trailing spaces, case differences)

Note: Cluster nodes, HMI systems, and NVR systems are automatically excluded
      from comparison as they typically don't need NinjaOne monitoring.

=======================================================
"@

$summaryText | Out-File -FilePath $summaryFile -Encoding UTF8
Write-Success "Exported: Summary_$timestamp.txt"

# ==============================
# Step 10: Display Samples
# ==============================
if ($notInAD.Count -gt 0) {
    Write-Host ""
    Write-Host "Sample devices in NinjaOne but NOT in AD:" -ForegroundColor Yellow
    $notInAD | Select-Object -First 5 SystemName, DNSName, LastContact | Format-Table -AutoSize
    if ($notInAD.Count -gt 5) {
        Write-Host "... and $($notInAD.Count - 5) more (see CSV file)" -ForegroundColor Gray
    }
}

if ($notInNinja.Count -gt 0) {
    Write-Host ""
    Write-Host "Sample devices in AD but NOT in NinjaOne:" -ForegroundColor Yellow
    $notInNinja | Select-Object -First 5 ComputerName, DNSHostName, OperatingSystem | Format-Table -AutoSize
    if ($notInNinja.Count -gt 5) {
        Write-Host "... and $($notInNinja.Count - 5) more (see CSV file)" -ForegroundColor Gray
    }
}

# ==============================
# Completion
# ==============================
Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Success "Script completed successfully!"
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

start $notInAD_File
start $notInNinja_File
