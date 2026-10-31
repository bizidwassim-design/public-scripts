<#
.SYNOPSIS
    Check whether each endpoint listed in the EDR console exists (and is enabled) in Active Directory.
.DESCRIPTION
    Reads a text file of hostnames exported from the EDR portal, looks each one up in AD and
    exports ComputerName / ExistsInAD / IsEnabled to a CSV. Useful to spot EDR agents that belong
    to decommissioned or unknown machines.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Compare-EDREndpointsWithAD.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Specify the path to your input text file containing computer names
$inputFilePath  = "C:\Scripts\edr\withedr.txt"
# Specify the path for the output CSV file
$outputFilePath = "C:\Scripts\edr\EDR_Vs_AD.csv"
# -------------------------------------------------------------------------

# Initialize an array to store the results
$results = @()

# Read computer names from the input file
$computerNames = Get-Content $inputFilePath

# Loop through each computer name
foreach ($computerName in $computerNames) {
    # Check if the computer exists in Active Directory
    $computer = Get-ADComputer -Filter {Name -eq $computerName} -Properties Enabled

    # Initialize a custom object to store the result
    $resultObject = New-Object PSObject -Property @{
        "ComputerName" = $computerName
        "ExistsInAD"   = [bool]($computer -ne $null)
        "IsEnabled"    = [bool]($computer.Enabled)
    }

    # Add the result object to the results array
    $results += $resultObject
}

# Export the results to a CSV file
$results | Export-Csv -Path $outputFilePath -NoTypeInformation

# Display a message indicating the task is complete
Write-Host "Task completed. Results exported to $outputFilePath"
