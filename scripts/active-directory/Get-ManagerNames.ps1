<#
.SYNOPSIS
    Resolve the manager display name for a list of user email addresses.
.DESCRIPTION
    Reads email addresses from a text file, finds each AD user by EmailAddress, reads the Manager
    attribute and exports UserEmail / ManagerName to a UTF-8 CSV.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ManagerNames.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Set the path for the input text file containing user email addresses
$inputFilePath  = "C:\Scripts\Manager\UserEmails.txt"
# Set the path for the CSV output file
$outputFilePath = "C:\Scripts\Manager\ManagerInfo.csv"
# -------------------------------------------------------------------------

# Get the list of email addresses from the input text file
$emailAddresses = Get-Content -Path $inputFilePath

# Initialize an array to store the results
$results = @()

# Loop through each email address and find the corresponding manager
foreach ($email in $emailAddresses) {
    $user = Get-AdUser -Filter { EmailAddress -eq $email } -Properties Manager

    if ($user -ne $null) {
        $manager = Get-AdUser -Identity $user.Manager -Properties DisplayName

        $results += [PSCustomObject]@{
            UserEmail = $email
            ManagerName = $manager.DisplayName
        }
    }
}

# Export the results to a CSV file
$results | Export-Csv -Path $outputFilePath -NoTypeInformation -encoding UTF8

Write-Host "Script completed. Manager information exported to $outputFilePath."
