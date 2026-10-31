<#
.SYNOPSIS
    Report disabled AD users that still hold Microsoft 365 licences (Graph), with their OU and extensionAttribute8.
.DESCRIPTION
    Step 1 tags every user in the "temporarily disabled" OUs with extensionAttribute8=TemporarilyDisabled.
    Step 2 pulls all users from Microsoft Graph, keeps the disabled ones that still have AssignedLicenses,
    maps SKU IDs to SKU part numbers, enriches each row with the on-prem OU and extensionAttribute8, exports
    a timestamped CSV and emails an HTML table of the result. Must run on a domain-joined host.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | Microsoft.Graph.Authentication | Microsoft.Graph.Users | Microsoft.Graph.Identity.DirectoryManagement | SMTP relay
    Impact      : Modifies AD (sets extensionAttribute8 on users in the target OUs); read-only on Entra ID
    License     : MIT
.EXAMPLE
    .\Report-DisabledUsersWithLicenses.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# OUs whose users are "temporarily disabled" (seasonal, long-term absence...)
$TargetOUs    = @(
    "OU=Disabled-Seasonal,OU=Disabled,OU=Users,DC=corp,DC=contoso,DC=local",
    "OU=Disabled-LongTermAbsence,OU=Disabled,OU=Users,DC=corp,DC=contoso,DC=local"
)
$TenantDomain = "contoso.onmicrosoft.com"   # cloud-only accounts to exclude
$smtpServer   = "smtp.contoso.com"
$from         = "it-support@contoso.com"
$to           = "it-support@contoso.com"
$bcc          = "security@contoso.com"
# -------------------------------------------------------------------------

# Enhanced script using Microsoft Graph API instead of MSOnline
# Requires Microsoft.Graph PowerShell SDK

# Import required modules
Import-Module ActiveDirectory -ErrorAction Stop
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Users -ErrorAction Stop
Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop

# Function to set extensionAttribute8 for users in specific OUs
function Set-ExtensionAttributeForDisabledOUs {
    try {
        Write-Host "=" * 80 -ForegroundColor Magenta
        Write-Host "STEP 1: Setting extensionAttribute8 for users in disabled OUs..." -ForegroundColor Magenta
        Write-Host "=" * 80 -ForegroundColor Magenta

        # Define the target OUs
        $targetOUs = $TargetOUs

        $totalProcessed = 0
        $totalModified = 0
        $errors = @()

        foreach ($ou in $targetOUs) {
            Write-Host "`nProcessing OU: $ou" -ForegroundColor Yellow

            try {
                # Get all users in this specific OU (not recursive)
                $usersInOU = Get-ADUser -SearchBase $ou -SearchScope OneLevel -Filter * -Properties extensionAttribute8, Enabled

                Write-Host "Found $($usersInOU.Count) users in this OU" -ForegroundColor Cyan

                if ($usersInOU.Count -eq 0) {
                    Write-Host "No users found in OU: $ou" -ForegroundColor Yellow
                    continue
                }

                $ouProcessed = 0
                $ouModified = 0

                foreach ($user in $usersInOU) {
                    $ouProcessed++
                    $totalProcessed++

                    try {
                        $currentValue = $user.extensionAttribute8
                        $needsUpdate = $false

                        # Check if we need to update the attribute
                        if ([string]::IsNullOrEmpty($currentValue)) {
                            $needsUpdate = $true
                            $action = "Setting (was empty)"
                        } elseif ($currentValue -ne "TemporarilyDisabled") {
                            $needsUpdate = $true
                            $action = "Updating (was: $currentValue)"
                        } else {
                            $action = "Already set correctly"
                        }

                        Write-Host "  [$ouProcessed/$($usersInOU.Count)] $($user.SamAccountName) - $action" -ForegroundColor Gray

                        if ($needsUpdate) {
                            # Set the extensionAttribute8 to "TemporarilyDisabled"
                            Set-ADUser -Identity $user.SamAccountName -Replace @{extensionAttribute8="TemporarilyDisabled"}
                            $ouModified++
                            $totalModified++
                            Write-Host "    [OK] Updated successfully" -ForegroundColor Green
                        }
                    }
                    catch {
                        $errorMsg = "Failed to update user $($user.SamAccountName): $_"
                        $errors += $errorMsg
                        Write-Host "    [X] Error: $_" -ForegroundColor Red
                    }
                }

                Write-Host "OU Summary - Processed: $ouProcessed, Modified: $ouModified" -ForegroundColor Cyan
            }
            catch {
                $errorMsg = "Failed to process OU '$ou': $_"
                $errors += $errorMsg
                Write-Host "Error processing OU: $_" -ForegroundColor Red
            }
        }

        # Final summary
        Write-Host "`n" + "=" * 60 -ForegroundColor Magenta
        Write-Host "EXTENSION ATTRIBUTE UPDATE SUMMARY:" -ForegroundColor Magenta
        Write-Host "=" * 60 -ForegroundColor Magenta
        Write-Host "Total users processed: $totalProcessed" -ForegroundColor White
        Write-Host "Total users modified: $totalModified" -ForegroundColor Green
        Write-Host "Total errors: $($errors.Count)" -ForegroundColor $(if ($errors.Count -gt 0) { "Red" } else { "Green" })

        if ($errors.Count -gt 0) {
            Write-Host "`nErrors encountered:" -ForegroundColor Red
            $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }

        Write-Host "`nWaiting 5 seconds for AD replication before continuing..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5

        return $totalModified -gt 0
    }
    catch {
        Write-Error "Critical error in Set-ExtensionAttributeForDisabledOUs: $_"
        return $false
    }
}
function Connect-ToGraph {
    try {
        # Connect to Microsoft Graph with required permissions
        Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All", "Organization.Read.All" -NoWelcome
        Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green

        # Test the connection
        $context = Get-MgContext
        Write-Host "Connected as: $($context.Account)" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        exit 1
    }
}

# Function to get all AD users with their extension attributes and OU information
function Get-ADUsersWithExtensionAttribute8 {
    try {
        Write-Host "Retrieving all AD users with extension attributes and OU information..." -ForegroundColor Yellow

        # Get all users with extensionAttribute8 and DistinguishedName for OU extraction
        $allADUsers = Get-ADUser -Filter * -Properties extensionAttribute8, DistinguishedName, Enabled

        # Create array of user objects with OU information
        $adUsers = @()
        foreach ($user in $allADUsers) {
            # Extract OU from DistinguishedName
            $ouPath = ""
            if ($user.DistinguishedName) {
                # Remove the CN part and get the OU path
                $dnParts = $user.DistinguishedName -split ","
                $ouParts = $dnParts | Where-Object { $_ -like "OU=*" -or $_ -like "DC=*" }
                $ouPath = ($ouParts -join ",").Trim()

                # If no OU found, it might be in a container
                if (-not $ouPath -or $ouPath -eq "") {
                    $containerParts = $dnParts | Where-Object { $_ -like "CN=*" -and $_ -ne $dnParts[0] }
                    if ($containerParts) {
                        $ouPath = ($containerParts + ($dnParts | Where-Object { $_ -like "DC=*" })) -join ","
                    } else {
                        $ouPath = "Default Container"
                    }
                }
            }

            $adUsers += [PSCustomObject]@{
                Name                 = $user.Name
                SamAccountName       = $user.SamAccountName
                UserPrincipalName    = $user.UserPrincipalName
                ExtensionAttribute8  = if ($user.extensionAttribute8) { $user.extensionAttribute8 } else { "Not Set" }
                OrganizationalUnit   = $ouPath
                ADAccountEnabled     = $user.Enabled
            }
        }

        Write-Host "Retrieved $($adUsers.Count) AD users with extension attributes and OU information" -ForegroundColor Green
        return $adUsers
    }
    catch {
        Write-Error "Failed to retrieve AD users: $_"
        return @()
    }
}

# Function to get disabled users with licenses from Microsoft Graph
function Get-DisabledUsersWithLicenses {
    param (
        [array]$ADUsers
    )

    try {
        Write-Host "Retrieving disabled users with licenses from Microsoft Graph..." -ForegroundColor Yellow

        # Get all users from Microsoft Graph with required properties including extension attributes
        $allUsers = Get-MgUser -All -Property "UserPrincipalName,AccountEnabled,AssignedLicenses,DisplayName,OnPremisesExtensionAttributes"

        # Filter for disabled users with licenses, excluding cloud-only tenant accounts
        $disabledUsers = $allUsers | Where-Object {
            $_.AccountEnabled -eq $false -and
            $_.AssignedLicenses.Count -gt 0 -and
            $_.UserPrincipalName -notlike "*@$TenantDomain"
        }

        Write-Host "Found $($disabledUsers.Count) disabled users with licenses" -ForegroundColor Green

        # Get organization info for license mapping
        $organization = Get-MgOrganization
        $tenantId = $organization.Id

        # Get available SKUs for license name mapping
        $subscribedSkus = Get-MgSubscribedSku
        $skuHashTable = @{}
        foreach ($sku in $subscribedSkus) {
            $skuHashTable[$sku.SkuId] = $sku.SkuPartNumber
        }

        # Get license information for each disabled user
        $licenseReport = @()
        $counter = 0
        foreach ($user in $disabledUsers) {
            $counter++
            Write-Progress -Activity "Processing Users" -Status "Processing user $counter of $($disabledUsers.Count): $($user.UserPrincipalName)" -PercentComplete (($counter / $disabledUsers.Count) * 100)

            try {
                # Get license names from assigned licenses
                $licenseNames = @()
                foreach ($license in $user.AssignedLicenses) {
                    if ($skuHashTable.ContainsKey($license.SkuId)) {
                        $licenseNames += $skuHashTable[$license.SkuId]
                    } else {
                        $licenseNames += $license.SkuId
                    }
                }
                $licenseString = $licenseNames -join ", "

                # Get ExtensionAttribute8 from multiple sources with priority
                $extensionAttribute8 = "Not Set"

                # First try: Graph API OnPremisesExtensionAttributes
                if ($user.OnPremisesExtensionAttributes -and $user.OnPremisesExtensionAttributes.ExtensionAttribute8) {
                    $extensionAttribute8 = $user.OnPremisesExtensionAttributes.ExtensionAttribute8
                    Write-Host "  Found ExtensionAttribute8 from Graph: $extensionAttribute8" -ForegroundColor DarkGreen
                }
                # Second try: AD array lookup
                elseif ($ADUsers.Count -gt 0) {
                    $matchingADUser = $ADUsers | Where-Object { $_.UserPrincipalName -eq $user.UserPrincipalName }
                    if ($matchingADUser -and $matchingADUser.ExtensionAttribute8 -ne "Not Set") {
                        $extensionAttribute8 = $matchingADUser.ExtensionAttribute8
                        Write-Host "  Found ExtensionAttribute8 from AD: $extensionAttribute8" -ForegroundColor DarkBlue
                    }
                }

                # Get OU information from AD data
                $organizationalUnit = "Unknown OU"
                if ($ADUsers.Count -gt 0) {
                    $matchingADUser = $ADUsers | Where-Object { $_.UserPrincipalName -eq $user.UserPrincipalName }
                    if ($matchingADUser) {
                        $organizationalUnit = $matchingADUser.OrganizationalUnit
                    }
                }

                $licenseReport += [PSCustomObject]@{
                    UserPrincipalName   = $user.UserPrincipalName
                    DisplayName         = $user.DisplayName
                    Licenses           = if ([string]::IsNullOrEmpty($licenseString)) { "No licenses found" } else { $licenseString }
                    ExtensionAttribute8 = $extensionAttribute8
                    OrganizationalUnit  = $organizationalUnit
                    AccountEnabled     = $user.AccountEnabled
                }
            }
            catch {
                Write-Warning "Failed to process user $($user.UserPrincipalName): $_"

                # Add user with basic info even if processing fails
                $matchingADUser = $ADUsers | Where-Object { $_.UserPrincipalName -eq $user.UserPrincipalName }
                $licenseReport += [PSCustomObject]@{
                    UserPrincipalName   = $user.UserPrincipalName
                    DisplayName         = $user.DisplayName
                    Licenses           = "Error retrieving licenses"
                    ExtensionAttribute8 = if ($matchingADUser) { $matchingADUser.ExtensionAttribute8 } else { "Error retrieving attribute" }
                    OrganizationalUnit  = if ($matchingADUser) { $matchingADUser.OrganizationalUnit } else { "Error retrieving OU" }
                    AccountEnabled     = $user.AccountEnabled
                }
            }
        }

        Write-Progress -Activity "Processing Users" -Completed
        return $licenseReport
    }
    catch {
        Write-Error "Failed to retrieve disabled users from Microsoft Graph: $_"
        Write-Host "Error details: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

# Function to generate HTML table
function New-HTMLTable {
    param (
        [array]$Data
    )

    if ($Data.Count -eq 0) {
        return "<p>No data to display.</p>"
    }

    $tableRows = $Data | ForEach-Object {
        "<tr>
            <td>$($_.UserPrincipalName)</td>
            <td>$($_.DisplayName)</td>
            <td>$($_.Licenses)</td>
            <td style='font-weight: bold; color: #d9534f;'>$($_.ExtensionAttribute8)</td>
            <td style='font-size: 0.9em; color: #666;'>$($_.OrganizationalUnit)</td>
        </tr>"
    }

    $htmlTable = @"
    <style>
        table { border-collapse: collapse; width: 100%; font-family: Arial, sans-serif; margin-top: 10px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; font-weight: bold; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .extension-attr { font-weight: bold; color: #d9534f; }
        .ou-path { font-size: 0.9em; color: #666; word-break: break-all; }
    </style>
    <table>
        <thead>
            <tr>
                <th>User Principal Name</th>
                <th>Display Name</th>
                <th>Licenses</th>
                <th>Extension Attribute 8</th>
                <th>Organizational Unit</th>
            </tr>
        </thead>
        <tbody>
            $($tableRows -join "`n")
        </tbody>
    </table>
"@

    return $htmlTable
}

# Function to send email report
function Send-EmailReport {
    param (
        [array]$LicenseData,
        [string]$CsvPath
    )

    # Generate HTML table
    $htmlTable = New-HTMLTable -Data $LicenseData

    # Email configuration
    $subject = "Disabled Active Directory Users with Assigned Microsoft 365 Licenses - $(Get-Date -Format 'yyyy-MM-dd')"

    $body = @"
    <html>
    <head>
        <title>Disabled Users License Report</title>
    </head>
    <body>
        <p>Hello Team,</p>
        <p>Please find below the report on disabled users with Microsoft 365 licenses.</p>
        <p>This report includes details about disabled users, their assigned licenses, and extension attributes.</p>
        <p><strong>Report Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Total Disabled Users with Licenses:</strong> $($LicenseData.Count)</p>
        <br>
        $htmlTable
        <br>
        <p>The detailed report is also attached as a CSV file.</p>
        <p>Best regards,<br>The Contoso IT Team</p>
    </body>
    </html>
"@

    try {
        $mailParams = @{
            SmtpServer = $smtpServer
            From = $from
            To = $to
            Bcc = $bcc
            Subject = $subject
            Body = $body
            BodyAsHtml = $true
            Priority = 'High'
            Encoding = [System.Text.Encoding]::UTF8
        }

        if (Test-Path $CsvPath) {
            $mailParams.Attachments = $CsvPath
        }

        Send-MailMessage @mailParams
        Write-Host "Email sent successfully to $to" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to send email: $_"
    }
}

# Main execution
try {
    Write-Host "Starting Disabled Users License Report Script..." -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan

    # STEP 1: Set extensionAttribute8 for users in specific OUs
    $attributesUpdated = Set-ExtensionAttributeForDisabledOUs

    if ($attributesUpdated) {
        Write-Host "`n[OK] Extension attributes updated successfully. Proceeding with report generation..." -ForegroundColor Green
    } else {
        Write-Host "`n! No extension attributes were updated, but continuing with report generation..." -ForegroundColor Yellow
    }

    Write-Host "`n" + "=" * 80 -ForegroundColor Cyan
    Write-Host "STEP 2: Generating License Report..." -ForegroundColor Cyan
    Write-Host "=" * 80 -ForegroundColor Cyan

    # Connect to Microsoft Graph
    Connect-ToGraph

    # Get AD users with extensionAttribute8
    $adUsersArray = Get-ADUsersWithExtensionAttribute8

    # Display summary of AD users with extension attributes
    $usersWithExtAttr = $adUsersArray | Where-Object { $_.ExtensionAttribute8 -ne "Not Set" }
    Write-Host "`nAD Summary:" -ForegroundColor Cyan
    Write-Host "- Total AD users processed: $($adUsersArray.Count)" -ForegroundColor White
    Write-Host "- Users with ExtensionAttribute8 set: $($usersWithExtAttr.Count)" -ForegroundColor White

    # Show sample of extension attributes
    if ($usersWithExtAttr.Count -gt 0) {
        Write-Host "`nSample Extension Attribute 8 values:" -ForegroundColor Yellow
        $usersWithExtAttr | Select-Object -First 5 | ForEach-Object {
            Write-Host "  $($_.UserPrincipalName) -> $($_.ExtensionAttribute8)" -ForegroundColor DarkYellow
        }
        if ($usersWithExtAttr.Count -gt 5) {
            Write-Host "  ... and $($usersWithExtAttr.Count - 5) more" -ForegroundColor DarkYellow
        }
    }

    # Get disabled users with licenses
    $disabledUsersReport = Get-DisabledUsersWithLicenses -ADUsers $adUsersArray

    # Process results
    if ($disabledUsersReport.Count -gt 0) {
        Write-Host "Processing $($disabledUsersReport.Count) disabled users with licenses..." -ForegroundColor Yellow

        # Export to CSV with timestamp
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $csvFileName = "disabled_users_licenses_$timestamp.csv"
        $disabledUsersReport | Export-Csv -Path $csvFileName -NoTypeInformation -Encoding UTF8

        Write-Host "Report exported to: $csvFileName" -ForegroundColor Green

        # Send email report
        Send-EmailReport -LicenseData $disabledUsersReport -CsvPath $csvFileName

        # Display summary
        Write-Host "`n" + "=" * 60 -ForegroundColor Cyan
        Write-Host "FINAL REPORT SUMMARY:" -ForegroundColor Cyan
        Write-Host "=" * 60 -ForegroundColor Cyan
        Write-Host "- Extension attributes updated in Step 1: $(if ($attributesUpdated) { 'Yes' } else { 'No' })" -ForegroundColor White
        Write-Host "- Total disabled users with licenses: $($disabledUsersReport.Count)" -ForegroundColor White
        Write-Host "- CSV file created: $csvFileName" -ForegroundColor White
        Write-Host "- Email sent successfully" -ForegroundColor White
    }
    else {
        Write-Host "No disabled users with licenses found. No email sent." -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Script execution failed: $_"
}
finally {
    # Disconnect from Microsoft Graph
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Write-Host "Disconnected from Microsoft Graph" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to disconnect from Microsoft Graph: $_"
    }

    Write-Host "`nScript completed." -ForegroundColor Cyan
}
