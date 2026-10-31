<#
.SYNOPSIS
    Monthly clean-up of stale Entra ID devices, with a CSV + email report of what was deleted.
.DESCRIPTION
    Enumerates all Entra ID devices (Microsoft Graph) and deletes those that have no recorded
    activity, are inactive for more than 90 days, or are missing from on-premises AD and inactive
    for more than 30 days. Deleted devices are exported to a CSV and emailed to the IT team.
    Set $WhatIf = $true to only log what would be deleted.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Microsoft.Graph.Authentication | Microsoft.Graph.Identity.DirectoryManagement | ActiveDirectory module | SMTP relay
    Impact      : Modifies Entra ID (deletes device objects)
    License     : MIT
.EXAMPLE
    .\Remove-StaleEntraDevices.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$WhatIf       = $true                                   # $false to really delete
$LogPath      = "C:\Scripts\MonthlyEntraIDDevices\script_log.txt"
$csvPath      = "C:\Scripts\MonthlyEntraIDDevices\DeletedDevices.csv"
$AdSearchBase = "OU=Computers,DC=corp,DC=contoso,DC=local"
$smtpServer   = "smtp.contoso.com"
$from         = "it-support@contoso.com"
$emailaddress = "it-support@contoso.com"
$Bcc          = "security@contoso.com"
# -------------------------------------------------------------------------

# Start transcript to log the script execution
Start-Transcript -Path $LogPath -Append -Force

# Install Microsoft Graph modules if not already installed
# Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
# Install-Module Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser -Force

# Import required modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Identity.DirectoryManagement
Import-Module ActiveDirectory

# Connect to Microsoft Graph with required scopes
try {
    Connect-MgGraph -Scopes "Device.ReadWrite.All", "Directory.Read.All" -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
}
catch {
    Write-Host "Failed to connect to Microsoft Graph: $($_.Exception.Message)" -ForegroundColor Red
    Stop-Transcript
    exit
}

# Initialize an array to store deleted device information
$deletedDevices = @()

# Get all Entra ID devices
Write-Host "Retrieving all Entra ID devices..." -ForegroundColor Cyan
$devices = Get-MgDevice -All | Select-Object DisplayName, ApproximateLastSignInDateTime, AccountEnabled, DeviceId, Id

Write-Host "Found $($devices.Count) devices in Entra ID" -ForegroundColor Cyan

# Loop through each device to apply conditions
foreach ($device in $devices) {
    Write-Host "WORKING IN PROGRESS: $($device.DisplayName)" -ForegroundColor GREEN

    $delete = $false
    $Comment = ""

    # Check if the activity field is empty
    if (-not $device.ApproximateLastSignInDateTime) {
        $delete = $true
        $Comment = "Activity field is empty"
    }

    # Check if the activity is older than 90 days
    $lastActivity = $device.ApproximateLastSignInDateTime
    if ($lastActivity -and ((Get-Date) - $lastActivity).Days -gt 90) {
        $delete = $true
        $Comment = "Activity is older than 90 days"
    }

    # Check if the device exists in the On-Premises Active Directory
    try {
        $adDevice = Get-ADComputer -Filter "Name -eq '$($device.DisplayName)'" -SearchBase $AdSearchBase -Properties Enabled -ErrorAction SilentlyContinue

        # Only check the 30-day condition if $lastActivity is not null
        if (!($adDevice) -and $lastActivity -and (((Get-Date) - $lastActivity).Days -gt 30)) {
            $delete = $true
            $Comment = "Device does not exist in On-Premises AD and inactive for 30+ days"
        }
    }
    catch {
        Write-Host "Warning: Could not check AD for device $($device.DisplayName): $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # If the device meets any of the deletion criteria, delete it
    if ($delete) {
        try {
            Write-Host "Deleting device: $($device.DisplayName) - Reason: $Comment" -ForegroundColor Yellow
            if ($WhatIf) {
                Write-Host "WHATIF: would delete $($device.DisplayName)" -ForegroundColor Magenta
            } else {
                Remove-MgDevice -DeviceId $device.Id -Confirm:$false
            }

            $deletedDevice = [PSCustomObject]@{
                DeviceName   = $device.DisplayName
                DeletedOn    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                LastActivity = if ($lastActivity) { $lastActivity.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
                Reason       = $Comment
                DeviceId     = $device.DeviceId
                ObjectId     = $device.Id
            }
            $deletedDevices += $deletedDevice

            Write-Host "Successfully deleted device: $($device.DisplayName)" -ForegroundColor Red
        }
        catch {
            Write-Host "Error deleting device $($device.DisplayName): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# Disconnect from Microsoft Graph
Disconnect-MgGraph

# Export deleted devices to a CSV file
if ($deletedDevices.Count -gt 0) {
    $deletedDevices | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "`nExported $($deletedDevices.Count) deleted devices to $csvPath" -ForegroundColor Green

    # Open the CSV file
    Start-Process $csvPath

    # Define email details
    $subject = "Monthly Audit Entra ID Devices - $($deletedDevices.Count) Devices Deleted"

    # Count of deleted devices
    $deletedDeviceCount = $deletedDevices.Count

    # Email body with updated content
    $body = @"
<html>
<body>
<p>Hello Team,</p>
<p>Attached, you will find the report for Azure Entra ID devices.</p>
<p><strong>We have deleted $deletedDeviceCount devices.</strong> For more details, please refer to the attached deleted devices list.</p>
<p>Deletion Criteria:</p>
<ul>
    <li>Devices with no activity recorded</li>
    <li>Devices inactive for more than 90 days</li>
    <li>Devices not in On-Premises AD and inactive for 30+ days</li>
</ul>
<p>Thank you for your prompt attention to this matter.</p>
<p>Best regards,<br>The Contoso Cybersecurity Team</p>
</body>
</html>
"@

    # Send the email with the attachment
    try {
        Send-MailMessage -SmtpServer $smtpServer `
            -From $from `
            -To $emailaddress `
            -Bcc $Bcc `
            -Subject $subject `
            -Body $body `
            -BodyAsHtml `
            -Priority High `
            -Encoding ([System.Text.Encoding]::UTF8) `
            -Attachment $csvPath

        Write-Host "Email sent successfully to $emailaddress" -ForegroundColor Green
    }
    catch {
        Write-Host "Error sending the email: $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "`nNo devices met the deletion criteria." -ForegroundColor Green

    # Create an empty CSV for record-keeping
    [PSCustomObject]@{
        DeviceName   = "No devices deleted"
        DeletedOn    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        LastActivity = "N/A"
        Reason       = "No devices met deletion criteria"
        DeviceId     = "N/A"
        ObjectId     = "N/A"
    } | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
}

# Stop transcript
Stop-Transcript
