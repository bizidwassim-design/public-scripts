<#
.SYNOPSIS
    Disable AD accounts from a UPN list that no longer hold a Microsoft 365 licence (mailbox SKU).
.DESCRIPTION
    For each UPN in the input file: looks up the AD user, checks the Exchange Online mailbox
    (SKUAssigned). Users without an assigned SKU are disabled in AD; if their mailbox is a shared
    mailbox, "shared mailbox" is appended to the AD Description. Everything is written to a
    timestamped log. Set $WhatIf = $true to log without disabling.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | ExchangeOnlineManagement
    Impact      : Modifies AD (disables accounts, updates Description)
    License     : MIT
.EXAMPLE
    .\Disable-UnlicensedAccounts.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$WhatIf         = $true                               # $false to really disable accounts
$InputFilePath  = "C:\Scripts\Input\UPNList.txt"      # one UPN per line
$OutputFilePath = "C:\Scripts\Logs\Output_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
# -------------------------------------------------------------------------

# AD and Office 365 User Management Script
# This script reads a list of UPNs, checks if users have an active O365 license,
# and disables accounts without licenses (updating description for shared mailboxes)

# Function to write to log file
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Message
    )

    if ([string]::IsNullOrEmpty($Message)) {
        # Just write a blank line
        "" | Out-File -FilePath $OutputFilePath -Append
    } else {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$timestamp - $Message" | Out-File -FilePath $OutputFilePath -Append
    }
}

# Check if required modules are installed
$requiredModules = @("ActiveDirectory", "ExchangeOnlineManagement")
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Required module $module is not installed. Please install it before running this script." -ForegroundColor Red
        exit
    }
}

# Function to update AD description field
function Update-ADDescription {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SamAccountName,

        [Parameter(Mandatory=$true)]
        [string]$AppendText
    )

    try {
        $user = Get-ADUser -Identity $SamAccountName -Properties Description
        $currentDescription = $user.Description

        if ([string]::IsNullOrEmpty($currentDescription)) {
            if (-not $WhatIf) { Set-ADUser -Identity $SamAccountName -Description $AppendText }
            Write-Log "Updated description for $SamAccountName to '$AppendText'"
        } else {
            # Check if the description already contains the append text
            if ($currentDescription -notlike "*$AppendText*") {
                $newDescription = "$currentDescription, $AppendText"
                if (-not $WhatIf) { Set-ADUser -Identity $SamAccountName -Description $newDescription }
                Write-Log "Updated description for $SamAccountName from '$currentDescription' to '$newDescription'"
            } else {
                Write-Log "Description for $SamAccountName already contains '$AppendText'"
            }
        }
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error updating description for ${SamAccountName} - $errorMessage"
    }
}

# Initialize log file
Write-Log "Script started (WhatIf = $WhatIf)"
Write-Log "Input file: $InputFilePath"
Write-Log "Output file: $OutputFilePath"

# Validate input file
if (-not (Test-Path -Path $InputFilePath)) {
    Write-Host "Input file not found: $InputFilePath" -ForegroundColor Red
    Write-Log "Error: Input file not found: $InputFilePath"
    exit
}

# Import Active Directory module
Import-Module ActiveDirectory
Write-Log "Imported Active Directory module"

# Connect to Exchange Online
try {
    Write-Host "Connecting to Exchange Online. Please sign in with admin credentials..." -ForegroundColor Yellow
    Connect-ExchangeOnline -ShowProgress $true
    Write-Log "Connected to Exchange Online"
} catch {
    $errorMessage = $_.Exception.Message
    Write-Host "Failed to connect to Exchange Online: $errorMessage" -ForegroundColor Red
    Write-Log "Error: Failed to connect to Exchange Online - $errorMessage"
    exit
}

# Read input file
try {
    $upns = Get-Content -Path $InputFilePath -ErrorAction Stop
    Write-Log "Successfully read $($upns.Count) UPNs from input file"
} catch {
    $errorMessage = $_.Exception.Message
    Write-Host "Error reading input file: $errorMessage" -ForegroundColor Red
    Write-Log "Error reading input file - $errorMessage"
    exit
}

# Process each UPN
foreach ($upn in $upns) {
    Write-Log "Processing UPN: $upn"

    try {
        # Get AD user
        $adUser = Get-ADUser -Filter "UserPrincipalName -eq '$upn'" -Properties samAccountName, Enabled

        if ($null -eq $adUser) {
            Write-Log "User not found in Active Directory: $upn"
            continue
        }

        $samAccountName = $adUser.samAccountName
        Write-Log "Found user in AD: $samAccountName (Enabled: $($adUser.Enabled))"

        # Check if user has a license in Office 365
        try {
            $mailboxInfo = Get-Mailbox -Identity $upn -ErrorAction SilentlyContinue | Select-Object SKUAssigned, RecipientTypeDetails

            if ($null -ne $mailboxInfo -and $mailboxInfo.SKUAssigned) {
                Write-Log "$samAccountName has an active license in Office 365. No action needed."
                Write-Log " "
                continue # Skip to the next user
            }

            # If we reach here, the user doesn't have an active license, so disable the account
            if ($adUser.Enabled) {
                if ($WhatIf) {
                    Write-Log "WHATIF: would disable account $samAccountName - no active license in Office 365"
                } else {
                    Disable-ADAccount -Identity $samAccountName
                    Write-Log "DISABLED account $samAccountName - no active license in Office 365"
                }
            } else {
                Write-Log "Account $samAccountName already disabled (no active license)"
            }

            # Check if the user has a shared mailbox
            if ($null -ne $mailboxInfo -and $mailboxInfo.RecipientTypeDetails -eq "SharedMailbox") {
                # Update AD description to indicate shared mailbox
                Update-ADDescription -SamAccountName $samAccountName -AppendText "shared mailbox"
                Write-Log "$samAccountName has a shared mailbox"
            }
        } catch {
            $errorMessage = $_.Exception.Message
            Write-Log "Error checking O365 information for ${upn} - $errorMessage"
        }
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Log "Error processing ${upn} - $errorMessage"
    }

    # Add a blank line in log for readability
    Write-Log " "
}

# Disconnect from Exchange Online
try {
    #Disconnect-ExchangeOnline -Confirm:$false
    Write-Log "Disconnected from Exchange Online"
} catch {
    $errorMessage = $_.Exception.Message
    Write-Log "Error disconnecting from Exchange Online - $errorMessage"
}

Write-Log "Script completed"
Write-Host "Processing completed. Check the log file at: $OutputFilePath" -ForegroundColor Green
