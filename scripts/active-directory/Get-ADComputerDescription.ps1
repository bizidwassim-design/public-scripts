<#
.SYNOPSIS
    Retrieves the AD Description attribute for a list of computer names and exports it to a CSV.
.DESCRIPTION
    Reads computer names (one per line) from a text file, looks each one up in Active Directory
    and collects its Description (usually the owner / usage). Computers not found are reported
    on the console. Results are exported to a CSV which is then opened.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ADComputerDescription.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Path to the text file containing computer names
$ComputerListFile = "C:\Scripts\Input\ComputerList.txt"

# Path to the CSV file to export results
$ExportCSVFile = "C:\Scripts\Reports\ComputerDescriptions.csv"
# -------------------------------------------------------------------------

# Initialize an empty array to store results
$Results = @()

# Read computer names from the text file
$ComputerNames = Get-Content -Path $ComputerListFile

# Iterate through each computer name and retrieve description from Active Directory
foreach ($ComputerName in $ComputerNames) {
    # Get computer object from Active Directory
    $Computer = Get-ADComputer -Filter { Name -eq $ComputerName } -Properties Description

    # Check if computer object exists
    if ($Computer) {
        # Add computer name and description to results array
        $Results += [PSCustomObject]@{
            'ComputerName' = $Computer.Name
            'Description'  = $Computer.Description
        }
    } else {
        # Output a message if computer object not found
        Write-Host "Computer '$ComputerName' not found in Active Directory" -ForegroundColor Yellow
    }
}

# Export results to CSV file
$Results | Export-Csv -Path $ExportCSVFile -NoTypeInformation
start $ExportCSVFile
