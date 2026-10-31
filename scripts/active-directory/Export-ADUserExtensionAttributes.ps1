<#
.SYNOPSIS
    Export the extensionAttribute "tags" of every enabled AD user to CSV.
.DESCRIPTION
    Selects Name, SamAccountName, mail, Enabled, Description, extensionAttribute1-7 and 10-15 and
    DistinguishedName for all enabled users, writes them to a UTF-8 CSV and opens it. Companion to
    the tag-compliance scripts that use extensionAttributes as security classification tags.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Export-ADUserExtensionAttributes.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Define the output file path
$outputFilePath = "C:\Scripts\Reports\ExportUsersExtensionAttributes.csv"
# -------------------------------------------------------------------------

# Import the Active Directory module if not already loaded
Import-Module ActiveDirectory

# Get all user accounts and select the desired properties
$users = Get-ADUser -Filter {Enabled -eq $true} -Properties * |
select Name,  SamAccountName, mail, enabled,  Description, extensionAttribute1, extensionAttribute2, extensionAttribute3, extensionAttribute4, extensionAttribute5, extensionAttribute6, extensionAttribute7, extensionAttribute10, extensionAttribute11, extensionAttribute12, extensionAttribute13, extensionAttribute14, extensionAttribute15, DistinguishedName|
Export-Csv -Path $outputFilePath -NoTypeInformation -encoding UTF8


# Open the exported file
Start-Process $outputFilePath
