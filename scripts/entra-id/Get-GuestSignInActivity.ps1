<#
.SYNOPSIS
    Export the last interactive / non-interactive sign-in of every enabled Entra ID guest account.
.DESCRIPTION
    Lists enabled guest users through Microsoft Graph, reads the signInActivity of each one from the
    beta endpoint and exports DisplayName / Email / UPN / last sign-ins to a timestamped CSV.
    Prints a summary of guests with no sign-in at all (candidates for removal).
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Microsoft.Graph (User.Read.All, AuditLog.Read.All, Directory.Read.All)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-GuestSignInActivity.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$OutputDir = "C:\Scripts\Reports"
# -------------------------------------------------------------------------

# Install required module if not already installed
# Install-Module Microsoft.Graph -Scope CurrentUser -Force

# Connect to Microsoft Graph with required scopes
Connect-MgGraph -Scopes @(
    "User.Read.All",
    "AuditLog.Read.All",
    "Directory.Read.All"
)

# Select beta profile for additional properties (Graph SDK v1 only; no-op on SDK v2)
Select-MgProfile -Name "beta" -ErrorAction SilentlyContinue

# Function to get sign-in data for a user
function Get-UserSignInInfo {
    param (
        [string]$UserId
    )
    try {
        $uri = "https://graph.microsoft.com/beta/users/$UserId/?`$select=id,displayName,userPrincipalName,mail,signInActivity"
        $userInfo = Invoke-MgGraphRequest -Uri $uri -Method GET
        return $userInfo
    }
    catch {
        Write-Warning "Error getting sign-in info for user $UserId : $_"
        return $null
    }
}

# Get all guest users
$guests = Get-MgUser -Filter "userType eq 'Guest' and accountEnabled eq true" -All

Write-Host "Found $($guests.Count) guest accounts. Retrieving sign-in data..."

$results = @()
$count = 0

foreach ($guest in $guests) {
    $count++
    Write-Progress -Activity "Processing Guest Accounts" -Status "Processing $($guest.DisplayName) ($count of $($guests.Count))" -PercentComplete (($count / $guests.Count) * 100)

    $signInInfo = Get-UserSignInInfo -UserId $guest.Id

    if ($signInInfo) {
        $lastInteractive = if ($signInInfo.signInActivity.lastSignInDateTime) {
            Get-Date $signInInfo.signInActivity.lastSignInDateTime -Format "MMM d, yyyy, h:mm tt"
        } else {
            "--"
        }

        $lastNonInteractive = if ($signInInfo.signInActivity.lastNonInteractiveSignInDateTime) {
            Get-Date $signInInfo.signInActivity.lastNonInteractiveSignInDateTime -Format "MMM d, yyyy, h:mm tt"
        } else {
            "--"
        }

        $results += [PSCustomObject]@{
            DisplayName = $signInInfo.displayName
            Email = $signInInfo.mail
            UserPrincipalName = $signInInfo.userPrincipalName
            'Last interactive sign-in' = $lastInteractive
            'Last non-interactive sign-in' = $lastNonInteractive
        }
    }
}

Write-Progress -Activity "Processing Guest Accounts" -Completed

# Export results to CSV with timestamp
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$csvPath = Join-Path $OutputDir "GuestAccountSignIns_$timestamp.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation

# Display results
$results | Format-Table -AutoSize

# Display summary
Write-Host "`nSummary:"
Write-Host "Total Guest Accounts Processed: $($results.Count)"
Write-Host "Accounts with no interactive sign-ins: $(($results | Where-Object { $_.'Last interactive sign-in' -eq '--' }).Count)"
Write-Host "Accounts with no non-interactive sign-ins: $(($results | Where-Object { $_.'Last non-interactive sign-in' -eq '--' }).Count)"
Write-Host "Accounts with no sign-ins at all: $(($results | Where-Object { $_.'Last interactive sign-in' -eq '--' -and $_.'Last non-interactive sign-in' -eq '--' }).Count)"
Write-Host "`nResults exported to: $csvPath"

start $csvPath
