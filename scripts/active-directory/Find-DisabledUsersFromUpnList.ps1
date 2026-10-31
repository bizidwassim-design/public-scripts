<#
.SYNOPSIS
    Check a list of UPNs (e.g. exported from a security-awareness platform) against AD and flag disabled accounts.
.DESCRIPTION
    Reads one UPN per line from a text file, looks each one up in AD and reports Disabled / Not in AD /
    Error rows with creation, password and last-logon dates. Accounts tagged "TemporarilyDisabled" in
    extensionAttribute8 are skipped. When $clearExtensionAttribute1 is $true the training tag stored in
    extensionAttribute1 is cleared on the disabled accounts. Exports a CSV and prints a summary.
    Typical use: export the Terranova user list, run the script, mark disabled users for deletion.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Modifies AD (clears extensionAttribute1 on disabled accounts when enabled)
    License     : MIT
.EXAMPLE
    .\Find-DisabledUsersFromUpnList.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$inputFile  = "C:\Scripts\Input\UPNFile.txt"
$outputFile = "C:\Scripts\Reports\DisabledUsersList.csv"
# Flag to determine if we should clear ExtensionAttribute1
$clearExtensionAttribute1 = $true
# -------------------------------------------------------------------------

# Import Active Directory Module
Import-Module ActiveDirectory

# Verify input file exists
if (-not (Test-Path $inputFile)) {
    Write-Error "Input file not found: $inputFile"
    exit
}

# Read UPN list from file
$upnList = Get-Content $inputFile | Where-Object { $_ -match '\S' }

# Initialize results array for disabled accounts
$disabledAccounts = @()

# Process each UPN
foreach ($upn in $upnList) {
    try {
        # Trim whitespace
        $upn = $upn.Trim()

        # Get AD User with additional properties - added extensionAttribute1 and Description
        $adUser = Get-ADUser -Filter {UserPrincipalName -eq $upn} -Properties Enabled, DisplayName, SamAccountName, LastLogonDate, WhenCreated, PasswordLastSet, DistinguishedName, extensionAttribute1, extensionAttribute8, Description

        if ($adUser) {
            # Check if account is disabled
            if (-not $adUser.Enabled) {
                if ($adUser.extensionAttribute8 -like "TemporarilyDisabled"){continue}
                # Create detailed result object for disabled accounts - added ExtensionAttribute1 and Description
                $attributeCleared = "No Action"
                if ($clearExtensionAttribute1 -and ![string]::IsNullOrEmpty($adUser.extensionAttribute1)) {
                    $attributeCleared = "ExtensionAttribute1 Cleared"
                }

                $disabledAccountObj = [PSCustomObject]@{
                    UserPrincipalName = $upn
                    DisplayName = $adUser.DisplayName
                    SamAccountName = $adUser.SamAccountName
                    DistinguishedName = $adUser.DistinguishedName
                    AccountCreated = $adUser.WhenCreated
                    PasswordLastSet = $adUser.PasswordLastSet
                    LastLogonDate = $adUser.LastLogonDate
                    ExtensionAttribute1 = $adUser.extensionAttribute1
                    Description = $adUser.Description
                    AccountStatus = "Disabled"
                    ActionTaken = $attributeCleared
                }

                # Add to disabled accounts list
                $disabledAccounts += $disabledAccountObj
            }
        }
        else {
            # User not found in AD
            $notFoundObj = [PSCustomObject]@{
                UserPrincipalName = $upn
                DisplayName = "Not Found"
                SamAccountName = "Not Found"
                DistinguishedName = "N/A"
                AccountCreated = $null
                PasswordLastSet = $null
                LastLogonDate = $null
                ExtensionAttribute1 = "N/A"
                Description = "N/A"
                AccountStatus = "Not in AD"
                ActionTaken = "N/A"
            }

            $disabledAccounts += $notFoundObj
        }
    }
    catch {
        # Handle any errors
        $errorObj = [PSCustomObject]@{
            UserPrincipalName = $upn
            DisplayName = "Error"
            SamAccountName = "Error"
            DistinguishedName = "N/A"
            AccountCreated = $null
            PasswordLastSet = $null
            LastLogonDate = $null
            ExtensionAttribute1 = "N/A"
            Description = "N/A"
            AccountStatus = "Error Processing"
            ActionTaken = "N/A"
        }

        $disabledAccounts += $errorObj
    }
}

# Filter only disabled accounts (excluding "Not in AD" and "Error Processing")
$actualDisabledAccounts = $disabledAccounts | Where-Object { $_.AccountStatus -eq "Disabled" }

# Perform the actual clearing of ExtensionAttribute1 for disabled accounts
if ($clearExtensionAttribute1) {
    $clearedCount = 0
    foreach ($account in $disabledAccounts | Where-Object { $_.AccountStatus -eq "Disabled" -and $_.ActionTaken -eq "ExtensionAttribute1 Cleared" }) {
        try {
            # Clear ExtensionAttribute1
            Set-ADUser -Identity $account.SamAccountName -Clear extensionAttribute1
            $clearedCount++
        }
        catch {
            Write-Warning "Failed to clear extensionAttribute1 for $($account.SamAccountName): $_"
        }
    }
    Write-Host "Cleared ExtensionAttribute1 for $clearedCount accounts" -ForegroundColor Yellow
}

# Export results to CSV
$disabledAccounts | Export-Csv -Path $outputFile -NoTypeInformation

# Display summary and results
Write-Host "Disabled Accounts Finder" -ForegroundColor Cyan
Write-Host "--------------------" -ForegroundColor Cyan
Write-Host "Total Users Processed: $($upnList.Count)"
Write-Host "Disabled Accounts Found: $($actualDisabledAccounts.Count)" -ForegroundColor Yellow

# Display detailed disabled account information
if ($actualDisabledAccounts.Count -gt 0) {
    Write-Host "`nDisabled Accounts Details:" -ForegroundColor Green
    $actualDisabledAccounts | Format-Table -AutoSize
}

# Additional detailed report in console
Write-Host "`nDetailed Report:" -ForegroundColor Cyan
Write-Host "Total Entries in Result: $($disabledAccounts.Count)"
Write-Host "Disabled Accounts: $($disabledAccounts | Where-Object { $_.AccountStatus -eq 'Disabled' } | Measure-Object | Select-Object -ExpandProperty Count)"
Write-Host "Not Found in AD: $($disabledAccounts | Where-Object { $_.AccountStatus -eq 'Not in AD' } | Measure-Object | Select-Object -ExpandProperty Count)"
Write-Host "Processing Errors: $($disabledAccounts | Where-Object { $_.AccountStatus -eq 'Error Processing' } | Measure-Object | Select-Object -ExpandProperty Count)"

Write-Host "`nResults exported to: $outputFile" -ForegroundColor Green

start $outputFile
