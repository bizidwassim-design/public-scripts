<#
.SYNOPSIS
    Audit the local SMB shares that grant permissions to "Everyone".
.DESCRIPTION
    Enumerates non-special SMB shares on the local server, reads the NTFS ACL of each share path
    and reports every ACE granted to the Everyone principal (share, path, rights).
    Results are exported to a per-server CSV and opened.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin (SmbShare module, local)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-PublicSharedFolders.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$ReportDir      = "C:\Scripts\Reports\AuditPublic"
$excludedfolder = "C:\Windows\system32\spool\drivers"
# -------------------------------------------------------------------------

$result = @()

$server = $env:COMPUTERNAME
$csvPath = "$ReportDir\$server-public-shared-folders.csv"
# Create the folder if it doesn't exist
if (-not (Test-Path -Path $ReportDir)) {
    New-Item -ItemType Directory -Path $ReportDir | Out-Null
}

# Get all shared folders
$sharedFolders = Get-SmbShare | Where-Object { $_.Special -eq $false -and $_.Name -ne "IPC$" -and ($_.Path -like "*\*" -and $_.Path -notlike $excludedfolder) } -ErrorAction SilentlyContinue

# Audit the shared folders
foreach ($folder in $sharedFolders) {
    $ACL = Get-Acl -Path $folder.Path
    $everyonePermissions = $ACL.Access | Where-Object { $_.IdentityReference -like "Everyone" } -ErrorAction SilentlyContinue

    if ($everyonePermissions) {
        foreach ($everyonePermission in $everyonePermissions) {
            # Convert FileSystemRights to a comma-separated string
            $permissionsString = ($everyonePermission.FileSystemRights -join ", ")

            $result += [PSCustomObject]@{
                ServerName          = $server
                FolderName          = $folder.Name
                Path                = $folder.Path
                Everyone            = $everyonePermission.IdentityReference.ToString()  # Ensure it's a string
                Everyone_Permissions = $permissionsString  # Use the formatted permissions string
            }
        }
    }
}

# Export the results to a CSV file
$result | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "Audit results exported to: $csvPath"

# Open the CSV file
Start-Process $csvPath
