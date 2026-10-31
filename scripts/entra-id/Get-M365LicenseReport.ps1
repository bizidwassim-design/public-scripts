<#
.SYNOPSIS
    Per-user Microsoft 365 licence and mailbox-type report (Graph + Exchange Online) exported to XLSX.
.DESCRIPTION
    Connects to Microsoft Graph and Exchange Online, maps SKU part numbers to friendly names,
    lists every licensed user with department, title, enabled state, up to five licences and the
    mailbox RecipientTypeDetails, then exports to Excel (ImportExcel) or a semicolon CSV fallback.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Microsoft.Graph | ExchangeOnlineManagement | ImportExcel (installed automatically if missing)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-M365LicenseReport.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$OutputFolder = "C:\Scripts\Reports"
$ReportTitle  = "Contoso - User License Report"
# -------------------------------------------------------------------------

# ============================================================
# User License & Mailbox Report - Graph API (V5 - FINAL)
# ============================================================

# --- Connect Graph ---
Connect-MgGraph -Scopes "User.Read.All","Directory.Read.All","Organization.Read.All" -NoWelcome
Write-Host "Graph connected." -ForegroundColor Green

# --- Connect Exchange ---
$exchangeConnected = $false
try {
    Connect-ExchangeOnline -ErrorAction Stop
    $exchangeConnected = $true
    Write-Host "Exchange Online connected." -ForegroundColor Green
} catch {
    try {
        Connect-ExchangeOnline -Device -ErrorAction Stop
        $exchangeConnected = $true
        Write-Host "Exchange Online connected (device code)." -ForegroundColor Green
    } catch {
        Write-Host "WARNING: Exchange Online not connected." -ForegroundColor Yellow
    }
}

# ============================================================
# Step 1: Build friendly name lookup
# ============================================================
Write-Host "`nBuilding license name lookup..." -ForegroundColor Cyan

$friendlyNames = @{
    "SPE_E3"="Microsoft 365 E3"
    "SPE_E5"="Microsoft 365 E5"
    "SPE_F1"="Microsoft 365 F3"
    "M365_F1"="Microsoft 365 F1"
    "SPB"="Microsoft 365 Business Premium"
    "SMB_BUSINESS_PREMIUM"="Microsoft 365 Business Standard"
    "BUSINESS_PREMIUM"="Microsoft 365 Business Premium"
    "BUSINESS_BASIC"="Microsoft 365 Business Basic"
    "BUSINESS_STANDARD"="Microsoft 365 Business Standard"
    "ENTERPRISEPACK"="Office 365 E3"
    "ENTERPRISEPREMIUM"="Office 365 E5"
    "STANDARDPACK"="Office 365 E1"
    "DESKLESSPACK"="Office 365 F3"
    "OFFICESUBSCRIPTION"="Microsoft 365 Apps for Enterprise"
    "O365_BUSINESS"="Microsoft 365 Apps for Business"
    "EXCHANGESTANDARD"="Exchange Online Plan 1"
    "EXCHANGEENTERPRISE"="Exchange Online Plan 2"
    "EXCHANGEARCHIVE_ADDON"="Exchange Online Archiving"
    "EXCHANGEDESKLESS"="Exchange Online Kiosk"
    "AAD_PREMIUM"="Azure AD Premium P1"
    "AAD_PREMIUM_P2"="Azure AD Premium P2"
    "EMS"="Enterprise Mobility + Security E3"
    "EMSPREMIUM"="Enterprise Mobility + Security E5"
    "INTUNE_A"="Microsoft Intune Plan 1"
    "ATP_ENTERPRISE"="Defender for Office 365 P1"
    "THREAT_INTELLIGENCE"="Defender for Office 365 P2"
    "WIN_DEF_ATP"="Defender for Endpoint P1"
    "MDATP_XPLAT"="Defender for Endpoint P2"
    "MCOEV"="Teams Phone System"
    "MCOMEETADV"="Teams Audio Conferencing"
    "MCOPSTN1"="Teams Domestic Calling"
    "MCOPSTN2"="Teams Intl Calling"
    "MCOPSTN_5"="Teams Calling 120min"
    "MCOCAP"="Common Area Phone"
    "POWER_BI_PRO"="Power BI Pro"
    "PBI_PREMIUM_PER_USER"="Power BI Premium Per User"
    "POWER_BI_STANDARD"="Power BI Free"
    "FLOW_FREE"="Power Automate Free"
    "FLOW_PER_USER"="Power Automate Per User"
    "POWERAPPS_VIRAL"="Power Apps Trial"
    "POWERAPPS_PER_APP_IW"="Power Apps Per App IW"
    "POWERAPPS_PER_USER"="Power Apps Per User"
    "PROJECTPROFESSIONAL"="Project Plan 3"
    "PROJECTESSENTIALS"="Project Online Essentials"
    "VISIOCLIENT"="Visio Plan 2"
    "VISIOONLINE_PLAN1"="Visio Plan 1"
    "TEAMS_EXPLORATORY"="Teams Exploratory"
    "PHONESYSTEM_VIRTUALUSER"="Teams Phone Virtual User"
    "Microsoft_Teams_Premium"="Microsoft Teams Premium"
    "MICROSOFT_FABRIC_FREE"="Microsoft Fabric Free"
    "RIGHTSMANAGEMENT"="Azure Information Protection P1"
    "STREAM"="Microsoft Stream"
    "MEETING_ROOM"="Teams Rooms Standard"
    "CCIBOTS_PRIVPREV_VIRAL"="Power Virtual Agents Trial"
    "WINDOWS_STORE"="Windows Store for Business"
    "DYN365_FINANCE"="Dynamics 365 Finance"
    "DYN365_ENTERPRISE_PLAN1"="Dynamics 365 Plan 1"
    "DYN365_ENTERPRISE_SALES"="Dynamics 365 Sales Enterprise"
    "FORMS_PRO"="Dynamics 365 Customer Voice"
    "MICROSOFT_365_COPILOT"="Microsoft 365 Copilot"
    "Microsoft_Copilot_Pro"="Microsoft Copilot Pro"
}

# ============================================================
# Step 2: Get ALL users
# ============================================================
Write-Host "Retrieving all users..." -ForegroundColor Cyan
$allUsers = Get-MgUser -All -Property Id,UserPrincipalName,DisplayName,AccountEnabled,Department,JobTitle
Write-Host "Total users: $($allUsers.Count)" -ForegroundColor Green

# ============================================================
# Step 3: Process each user
# ============================================================
Write-Host "Fetching license details per user..." -ForegroundColor Cyan

$counter = 0
$results = [System.Collections.ArrayList]::new()

foreach ($user in $allUsers) {
    $counter++
    if ($counter % 50 -eq 0) { Write-Host "  $counter / $($allUsers.Count)..." }

    # Get licenses via Get-MgUserLicenseDetail (reliable method)
    $licenseList = @()
    try {
        $licDetails = Get-MgUserLicenseDetail -UserId $user.Id -ErrorAction Stop
        foreach ($ld in $licDetails) {
            $partName = $ld.SkuPartNumber
            if (-not [string]::IsNullOrEmpty($partName)) {
                if ($friendlyNames.ContainsKey($partName)) {
                    $licenseList += $friendlyNames[$partName]
                } else {
                    $licenseList += $partName
                }
            }
        }
    } catch { }

    # Skip unlicensed users
    if ($licenseList.Count -eq 0) { continue }

    # Mailbox type
    $MailboxType = ""
    if ($exchangeConnected) {
        try {
            $mbx = Get-Mailbox -Identity $user.UserPrincipalName -ErrorAction Stop
            $MailboxType = $mbx.RecipientTypeDetails
        } catch { $MailboxType = "No Mailbox" }
    }

    # Clean strings to remove any problematic characters
    $cleanDisplayName = ($user.DisplayName -replace '[";]','')
    $cleanDepartment  = ($user.Department  -replace '[";]','')
    $cleanJobTitle    = ($user.JobTitle    -replace '[";]','')

    $null = $results.Add([PSCustomObject]@{
        DisplayName       = $cleanDisplayName
        UserPrincipalName = $user.UserPrincipalName
        Department        = $cleanDepartment
        JobTitle          = $cleanJobTitle
        AccountDisabled   = (-not $user.AccountEnabled).ToString()
        LicenseCount      = $licenseList.Count
        License1          = if ($licenseList.Count -ge 1) { $licenseList[0] } else { "" }
        License2          = if ($licenseList.Count -ge 2) { $licenseList[1] } else { "" }
        License3          = if ($licenseList.Count -ge 3) { $licenseList[2] } else { "" }
        License4          = if ($licenseList.Count -ge 4) { $licenseList[3] } else { "" }
        License5          = if ($licenseList.Count -ge 5) { $licenseList[4] } else { "" }
        AllLicenses       = $licenseList -join " | "
        MailboxType       = $MailboxType
    })
}

# ============================================================
# Step 4: Export as XLSX (avoids all CSV encoding issues)
# ============================================================
Write-Host "`nExporting..." -ForegroundColor Cyan

# Method 1: Try Excel export via ImportExcel module
$useExcel = $false
if (Get-Module -ListAvailable -Name ImportExcel) {
    $useExcel = $true
} else {
    Write-Host "Installing ImportExcel module for clean XLSX output..." -ForegroundColor Yellow
    try {
        Install-Module ImportExcel -Force -Scope CurrentUser -ErrorAction Stop
        $useExcel = $true
    } catch {
        Write-Host "Could not install ImportExcel. Falling back to CSV." -ForegroundColor Yellow
    }
}

if ($useExcel) {
    $outputPath = Join-Path $OutputFolder "user_license_mailbox_details.xlsx"
    $results | Sort-Object DisplayName | Export-Excel -Path $outputPath `
        -AutoSize -AutoFilter -FreezeTopRow `
        -WorksheetName "Licensed Users" `
        -Title $ReportTitle `
        -TitleBold
    Write-Host "Exported $($results.Count) users to $outputPath" -ForegroundColor Green
} else {
    # Fallback: CSV with UTF8-BOM and semicolon delimiter for Excel compatibility
    $outputPath = Join-Path $OutputFolder "user_license_mailbox_details.csv"
    $utf8Bom = New-Object System.Text.UTF8Encoding $true
    $csvContent = ($results | Sort-Object DisplayName | ConvertTo-Csv -NoTypeInformation -Delimiter ";") -join "`r`n"
    [System.IO.File]::WriteAllText($outputPath, $csvContent, $utf8Bom)
    Write-Host "Exported $($results.Count) users to $outputPath (semicolon-delimited)" -ForegroundColor Green
}

Start-Process $outputPath

# Cleanup
Disconnect-MgGraph
if ($exchangeConnected) { Disconnect-ExchangeOnline -Confirm:$false }
