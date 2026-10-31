<#
.SYNOPSIS
    Resolve the owner (and owner email) of a list of AD computers from the computer Description field.
.DESCRIPTION
    Reads hostnames from a text file. For each computer, reads its AD Description (expected to hold
    the owner's full name), looks the user up by Name and exports ComputerName / Enabled /
    Description / Email to a CSV, flagging computers or users that are not found.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-ComputerOwners.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$InputPath  = "C:\Scripts\input.txt"                 # one hostname per line
$OutputPath = "C:\Scripts\ComputerDescriptions.csv"
# -------------------------------------------------------------------------

$computerNames = Get-Content -Path $InputPath

$results = @()

foreach ($computerName in $computerNames) {
    $computer = Get-ADComputer -Filter {Name -eq $computerName} -Properties Description
    if ($computer) {

    # Set the full name of the user you want to find
                $fullName = $computer.Description

                # Retrieve the user based on their full name
                $user = Get-ADUser -Filter {Name -eq $fullName} -Properties EmailAddress

                # Check if the user was found and display their email address
                if ($user) { $email = $user.EmailAddress }
                else {$email= "User with full name '$fullName' not found in AD."}

        $results += [PSCustomObject]@{
            ComputerName = $computer.Name
            Enabled = $computer.Enabled
            Description = $computer.Description
            Email = $email
        }
    } else {
        $results += [PSCustomObject]@{
            ComputerName = $computerName
            Enabled = "Computer not found in AD"
            Description = "Computer not found in AD"
            Email = "Computer not found in AD"
        }
    }
}

$results | Export-Csv -Path $OutputPath -NoTypeInformation -encoding utf8
start $OutputPath
