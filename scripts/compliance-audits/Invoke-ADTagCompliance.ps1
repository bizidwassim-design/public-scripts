<#
.SYNOPSIS
    Weekly Active Directory tag compliance: add/remove extensionAttribute security tags by rule.
.DESCRIPTION
    Applies a tagging convention to every AD user: *test* UPNs -> Generic (ea12), svc* -> ServiceAccount
    (ea15), OU=External -> Consultant (ea13), *admin* -> AdminAccount (ea4); clears conflicting tags and
    removes the CyberSecurityTraining tag (ea1) from excluded account types. Exports CSVs, transcript
    log and emails an HTML report when something changed. Run on a domain-joined admin server.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | write permission on user extensionAttributes
    Impact      : Modifies AD (sets/clears extensionAttribute1/2/4/11/12/13/15) — use -WhatIf first
    License     : MIT
.EXAMPLE
    .\Invoke-ADTagCompliance.ps1 -WhatIf -Verbose
.EXAMPLE
    .\Invoke-ADTagCompliance.ps1 -SMTPServer smtp.contoso.com -ToAddress security@contoso.com
#>

[CmdletBinding()]
param(
    # ---- EDIT ME (defaults) ---------------------------------------------
    [Parameter(Mandatory = $false)]
    [string]$ScriptPath = "C:\Scripts\WeeklyTagCompliance",

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer = "smtp.contoso.com",

    [Parameter(Mandatory = $false)]
    [string]$FromAddress = "it-support@contoso.com",

    [Parameter(Mandatory = $false)]
    [string]$ToAddress = "security@contoso.com",
    # ---------------------------------------------------------------------

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

#Requires -Modules ActiveDirectory

# Set strict mode for better error detection
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---- EDIT ME ------------------------------------------------------------
# v2.1: Accounts that must ALWAYS keep the CyberSecurityTraining tag (extensionAttribute1),
# regardless of exclusion rules (Consultant, etc.)
$CyberSecurityTrainingExceptions = @(
    "user@contoso.com"
)
$TeamSignature = "Contoso Cybersecurity Team"
# -------------------------------------------------------------------------

#region Helper Functions

function Initialize-ScriptEnvironment {
    <#
    .SYNOPSIS
        Initializes the script environment and validates prerequisites
    #>
    [CmdletBinding()]
    param(
        [string]$BasePath
    )

    try {
        # Create required directories if they don't exist
        $directories = @(
            "$BasePath",
            "$BasePath\log",
            "$BasePath\output"
        )

        foreach ($dir in $directories) {
            if (-not (Test-Path -Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
                Write-Verbose "Created directory: $dir"
            }
        }

        # Verify AD module is available
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            throw "ActiveDirectory module is not available. Please install RSAT tools."
        }

        # Import AD module if not already loaded
        if (-not (Get-Module -Name ActiveDirectory)) {
            Import-Module ActiveDirectory -ErrorAction Stop
        }

        Write-Verbose "Script environment initialized successfully"
        return $true
    }
    catch {
        Write-Error "Failed to initialize script environment: $_"
        return $false
    }
}

function Write-LogMessage {
    <#
    .SYNOPSIS
        Writes a formatted log message to console and transcript
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{
        'Info'    = 'White'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
    }

    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $colorMap[$Level]
}

function Set-ADUserTag {
    <#
    .SYNOPSIS
        Adds a tag to an AD user's extension attribute
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.ActiveDirectory.Management.ADUser]$User,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 15)]
        [int]$AttributeNumber,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    try {
        $attributeName = "extensionAttribute$AttributeNumber"

        if ($PSCmdlet.ShouldProcess($User.UserPrincipalName, "Add $attributeName = $Value")) {
            Set-ADUser -Identity $User -Add @{$attributeName = $Value} -ErrorAction Stop

            Write-LogMessage -Message "Added [$attributeName = $Value] for: $($User.UserPrincipalName) - Reason: $Reason" -Level Success

            return [PSCustomObject]@{
                Action            = "Add [$attributeName = $Value]"
                Reason            = $Reason
                UserPrincipalName = $User.UserPrincipalName
                DistinguishedName = $User.DistinguishedName
                Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
    }
    catch {
        Write-LogMessage -Message "Failed to add tag for $($User.UserPrincipalName): $_" -Level Error
        return $null
    }
}

function Remove-ADUserTag {
    <#
    .SYNOPSIS
        Removes a tag from an AD user's extension attribute
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.ActiveDirectory.Management.ADUser]$User,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 15)]
        [int]$AttributeNumber,

        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    try {
        $attributeName = "extensionAttribute$AttributeNumber"
        $currentValue = $User.$attributeName

        if ($PSCmdlet.ShouldProcess($User.UserPrincipalName, "Clear $attributeName")) {
            Set-ADUser -Identity $User -Clear $attributeName -ErrorAction Stop

            Write-LogMessage -Message "Removed [$attributeName = $currentValue] for: $($User.UserPrincipalName) - Reason: $Reason" -Level Warning

            return [PSCustomObject]@{
                Action            = "Remove [$attributeName = $currentValue]"
                Reason            = $Reason
                UserPrincipalName = $User.UserPrincipalName
                DistinguishedName = $User.DistinguishedName
                Timestamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
    }
    catch {
        Write-LogMessage -Message "Failed to remove tag for $($User.UserPrincipalName): $_" -Level Error
        return $null
    }
}

function Test-ShouldExcludeFromCyberSecurityTraining {
    <#
    .SYNOPSIS
        Determines if a user should be excluded from CyberSecurityTraining tag
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.ActiveDirectory.Management.ADUser]$User
    )

    # v2.1: Exception list - these accounts always keep the tag
    if ($CyberSecurityTrainingExceptions -contains $User.UserPrincipalName) {
        return @{
            ShouldExclude = $false
            Reason        = "Exception list - tag must be kept"
        }
    }

    # Disabled accounts
    if ($User.Enabled -eq $false) {
        return @{
            ShouldExclude = $true
            Reason        = "Account is disabled"
        }
    }

    # Truck drivers (don't use emails)
    if ($User.extensionAttribute7 -eq "UserDontUseEmails") {
        return @{
            ShouldExclude = $true
            Reason        = "User is a driver (doesn't use email)"
        }
    }

    # Service accounts
    if ($User.extensionAttribute15 -eq "ServiceAccount") {
        return @{
            ShouldExclude = $true
            Reason        = "Service account"
        }
    }

    # Consultants
    if ($User.extensionAttribute13 -eq "Consultant") {
        return @{
            ShouldExclude = $true
            Reason        = "Consultant account"
        }
    }

    # Generic accounts
    if ($User.extensionAttribute12 -eq "Generic") {
        return @{
            ShouldExclude = $true
            Reason        = "Generic account"
        }
    }

    # AD-only accounts
    if ($User.extensionAttribute11 -eq "ADonly") {
        return @{
            ShouldExclude = $true
            Reason        = "AD-only account"
        }
    }

    return @{
        ShouldExclude = $false
        Reason        = $null
    }
}

function ConvertTo-HTMLTable {
    <#
    .SYNOPSIS
        Converts an array of objects to an HTML table
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Data,

        [Parameter(Mandatory = $false)]
        [string[]]$Properties = @('Action', 'Reason', 'UserPrincipalName')
    )

    if ($Data.Count -eq 0) {
        return "<p><em>No changes made in this category.</em></p>"
    }

    $tableRows = $Data | ForEach-Object {
        $row = "<tr>"
        foreach ($prop in $Properties) {
            $row += "<td>$($_.$prop)</td>"
        }
        $row += "</tr>"
        return $row
    }

    $headers = "<tr>" + ($Properties | ForEach-Object { "<th>$_</th>" }) + "</tr>"

    return @"
<table border='1' cellpadding='5' cellspacing='0' style='border-collapse: collapse; width: 100%;'>
    <thead style='background-color: #4CAF50; color: white;'>
        $headers
    </thead>
    <tbody>
        $($tableRows -join "`n")
    </tbody>
</table>
"@
}

function Send-ComplianceReport {
    <#
    .SYNOPSIS
        Sends the compliance report via email
    #>
    [CmdletBinding()]
    param(
        [array]$AddedTags,
        [array]$RemovedTags,
        [string]$SMTPServer,
        [string]$From,
        [string]$To,
        [string]$AddOutputPath,
        [string]$RemoveOutputPath
    )

    try {
        # Only send email if there are changes
        if ($AddedTags.Count -eq 0 -and $RemovedTags.Count -eq 0) {
            Write-LogMessage -Message "No changes detected. Email will not be sent." -Level Info
            return $true
        }

        # Generate HTML tables
        $addTable = ConvertTo-HTMLTable -Data $AddedTags
        $removeTable = ConvertTo-HTMLTable -Data $RemovedTags

        # Build email body
        $body = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        h2 { color: #333; }
        h3 { color: #666; margin-top: 20px; }
        table { margin: 10px 0; font-size: 14px; }
        .summary { background-color: #f0f0f0; padding: 10px; border-radius: 5px; margin: 15px 0; }
    </style>
</head>
<body>
    <h2>Weekly Tag Compliance Report</h2>
    <p>Hello Security Team,</p>
    <p>This automated report summarizes the Active Directory tag compliance actions performed on <strong>$(Get-Date -Format 'MMMM dd, yyyy')</strong>.</p>

    <div class='summary'>
        <strong>Summary:</strong><br>
        • Tags Added: <strong>$($AddedTags.Count)</strong><br>
        • Tags Removed: <strong>$($RemovedTags.Count)</strong><br>
        • Total Changes: <strong>$($AddedTags.Count + $RemovedTags.Count)</strong>
    </div>

    <h3>Tags Added:</h3>
    $addTable

    <h3>Tags Removed:</h3>
    $removeTable

    <hr style='margin-top: 30px;'>
    <p style='font-size: 12px; color: #666;'>
        <strong>Note:</strong> Detailed CSV reports are attached to this email for further analysis.<br>
        If you have any concerns about these changes, please contact the IT Infrastructure team immediately.
    </p>
    <p>Best regards,<br><strong>$TeamSignature</strong></p>
</body>
</html>
"@

        $mailParams = @{
            SmtpServer = $SMTPServer
            From       = $From
            To         = $To
            Bcc        = $To
            Subject    = "Weekly AD Tag Compliance Report - $(Get-Date -Format 'yyyy-MM-dd')"
            Body       = $body
            BodyAsHtml = $true
            Priority   = 'High'
            Encoding   = [System.Text.Encoding]::UTF8
        }

        # Add attachments if files exist
        $attachments = @()
        if (Test-Path $AddOutputPath) { $attachments += $AddOutputPath }
        if (Test-Path $RemoveOutputPath) { $attachments += $RemoveOutputPath }

        if ($attachments.Count -gt 0) {
            $mailParams['Attachments'] = $attachments
        }

        Send-MailMessage @mailParams -ErrorAction Stop
        Write-LogMessage -Message "Compliance report email sent successfully to $To" -Level Success
        return $true
    }
    catch {
        Write-LogMessage -Message "Failed to send email: $_" -Level Error
        return $false
    }
}

#endregion

#region Main Script

try {
    # Initialize logging
    $currentDate = Get-Date -Format "yyyyMMdd_HHmmss"
    $logPath = Join-Path -Path $ScriptPath -ChildPath "log"
    $logFile = Join-Path -Path $logPath -ChildPath "Log_SecurityCompliant_$currentDate.txt"

    Start-Transcript -Path $logFile -ErrorAction Stop

    Write-LogMessage -Message "=== Weekly Tag Compliance Script Started ===" -Level Info
    Write-LogMessage -Message "Script Version: 2.1" -Level Info
    Write-LogMessage -Message "Execution Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Info
    Write-LogMessage -Message "WhatIf Mode: $($WhatIf.IsPresent)" -Level Info
    Write-LogMessage -Message "CyberSecurityTraining exceptions: $($CyberSecurityTrainingExceptions -join ', ')" -Level Info

    # Initialize environment
    if (-not (Initialize-ScriptEnvironment -BasePath $ScriptPath)) {
        throw "Failed to initialize script environment"
    }

    # Initialize collections
    $addedTags = [System.Collections.Generic.List[PSCustomObject]]::new()
    $removedTags = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Define output paths
    $outputPath = Join-Path -Path $ScriptPath -ChildPath "output"
    $addOutputFile = Join-Path -Path $outputPath -ChildPath "TagsAdded_$currentDate.csv"
    $removeOutputFile = Join-Path -Path $outputPath -ChildPath "TagsRemoved_$currentDate.csv"

    # Get all AD users with required properties
    Write-LogMessage -Message "Retrieving AD users..." -Level Info

    $properties = @(
        'UserPrincipalName', 'Enabled', 'DistinguishedName',
        'extensionAttribute1', 'extensionAttribute2', 'extensionAttribute3',
        'extensionAttribute4', 'extensionAttribute5', 'extensionAttribute6',
        'extensionAttribute7', 'extensionAttribute8', 'extensionAttribute9',
        'extensionAttribute10', 'extensionAttribute11', 'extensionAttribute12',
        'extensionAttribute13', 'extensionAttribute14', 'extensionAttribute15'
    )

    $users = Get-ADUser -Filter * -Properties $properties -ErrorAction Stop
    Write-LogMessage -Message "Retrieved $($users.Count) user accounts" -Level Info

    # Process each user
    $processedCount = 0
    foreach ($user in $users) {
        $processedCount++

        if ($processedCount % 100 -eq 0) {
            Write-Progress -Activity "Processing AD Users" -Status "Processing user $processedCount of $($users.Count)" -PercentComplete (($processedCount / $users.Count) * 100)
        }

        #region Test Account Tagging
        # Tag test accounts as Generic
        if ($user.UserPrincipalName -like "*test*" -and $user.extensionAttribute12 -ne "Generic") {
            $result = Set-ADUserTag -User $user -AttributeNumber 12 -Value "Generic" `
                -Reason "Test account identified by UPN pattern" -WhatIf:$WhatIf
            if ($result) { $addedTags.Add($result) }
        }
        #endregion

        #region CyberSecurityTraining Tag Management
        if ($user.extensionAttribute1 -eq "CyberSecurityTraining") {
            $exclusionCheck = Test-ShouldExcludeFromCyberSecurityTraining -User $user

            if ($exclusionCheck.ShouldExclude) {
                $result = Remove-ADUserTag -User $user -AttributeNumber 1 `
                    -Reason $exclusionCheck.Reason -WhatIf:$WhatIf
                if ($result) { $removedTags.Add($result) }
            }
        }
        #endregion

        #region Service Account Tagging
        # Tag accounts starting with 'svc' as ServiceAccount
        if ($user.UserPrincipalName -like 'svc*' -and $user.extensionAttribute15 -ne "ServiceAccount") {
            $result = Set-ADUserTag -User $user -AttributeNumber 15 -Value "ServiceAccount" `
                -Reason "Service account identified by UPN prefix 'svc'" -WhatIf:$WhatIf
            if ($result) { $addedTags.Add($result) }
        }

        # Clean up conflicting tags for service accounts
        if ($user.extensionAttribute15 -eq "ServiceAccount") {
            # Remove AdminAccount tag from service accounts
            if ($user.extensionAttribute4 -eq "AdminAccount") {
                $result = Remove-ADUserTag -User $user -AttributeNumber 4 `
                    -Reason "Service accounts should not have AdminAccount tag" -WhatIf:$WhatIf
                if ($result) { $removedTags.Add($result) }
            }

            # Remove ADonly tag from service accounts (fixed bug: was checking for "Generic" instead of "ADonly")
            if ($user.extensionAttribute11 -eq "ADonly") {
                $result = Remove-ADUserTag -User $user -AttributeNumber 11 `
                    -Reason "Service accounts should not have ADonly tag" -WhatIf:$WhatIf
                if ($result) { $removedTags.Add($result) }
            }
        }
        #endregion

        #region Generic Account Tag Management
        if ($user.extensionAttribute12 -eq "Generic") {
            # Remove VIP tag from Generic accounts
            if ($user.extensionAttribute2 -eq "VIP") {
                $result = Remove-ADUserTag -User $user -AttributeNumber 2 `
                    -Reason "Generic accounts should not have VIP tag" -WhatIf:$WhatIf
                if ($result) { $removedTags.Add($result) }
            }
        }
        #endregion

        #region Consultant Tagging
        # Tag accounts in External OU as Consultant
        if ($user.DistinguishedName -like "*OU=External*" -and
            $user.extensionAttribute15 -ne "ServiceAccount" -and
            $user.extensionAttribute13 -ne "Consultant") {

            $result = Set-ADUserTag -User $user -AttributeNumber 13 -Value "Consultant" `
                -Reason "Account located in External OU" -WhatIf:$WhatIf
            if ($result) { $addedTags.Add($result) }
        }
        #endregion

        #region Admin Account Tagging
        # Tag accounts with 'admin' in UPN as AdminAccount
        if ($user.UserPrincipalName -like "*admin*" -and $user.extensionAttribute4 -ne "AdminAccount") {
            # Only tag if not a service account, generic account, or AD-only account
            if ($user.extensionAttribute15 -ne "ServiceAccount" -and
                $user.extensionAttribute12 -ne "Generic" -and
                $user.extensionAttribute11 -ne "ADonly") {

                $result = Set-ADUserTag -User $user -AttributeNumber 4 -Value "AdminAccount" `
                    -Reason "Admin account identified by UPN pattern" -WhatIf:$WhatIf
                if ($result) { $addedTags.Add($result) }
            }
        }
        #endregion
    }

    Write-Progress -Activity "Processing AD Users" -Completed

    # Export results to CSV
    Write-LogMessage -Message "Exporting results to CSV files..." -Level Info

    if ($addedTags.Count -gt 0) {
        $addedTags | Export-Csv -Path $addOutputFile -NoTypeInformation -Encoding UTF8
        Write-LogMessage -Message "Added tags exported to: $addOutputFile" -Level Success
    }

    if ($removedTags.Count -gt 0) {
        $removedTags | Export-Csv -Path $removeOutputFile -NoTypeInformation -Encoding UTF8
        Write-LogMessage -Message "Removed tags exported to: $removeOutputFile" -Level Success
    }

    # Display summary
    Write-LogMessage -Message "`n=== Execution Summary ===" -Level Info
    Write-LogMessage -Message "Total users processed: $($users.Count)" -Level Info
    Write-LogMessage -Message "Tags added: $($addedTags.Count)" -Level Success
    Write-LogMessage -Message "Tags removed: $($removedTags.Count)" -Level Warning
    Write-LogMessage -Message "Total changes: $($addedTags.Count + $removedTags.Count)" -Level Info

    # Send email report
    if (-not $WhatIf) {
        Write-LogMessage -Message "Sending email report..." -Level Info

        $emailResult = Send-ComplianceReport `
            -AddedTags $addedTags `
            -RemovedTags $removedTags `
            -SMTPServer $SMTPServer `
            -From $FromAddress `
            -To $ToAddress `
            -AddOutputPath $addOutputFile `
            -RemoveOutputPath $removeOutputFile

        if ($emailResult) {
            Write-LogMessage -Message "Email report sent successfully" -Level Success
        }
    }
    else {
        Write-LogMessage -Message "WhatIf mode: Email not sent" -Level Info
    }

    Write-LogMessage -Message "=== Script Completed Successfully ===" -Level Success

    $exitCode = 0
}
catch {
    Write-LogMessage -Message "CRITICAL ERROR: $($_.Exception.Message)" -Level Error
    Write-LogMessage -Message "Stack Trace: $($_.ScriptStackTrace)" -Level Error
    $exitCode = 1
}
finally {
    Stop-Transcript

    # Open log file if there were changes or errors
    if ($exitCode -ne 0 -or $addedTags.Count -gt 0 -or $removedTags.Count -gt 0) {
        Start-Process notepad.exe -ArgumentList $logFile
    }
}

exit $exitCode

#endregion
