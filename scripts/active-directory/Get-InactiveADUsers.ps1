<#
.SYNOPSIS
    Export enabled AD users that have not logged on for N days, with their extensionAttribute tags.
.DESCRIPTION
    Searches the given base DN for enabled users whose LastLogonDate is older than $days,
    selects SamAccountName, LastLogonDate and extensionAttribute1-5 / 10-15 and exports them to CSV,
    then opens the file. Optional email block left commented out.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-InactiveADUsers.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$ou          = "DC=corp,DC=contoso,DC=local"
$worksfolder = "C:\Scripts\Reports"
#define days days the period which users did not logged and you want to disable
$days        = 90
# -------------------------------------------------------------------------

if ( !(test-path "$worksfolder")) {
    Write-Verbose "Folder [$($worksfolder)] does not exist, creating"
    new-item $worksFolder -type directory -Force
}

#you can change the path where users will be exported.
$exportedpath= "$worksfolder\inactiveusers.csv"

Import-Module activedirectory

get-aduser -filter 'enabled -eq $true' -SearchBase $ou -Properties samaccountname,lastlogondate, extensionAttribute1, extensionAttribute2, extensionAttribute3, extensionAttribute4, extensionAttribute5, extensionAttribute10, extensionAttribute11, extensionAttribute12, extensionAttribute13, extensionAttribute14, extensionAttribute15 |
Where-object {$_.lastlogondate -lt (get-date).AddDays(-$days)} |select samaccountname,lastlogondate,extensionAttribute1, extensionAttribute2, extensionAttribute3, extensionAttribute4, extensionAttribute5, extensionAttribute10, extensionAttribute11, extensionAttribute12, extensionAttribute13, extensionAttribute14, extensionAttribute15  | export-csv $exportedpath -nti

start $exportedpath

#$body="GC $exportedpath"
#Send-MailMessage -to security@contoso.com -From alerts@contoso.com -SmtpServer smtp.contoso.com -Body $body -Subject "Inactive users"
