<#
.SYNOPSIS
    Disables the AD computer objects listed in a text file and moves them to a "Disabled" OU.
.DESCRIPTION
    Reads computer names (one per line) from a text file. For each one, disables the computer
    account and moves the object to the target OU. Success or failure is written to the console.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Modifies AD (disables computer accounts and moves them to another OU)
    License     : MIT
.EXAMPLE
    .\Disable-ADComputersFromList.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Path to the text file containing computer names (one per line)
$computerNamesFile = "C:\Scripts\Input\ComputerNames.txt"

# OU path where disabled computer objects will be moved
$targetOU = "OU=Disabled,OU=Computers,DC=corp,DC=contoso,DC=local"
# -------------------------------------------------------------------------

# Read computer names from the file
$computerNames = Get-Content -Path $computerNamesFile

# Iterate through each computer name, disable the object, and move to the target OU
foreach ($computerName in $computerNames) {
    try {
        # Disable the computer object
        Disable-ADAccount -Identity $computerName

        # Move the disabled computer object to the target OU
        Get-ADComputer -Identity $computerName | Move-ADObject -TargetPath $targetOU -Confirm:$false

        Write-Host "Successfully disabled and moved '$computerName' to '$targetOU'"
    } catch {
        Write-Host "Error processing '$computerName': $_"
    }
}
