<#
.SYNOPSIS
    Replaces a text string in every file of a folder (in place).
.DESCRIPTION
    Reads each file of the target directory, replaces every occurrence of $oldText with $newText
    (regex replace) and writes the content back. Originally used to re-point printer label
    templates to another data source. Take a backup of the folder first: there is no undo.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : write access to the target folder
    Impact      : Modifies files in place (text replace in every file of the folder)
    License     : MIT
.EXAMPLE
    .\Update-TextInFiles.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Define the directory path
$directory = "C:\ProgramData\VendorApp\Templates"

# Define the text to be replaced and the new text
$oldText = "OLD_VALUE"
$newText = "NEW_VALUE"
# -------------------------------------------------------------------------

# Get all files in the directory with the specified file extension
$files = Get-ChildItem -Path $directory -File
write-output $files


# Iterate through each file and replace the text
foreach ($file in $files) {
    # Read the content of the file
    $content = Get-Content $file.FullName -Raw

    # Replace the text
    $newContent = $content -replace $oldText, $newText

    # Write the modified content back to the file
    $newContent | Set-Content $file.FullName
}
