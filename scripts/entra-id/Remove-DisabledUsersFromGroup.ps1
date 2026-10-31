#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Users

<#
.SYNOPSIS
    Removes disabled Entra ID users from a licensing/access group (e.g. the Atlassian users group).
.DESCRIPTION
    Connects to Microsoft Graph, enumerates the members of the target group, checks each member's
    accountEnabled flag, removes disabled accounts from the group and writes a timestamped CSV of
    the removed users plus a log file. Supports -WhatIf (dry run, CSV suffixed -WHATIF).
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Microsoft.Graph (GroupMember.ReadWrite.All, User.Read.All)
    Impact      : Modifies Entra ID (removes group members)
    License     : MIT
.EXAMPLE
    .\Remove-DisabledUsersFromGroup.ps1
    .\Remove-DisabledUsersFromGroup.ps1 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param ()

# ---- EDIT ME ------------------------------------------------------------
$groupName = "GRP-Atlassian-Users"                                # display name of the group to clean
$baseDir   = "C:\Scripts\Reports\RemoveDisabledUsersFromGroup"   # CSV output folder
# -------------------------------------------------------------------------

# ─── Output paths ────────────────────────────────────────────────────────────

$logDir    = Join-Path $baseDir "logs"
$datestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$logPath = Join-Path $logDir  "GroupCleanup_$datestamp.log"
$csvPath = Join-Path $baseDir "RemovedUsers_$datestamp.csv"

# Create directories if they don't exist
foreach ($dir in @($baseDir, $logDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# ─── Logging ─────────────────────────────────────────────────────────────────

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logPath -Value $line
    switch ($Level) {
        'ERROR'   { Write-Host $line -ForegroundColor Red }
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $line -ForegroundColor Green }
        default   { Write-Host $line }
    }
}

# ─── Connect to Microsoft Graph ──────────────────────────────────────────────

Write-Log "Script started."
Write-Log "Log file   : $logPath"
Write-Log "CSV output : $csvPath"

$requiredScopes = @(
    "GroupMember.ReadWrite.All",   # Remove members from groups
    "User.Read.All"                # Read user account status
)

try {
    Write-Log "Connecting to Microsoft Graph..."
    Connect-MgGraph -Scopes $requiredScopes -NoWelcome -ErrorAction Stop
    Write-Log "Connected successfully." -Level SUCCESS
} catch {
    Write-Log "Failed to connect to Microsoft Graph: $_" -Level ERROR
    exit 1
}

# ─── Find the target group ───────────────────────────────────────────────────

try {
    Write-Log "Looking up group: $groupName"
    $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop

    if (-not $group) {
        Write-Log "Group '$groupName' not found. Verify the display name and try again." -Level ERROR
        Disconnect-MgGraph | Out-Null
        exit 1
    }

    if ($group.Count -gt 1) {
        Write-Log "Multiple groups matched '$groupName'. Aborting to avoid unintended changes." -Level ERROR
        Disconnect-MgGraph | Out-Null
        exit 1
    }

    Write-Log "Found group: $($group.DisplayName) (ID: $($group.Id))"
} catch {
    Write-Log "Error retrieving group: $_" -Level ERROR
    Disconnect-MgGraph | Out-Null
    exit 1
}

# ─── Get group members ───────────────────────────────────────────────────────

try {
    Write-Log "Retrieving group members..."
    $members = Get-MgGroupMember -GroupId $group.Id -All -ErrorAction Stop
    Write-Log "Total members found: $($members.Count)"
} catch {
    Write-Log "Error retrieving group members: $_" -Level ERROR
    Disconnect-MgGraph | Out-Null
    exit 1
}

# ─── Process each member ─────────────────────────────────────────────────────

$removedCount = 0
$skippedCount = 0
$errorCount   = 0
$nonUserCount = 0
$removedUsers = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($member in $members) {
    # Groups can contain users, service principals, devices, etc.
    # Only process User objects.
    if ($member.AdditionalProperties.'@odata.type' -ne '#microsoft.graph.user') {
        Write-Log "Skipping non-user member: $($member.Id) (type: $($member.AdditionalProperties.'@odata.type'))" -Level WARN
        $nonUserCount++
        continue
    }

    try {
        $user = Get-MgUser -UserId $member.Id `
            -Property "id,displayName,userPrincipalName,accountEnabled,jobTitle,department,mail" `
            -ErrorAction Stop
    } catch {
        Write-Log "Could not retrieve user details for ID $($member.Id): $_" -Level ERROR
        $errorCount++
        continue
    }

    $upn  = $user.UserPrincipalName
    $name = $user.DisplayName

    if ($user.AccountEnabled -eq $false) {
        if ($PSCmdlet.ShouldProcess("$name ($upn)", "Remove from $groupName")) {
            try {
                Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
                Write-Log "REMOVED: $name ($upn) - account is disabled." -Level SUCCESS

                $removedUsers.Add([PSCustomObject]@{
                    DisplayName       = $name
                    UserPrincipalName = $upn
                    Mail              = $user.Mail
                    JobTitle          = $user.JobTitle
                    Department        = $user.Department
                    ObjectId          = $user.Id
                    RemovedAt         = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                    WhatIf            = $false
                })
                $removedCount++
            } catch {
                Write-Log "Failed to remove $name ($upn): $_" -Level ERROR
                $errorCount++
            }
        } else {
            # -WhatIf path
            Write-Log "[WHATIF] Would remove: $name ($upn) - account is disabled." -Level WARN

            $removedUsers.Add([PSCustomObject]@{
                DisplayName       = $name
                UserPrincipalName = $upn
                Mail              = $user.Mail
                JobTitle          = $user.JobTitle
                Department        = $user.Department
                ObjectId          = $user.Id
                RemovedAt         = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                WhatIf            = $true
            })
            $removedCount++
        }
    } else {
        Write-Log "Keeping: $name ($upn) - account is enabled."
        $skippedCount++
    }
}

# ─── Export CSV ──────────────────────────────────────────────────────────────

if ($removedUsers.Count -gt 0) {
    # If this was a -WhatIf run, label the CSV so it's obvious
    if ($WhatIfPreference) {
        $csvPath = $csvPath -replace '\.csv$', '-WHATIF.csv'
    }

    try {
        $removedUsers | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        Write-Log "CSV report saved: $csvPath" -Level SUCCESS
    } catch {
        Write-Log "Failed to write CSV report: $_" -Level ERROR
    }
} else {
    Write-Log "No users were removed - CSV report not created."
}

# ─── Summary ─────────────────────────────────────────────────────────────────

Write-Log "──────────────────────────────────────────"
Write-Log "Run complete."
Write-Log "  Removed (disabled users) : $removedCount"
Write-Log "  Kept   (enabled users)   : $skippedCount"
Write-Log "  Non-user members skipped : $nonUserCount"
Write-Log "  Errors                   : $errorCount"
Write-Log "  Log file                 : $logPath"
if ($removedUsers.Count -gt 0) {
Write-Log "  CSV report               : $csvPath"
}
Write-Log "──────────────────────────────────────────"

Disconnect-MgGraph | Out-Null
Write-Log "Disconnected from Microsoft Graph."
