<#
.SYNOPSIS
    Exports every SharePoint Online site, its SharePoint groups and the members of each group to a CSV.
.DESCRIPTION
    Connects to the SharePoint Online admin endpoint, enumerates all site collections, then for
    each site lists the site groups (Owners, Members, Visitors, ...) and their users.
    Output: one CSV row per Site / Group / User login name.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : SharePoint Online Management Shell (Microsoft.Online.SharePoint.PowerShell) | SharePoint admin
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Export-SPOSiteGroupMembers.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$siteUrl    = "https://contoso-admin.sharepoint.com"   # SharePoint admin centre URL
$username   = "admin@contoso.com"
$OutputPath = "C:\Scripts\Reports\SharePoint_Sites_Groups_Users.csv"
# -------------------------------------------------------------------------

# Connect to SharePoint Online (interactive; MFA-capable)
$credential = Get-Credential -UserName $username -Message "SharePoint Online admin"
Connect-SPOService -Url $siteUrl -Credential $credential

# Get all sites
$sites = Get-SPOSite -Limit All

# Prepare data for CSV
$data = @()
foreach ($site in $sites) {
    $siteUrl = $site.Url
    $groups = Get-SPOSiteGroup -Site $siteUrl
    foreach ($group in $groups) {
        $groupName = $group.Title
        $users = Get-SPOUser -Site $siteUrl -Group $groupName
        foreach ($user in $users) {
            $data += New-Object PSObject -Property @{
                'Site' = $siteUrl
                'Group' = $groupName
                'User' = $user.LoginName
            }
        }
    }
}

# Export data to CSV
$data | Export-Csv -Path $OutputPath -NoTypeInformation
