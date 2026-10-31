<#
.SYNOPSIS
    Remove duplicate rows from a CSV file based on one column.
.DESCRIPTION
    Imports a CSV, keeps a single row per distinct value of $KeyColumn (first match after sorting)
    and writes the unique rows to a new CSV file.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : nothing special
    Impact      : Read-only (writes a new file)
    License     : MIT
.EXAMPLE
    .\Remove-CsvDuplicates.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
#Define the input and output file paths
$inputFilePath  = "C:\Scripts\input.csv"
$outputFilePath = "C:\Scripts\output.csv"
$KeyColumn      = "ip address"       # column used to detect duplicates
# -------------------------------------------------------------------------

#Read the CSV file into a PowerShell array
$csvData = Import-Csv -Path $inputFilePath

#Remove duplicate lines based on the key column
$uniqueRecords = $csvData | Sort-Object -Property $KeyColumn -Unique

#Export the unique records to a new CSV file
$uniqueRecords | Export-Csv -Path $outputFilePath -NoTypeInformation

#Output a message indicating the process is complete
Write-Host "Unique records exported to $outputFilePath"
