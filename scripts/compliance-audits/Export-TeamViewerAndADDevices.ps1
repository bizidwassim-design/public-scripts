<#
.SYNOPSIS
    Export TeamViewer devices and AD computers into one CSV and email it for reconciliation.
.DESCRIPTION
    Queries the TeamViewer web API (/api/v1/devices) and the computers of a given AD OU, merges
    both lists (Source / Name / Description / Status / LastSeen) into a CSV and emails it to the
    security team so that TeamViewer device names and descriptions can be aligned with AD and
    orphaned TeamViewer devices removed.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | TeamViewer API token | SMTP relay
    Impact      : Read-only (sends an email)
    License     : MIT
.EXAMPLE
    .\Export-TeamViewerAndADDevices.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$tvApiUrl   = "https://webapi.teamviewer.com/api/v1/devices"
$adOU       = "OU=Computers,DC=corp,DC=contoso,DC=local"
$exportPath = "C:\Scripts\Reports\combined_devices_and_computers.csv"
$smtpServer = "smtp.contoso.com"
$from       = "it-support@contoso.com"
$to         = "security@contoso.com"
$subject    = "Update TeamViewer Devices List"
# -------------------------------------------------------------------------

# Import required modules
Import-Module ActiveDirectory

# Function to get the TeamViewer API token from the secret vault
function Get-TeamViewerToken {
    # This is a placeholder function. In a real-world scenario, you would implement
    # the logic to retrieve the token from your specific secret vault (e.g., Azure Key Vault, HashiCorp Vault, etc.)
    # For demonstration purposes, we're just echoing a message.
    Write-Output "Retrieving TeamViewer API token from secret vault"
    return "<API-KEY>"
}

# Get the TeamViewer token securely
$tvAccessToken = Get-TeamViewerToken

$tvHeaders = @{
    "Authorization" = "Bearer $tvAccessToken"
    "Content-Type" = "application/json"
}

# Function to format the last_seen timestamp
function Format-LastSeen {
    param([string]$timestamp)
    if ($timestamp) {
        return [DateTime]::Parse($timestamp).ToString("yyyy-MM-dd HH:mm:ss")
    }
    return "N/A"
}

# Function to get TeamViewer devices
function Get-TeamViewerDevices {
    try {
        $response = Invoke-RestMethod -Uri $tvApiUrl -Headers $tvHeaders -Method Get

        if ($response.devices) {
            return $response.devices | ForEach-Object {
                [PSCustomObject]@{
                    Source = "TeamViewer"
                    Name = $_.alias
                    Description = "Device ID: $($_.device_id)"
                    Status = $_.online_state
                    LastSeen = if ($_.online_state -eq "offline") { Format-LastSeen $_.last_seen } else { "Currently Online" }
                }
            }
        } else {
            Write-Warning "No TeamViewer devices found or you don't have permission to view them."
            return @()
        }
    } catch {
        Write-Error "Error occurred while fetching TeamViewer devices: $_"
        return @()
    }
}

# Function to get AD computers
function Get-ADComputersFromOU {
    param ([string]$OUPath)
    try {
        $computers = Get-ADComputer -Filter * -Properties Name, Description, Enabled -SearchBase $OUPath
        return $computers | ForEach-Object {
            [PSCustomObject]@{
                Source = "Active Directory"
                Name = $_.Name
                Description = $_.Description
                Status = if ($_.Enabled) { "Enabled" } else { "Disabled" }
                LastSeen = "N/A"  # AD doesn't provide last seen info in this context
            }
        }
    } catch {
        Write-Error "Error occurred while fetching AD computers: $_"
        return @()
    }
}

# Main execution
try {
    $allDevices = @()

    # Get TeamViewer devices
    Write-Output "Fetching TeamViewer devices..."
    $allDevices += Get-TeamViewerDevices

    # Get AD computers
    Write-Output "Fetching Active Directory computers..."
    $allDevices += Get-ADComputersFromOU -OUPath $adOU

    if ($allDevices.Count -gt 0) {
        # Ensure the export directory exists
        $exportDir = Split-Path -Parent $exportPath
        if (!(Test-Path -Path $exportDir)) {
            New-Item -ItemType Directory -Force -Path $exportDir | Out-Null
        }

        # Export to CSV
        $allDevices | Export-Csv -Path $exportPath -NoTypeInformation

        Write-Output "Combined data exported successfully to $exportPath"
        $allDevices | Format-Table -AutoSize

        # Prepare email body
        $body = @"
<font face="calibri">
Hello Security Team,

Please find attached the latest export of devices from both TeamViewer and Active Directory.

We kindly request that you perform the following actions:

1. Update the TeamViewer devices list based on the attached AD export.
2. Ensure that the device descriptions in TeamViewer match those in Active Directory.
3. Remove any devices from the TeamViewer list that no longer exist in Active Directory.

The attached CSV file contains the following information for each device:
- Source (TeamViewer or Active Directory)
- Name
- Description
- Status
- Last Seen (for TeamViewer devices)

If you have any questions or concerns, please don't hesitate to reach out.

Thank you for your attention to this matter.

Best regards,
IT Support Team
</font>
"@

        # Send email with attachment
        try {
            Send-MailMessage -SmtpServer $smtpServer `
                -From $from `
                -To $to `
                -Subject $subject `
                -Body $body `
                -BodyAsHtml `
                -Priority High `
                -Encoding ([System.Text.Encoding]::UTF8) `
                -Attachments $exportPath

            Write-Output "Email sent successfully with the CSV file attached."
        } catch {
            Write-Error "Error sending email: $_"
        }

    } else {
        Write-Warning "No devices or computers found to export."
    }
} catch {
    Write-Error "An unexpected error occurred: $_"
}
