<#
.SYNOPSIS
    Check whether each path listed in a text file exists on the local computer.
.DESCRIPTION
    Reads a list of file/folder paths, tests each one with Test-Path and writes Path / Exists to a
    CSV named after the hostname in the user's profile folder, then opens it. Handy for verifying
    that a software deployment or GPO landed on a set of machines.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : nothing special
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Test-PathsExist.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Define the input file path
$inputFilePath = "C:\Scripts\Input\Input.txt"
# -------------------------------------------------------------------------

# Read the list of paths from the input file
$paths = Get-Content -Path $inputFilePath

# Initialize an empty array to store the results
$results = @()

# Loop through each path and check if it exists
foreach ($path in $paths) {
    $exists = Test-Path -Path $path
    $results += [PSCustomObject]@{
        "Path" = $path
        "Exists" = $exists
    }
}

# Define the output file path with the hostname
$outputFileName = "$env:COMPUTERNAME.csv"
$outputFilePath = Join-Path -Path $env:USERPROFILE -ChildPath $outputFileName

# Export the results to a CSV file
$results | Export-Csv -Path $outputFilePath -NoTypeInformation

# Display a message indicating where the results were saved
Write-Host "Results saved to $outputFilePath"
start $outputFilePath
