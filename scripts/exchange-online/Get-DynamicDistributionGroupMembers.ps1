<#
.SYNOPSIS
    Export the resolved membership of an Exchange Online dynamic distribution group to CSV.
.DESCRIPTION
    Connects to Exchange Online, finds the dynamic distribution group whose name matches
    $GroupName, evaluates its recipient filter and exports the members to a CSV file, then opens it.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ExchangeOnlineManagement
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-DynamicDistributionGroupMembers.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$GroupName  = "AllUsers"                 # name (wildcards allowed) of the dynamic distribution group
$OutputPath = ".\ddg-members.csv"
# -------------------------------------------------------------------------

# Import the module
Import-Module ExchangeOnlineManagement

# Connect to Exchange Online
Connect-ExchangeOnline
Get-DynamicDistributionGroup |?{$_.name -like $GroupName} | Get-DynamicDistributionGroupMember  |export-csv -Path $OutputPath -Encoding utf8
start $OutputPath
