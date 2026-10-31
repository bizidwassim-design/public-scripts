<#
.SYNOPSIS
    Show the largest folders (and their sub-folders) under a path, sorted by size.
.DESCRIPTION
    Computes the recursive size of every first-level folder under $TargetPath, prints them largest
    first in GB, and indents the sub-folders of each one sorted by size. Useful to find what fills
    a profile or a data drive.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : nothing (run as admin to read all folders)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-LargestFolders.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$TargetPath = $env:USERPROFILE
# -------------------------------------------------------------------------

# Function to calculate folder size
function Get-FolderSize {
    param (
        [string]$Path
    )
    $size = (Get-ChildItem -Path $Path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    return $size
}

# Get all directories and their sizes
$Folders = Get-ChildItem -Path $TargetPath -Directory -ErrorAction SilentlyContinue |
    ForEach-Object {
        $Size = Get-FolderSize -Path $_.FullName
        [PSCustomObject]@{
            Folder   = $_.FullName
            Size     = $Size
        }
    }

# Sort folders by size (largest first)
$SortedFolders = $Folders | Sort-Object -Property Size -Descending

# Display results in a tree-like format
$SortedFolders | ForEach-Object {
    $SizeGB = "{0:N2} GB" -f ($_.Size / 1GB)
    Write-Host "[-] $($_.Folder) - $SizeGB" -ForegroundColor Yellow

    # Get subfolders sorted by size
    $SubFolders = Get-ChildItem -Path $_.Folder -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $SubSize = Get-FolderSize -Path $_.FullName
            [PSCustomObject]@{
                SubFolder = $_.FullName
                Size      = $SubSize
            }
        } | Sort-Object -Property Size -Descending

    # Display subfolders with indentation
    $SubFolders | ForEach-Object {
        $SubSizeGB = "{0:N2} GB" -f ($_.Size / 1GB)
        Write-Host "    |_ $($_.SubFolder) - $SubSizeGB" -ForegroundColor Cyan
    }
}
