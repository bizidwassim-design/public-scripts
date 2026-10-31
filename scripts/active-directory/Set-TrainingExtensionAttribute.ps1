<#
.SYNOPSIS
    Tag licensed, non-excluded AD users with extensionAttribute1 = "CyberSecurityTraining" (awareness-platform sync).
.DESCRIPTION
    For every enabled AD user: skips accounts flagged by an exclusion extension attribute (admin,
    no-mailbox, temporarily disabled, AD-only, generic, consultant, service account), checks in
    Microsoft Graph that the user holds one of the target licence SKUs (SPE_E5 / SPE_F1), then sets
    extensionAttribute1 to the training tag. Writes Updated / Skipped CSV reports and a summary.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | Microsoft.Graph.Authentication | Microsoft.Graph.Users
    Impact      : Modifies AD (extensionAttribute1 on eligible users)
    License     : MIT
.EXAMPLE
    .\Set-TrainingExtensionAttribute.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$TrainingTag     = "CyberSecurityTraining"
# Define target licenses (SKU part numbers)
$TargetLicenses  = @("SPE_E5", "SPE_F1")
# Define exclusion conditions (attribute = value)
$ExclusionConditions = @{
    "extensionAttribute4"  = "AdminAccount"
    "extensionAttribute7"  = "UserDontUseEmails"
    "extensionAttribute8"  = "TemporarilyDisabled"
    "extensionAttribute11" = "ADonly"
    "extensionAttribute12" = "Generic"
    "extensionAttribute13" = "Consultant"
    "extensionAttribute15" = "ServiceAccount"
}
$ReportDir       = "C:\Scripts\Reports"
# -------------------------------------------------------------------------

# Import required modules
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "Active Directory module imported successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to import Active Directory module. Please install RSAT tools."
    exit 1
}

try {
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
    Write-Host "Microsoft Graph modules imported successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to import Microsoft Graph modules. Please install: Install-Module Microsoft.Graph"
    exit 1
}

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
try {
    Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All" -ErrorAction Stop
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    exit 1
}

# Get all active users from Active Directory with extension attributes
Write-Host "Retrieving active users from Active Directory..." -ForegroundColor Yellow
try {
    $ADUsers = Get-ADUser -Filter {Enabled -eq $true} -Properties UserPrincipalName, extensionAttribute1, extensionAttribute4, extensionAttribute7, extensionAttribute8, extensionAttribute11, extensionAttribute12, extensionAttribute13, extensionAttribute15
    Write-Host "Found $($ADUsers.Count) active AD users" -ForegroundColor Green
} catch {
    Write-Error "Failed to retrieve AD users: $($_.Exception.Message)"
    exit 1
}

# Initialize counters
$ProcessedCount = 0
$EligibleUsers = 0
$UpdatedUsers = 0
$SkippedUsers = 0
$TotalUsers = $ADUsers.Count

Write-Host "Processing users for CyberSecurity Training attribute..." -ForegroundColor Yellow

# Create arrays to store results for reporting
$UpdatedUsersList = @()
$SkippedUsersList = @()

foreach ($ADUser in $ADUsers) {
    $ProcessedCount++
    Write-Progress -Activity "Processing Users" -Status "Checking user $ProcessedCount of $TotalUsers" -PercentComplete (($ProcessedCount / $TotalUsers) * 100)

    # Skip if no UPN
    if ([string]::IsNullOrEmpty($ADUser.UserPrincipalName)) {
        Write-Warning "Skipping user $($ADUser.SamAccountName) - No UPN found"
        continue
    }

    # Check exclusion conditions first
    $IsExcluded = $false
    $ExclusionReason = ""

    foreach ($Attribute in $ExclusionConditions.Keys) {
        if ($ADUser.$Attribute -eq $ExclusionConditions[$Attribute]) {
            $IsExcluded = $true
            $ExclusionReason = "$Attribute = $($ExclusionConditions[$Attribute])"
            break
        }
    }

    if ($IsExcluded) {
        $SkippedUsers++
        $SkippedUsersList += [PSCustomObject]@{
            UPN = $ADUser.UserPrincipalName
            Reason = "Excluded: $ExclusionReason"
            CurrentExtensionAttribute1 = $ADUser.extensionAttribute1
        }
        Write-Host "[-] Skipped (Excluded): $($ADUser.UserPrincipalName) - $ExclusionReason" -ForegroundColor Yellow
        continue
    }

    try {
        # Get user from Microsoft Graph to check licenses
        $GraphUser = Get-MgUser -UserId $ADUser.UserPrincipalName -Property "AssignedLicenses" -ErrorAction SilentlyContinue

        if ($GraphUser -and $GraphUser.AssignedLicenses.Count -gt 0) {
            # Check if user has target licenses
            $HasTargetLicense = $false
            $UserLicenses = @()

            foreach ($License in $GraphUser.AssignedLicenses) {
                try {
                    $SubscribedSku = Get-MgSubscribedSku | Where-Object { $_.SkuId -eq $License.SkuId }
                    if ($SubscribedSku) {
                        $LicenseName = $SubscribedSku.SkuPartNumber
                        $UserLicenses += $LicenseName
                        if ($TargetLicenses -contains $LicenseName) {
                            $HasTargetLicense = $true
                        }
                    }
                } catch {
                    Write-Warning "Could not resolve license SKU for user $($ADUser.UserPrincipalName)"
                }
            }

            if ($HasTargetLicense) {
                $EligibleUsers++

                # Check if extensionAttribute1 already has the training tag
                if ($ADUser.extensionAttribute1 -eq $TrainingTag) {
                    $SkippedUsers++
                    $SkippedUsersList += [PSCustomObject]@{
                        UPN = $ADUser.UserPrincipalName
                        Reason = "Already has $TrainingTag"
                        CurrentExtensionAttribute1 = $ADUser.extensionAttribute1
                        Licenses = ($UserLicenses -join ", ")
                    }
                    Write-Host "[-] Skipped (Already set): $($ADUser.UserPrincipalName)" -ForegroundColor Gray
                } else {
                    # Update extensionAttribute1
                    try {
                        Set-ADUser -Identity $ADUser.SamAccountName -Replace @{extensionAttribute1=$TrainingTag} -ErrorAction Stop
                        $UpdatedUsers++
                        $UpdatedUsersList += [PSCustomObject]@{
                            UPN = $ADUser.UserPrincipalName
                            PreviousExtensionAttribute1 = if ($ADUser.extensionAttribute1) { $ADUser.extensionAttribute1 } else { "(empty)" }
                            NewExtensionAttribute1 = $TrainingTag
                            Licenses = ($UserLicenses -join ", ")
                        }
                        Write-Host "[OK] Updated: $($ADUser.UserPrincipalName) - Set extensionAttribute1 to '$TrainingTag'" -ForegroundColor Green
                    } catch {
                        Write-Error "Failed to update $($ADUser.UserPrincipalName): $($_.Exception.Message)"
                        $SkippedUsers++
                        $SkippedUsersList += [PSCustomObject]@{
                            UPN = $ADUser.UserPrincipalName
                            Reason = "Update failed: $($_.Exception.Message)"
                            CurrentExtensionAttribute1 = $ADUser.extensionAttribute1
                        }
                    }
                }
            } else {
                $SkippedUsers++
                $SkippedUsersList += [PSCustomObject]@{
                    UPN = $ADUser.UserPrincipalName
                    Reason = "No target license ($($TargetLicenses -join ' or '))"
                    CurrentExtensionAttribute1 = $ADUser.extensionAttribute1
                    Licenses = if ($UserLicenses.Count -gt 0) { ($UserLicenses -join ", ") } else { "No licenses" }
                }
                Write-Host "[ ] No target license: $($ADUser.UserPrincipalName)" -ForegroundColor Gray
            }
        } else {
            $SkippedUsers++
            $SkippedUsersList += [PSCustomObject]@{
                UPN = $ADUser.UserPrincipalName
                Reason = "No Office 365 licenses"
                CurrentExtensionAttribute1 = $ADUser.extensionAttribute1
                Licenses = "No licenses"
            }
            Write-Host "[ ] No O365 licenses: $($ADUser.UserPrincipalName)" -ForegroundColor Gray
        }
    } catch {
        Write-Warning "Error processing user $($ADUser.UserPrincipalName): $($_.Exception.Message)"
        $SkippedUsers++
        $SkippedUsersList += [PSCustomObject]@{
            UPN = $ADUser.UserPrincipalName
            Reason = "Processing error: $($_.Exception.Message)"
            CurrentExtensionAttribute1 = $ADUser.extensionAttribute1
        }
    }
}

Write-Progress -Activity "Processing Users" -Completed

# Generate reports
$Timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

# Export updated users to CSV
if ($UpdatedUsers -gt 0) {
    $UpdatedUsersFile = Join-Path $ReportDir "CyberSecurity_Training_Updated_Users_$Timestamp.csv"
    $UpdatedUsersList | Export-Csv -Path $UpdatedUsersFile -NoTypeInformation -Encoding UTF8
    Write-Host "`nUpdated users report saved as: $UpdatedUsersFile" -ForegroundColor Green
}

# Export skipped users to CSV
if ($SkippedUsers -gt 0) {
    $SkippedUsersFile = Join-Path $ReportDir "CyberSecurity_Training_Skipped_Users_$Timestamp.csv"
    $SkippedUsersList | Export-Csv -Path $SkippedUsersFile -NoTypeInformation -Encoding UTF8
    Write-Host "Skipped users report saved as: $SkippedUsersFile" -ForegroundColor Yellow
}

# Display final summary
Write-Host "`n========== FINAL SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Total AD users processed: $TotalUsers" -ForegroundColor White
Write-Host "Users with target licenses ($($TargetLicenses -join '/')): $EligibleUsers" -ForegroundColor White
Write-Host "Users updated with $($TrainingTag): $UpdatedUsers" -ForegroundColor Green
Write-Host "Users skipped: $SkippedUsers" -ForegroundColor Yellow
Write-Host "====================================" -ForegroundColor Cyan

# Show breakdown of skipped reasons
if ($SkippedUsersList.Count -gt 0) {
    Write-Host "`n--- SKIP REASONS BREAKDOWN ---" -ForegroundColor Cyan
    $SkippedUsersList | Group-Object Reason | ForEach-Object {
        Write-Host "$($_.Name): $($_.Count) users" -ForegroundColor Yellow
    }
}

# Show preview of updated users
if ($UpdatedUsers -gt 0) {
    Write-Host "`n--- UPDATED USERS PREVIEW ---" -ForegroundColor Cyan
    if ($UpdatedUsersList.Count -le 10) {
        $UpdatedUsersList | Format-Table -AutoSize
    } else {
        $UpdatedUsersList | Select-Object -First 10 | Format-Table -AutoSize
        Write-Host "... and $($UpdatedUsersList.Count - 10) more users (see CSV for full list)" -ForegroundColor Gray
    }
}

# Disconnect from Microsoft Graph
try {
    Disconnect-MgGraph
    Write-Host "`nDisconnected from Microsoft Graph" -ForegroundColor Green
} catch {
    Write-Warning "Error disconnecting from Microsoft Graph: $($_.Exception.Message)"
}

Write-Host "`nScript execution completed." -ForegroundColor Green
