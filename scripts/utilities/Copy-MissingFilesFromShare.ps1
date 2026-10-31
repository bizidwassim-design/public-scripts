<#
.SYNOPSIS
    Copies the files of a network folder to a local folder, skipping files that already exist locally.
.DESCRIPTION
    Lists the files of a source (UNC) folder and copies each one to the destination folder only
    when a file of the same name is not already present. Originally used to replicate printer
    label templates from a reference server to a workstation (disaster-recovery "plan C").
    Sub-folders are not processed.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : read access to the source share | write access to the destination folder
    Impact      : Writes files to the destination folder (never overwrites)
    License     : MIT
.EXAMPLE
    .\Copy-MissingFilesFromShare.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Define the source (network) folder and destination (local) folder paths
$sourceFolder      = "\\SRV-APP01\C$\ProgramData\VendorApp\Templates"
$destinationFolder = "C:\ProgramData\VendorApp\Templates"
# -------------------------------------------------------------------------

# Get a list of files in the source folder
$sourceFiles = Get-ChildItem -Path $sourceFolder -File

# Iterate through each file in the source folder
foreach ($file in $sourceFiles) {
    # Construct the destination file path
    $destinationFilePath = Join-Path -Path $destinationFolder -ChildPath $file.Name

    # Check if the file already exists in the destination folder
    if (-not (Test-Path $destinationFilePath)) {
        # File does not exist in the destination folder, so copy it
        Copy-Item -Path $file.FullName -Destination $destinationFolder
        Write-Host "Copied $($file.Name) to $destinationFolder"
    }
    else {
        Write-Host "Skipping $($file.Name) as it already exists in $destinationFolder"
    }
}

Write-Host "Copy operation complete."
