#Requires -Modules GroupPolicy, ActiveDirectory

<#
.SYNOPSIS
    Inventories every GPO in the domain (status, links, versions, owner, WMI filter) to CSV or console.
.DESCRIPTION
    Retrieves all GPOs with Get-GPO, resolves where each one is linked (domain root, every OU and
    AD sites), decodes the status, builds the SYSVOL and AD paths and exports one row per GPO to
    CSV (default .\all-gpos.csv) or prints the details to the console when -ExportCsv is empty.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : GroupPolicy + ActiveDirectory modules (RSAT) | domain read access
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-GPOInventory.ps1
    .\Get-GPOInventory.ps1 -ExportCsv "C:\Scripts\Reports\GPOs.csv"
#>

param(
    [string]$ExportCsv = '.\all-gpos.csv'
)

# ── Prerequisites ────────────────────────────────────────────────────────────
Import-Module GroupPolicy  -ErrorAction Stop
Import-Module ActiveDirectory -ErrorAction Stop

$domain     = Get-ADDomain
$domainDN   = $domain.DistinguishedName
$domainName = $domain.DNSRoot

Write-Host "`nQuerying all GPOs in domain: $domainName ...`n" -ForegroundColor Cyan

# ── Helper: resolve linked OUs for a GPO ────────────────────────────────────
function Get-GPOLinks {
    param([string]$GpoId)

    $links = @()

    # Search all OUs, the domain root, and sites for GP links
    $searchBases = @(
        $domainDN   # domain root
    )
    $searchBases += (Get-ADOrganizationalUnit -Filter * -SearchBase $domainDN |
                        Select-Object -ExpandProperty DistinguishedName)

    foreach ($base in $searchBases) {
        try {
            $obj = Get-ADObject -Identity $base `
                                -Properties gpLink, DistinguishedName `
                                -ErrorAction SilentlyContinue
            if ($obj.gpLink -and $obj.gpLink -match $GpoId) {
                $links += $obj.DistinguishedName
            }
        } catch { }
    }

    # Also check Sites container
    $sitesContainer = "CN=Sites,CN=Configuration,$domainDN"
    try {
        Get-ADObject -Filter { ObjectClass -eq "site" } `
                     -SearchBase $sitesContainer `
                     -Properties gpLink, DistinguishedName `
                     -ErrorAction SilentlyContinue |
        Where-Object { $_.gpLink -match $GpoId } |
        ForEach-Object { $links += $_.DistinguishedName }
    } catch { }

    return ($links -join " | ")
}

# ── Helper: decode GPO status integer ───────────────────────────────────────
function Get-GPOStatusText {
    param([Microsoft.GroupPolicy.GpoStatus]$Status)
    switch ($Status) {
        "AllSettingsEnabled"       { "All Settings Enabled" }
        "UserSettingsDisabled"     { "User Settings Disabled" }
        "ComputerSettingsDisabled" { "Computer Settings Disabled" }
        "AllSettingsDisabled"      { "All Settings Disabled" }
        default                    { $Status.ToString() }
    }
}

# ── Main: collect GPO data ───────────────────────────────────────────────────
$allGpos   = Get-GPO -All -Domain $domainName
$totalGpos = $allGpos.Count
$results   = [System.Collections.Generic.List[PSCustomObject]]::new()
$i         = 0

foreach ($gpo in $allGpos) {
    $i++
    Write-Progress -Activity "Processing GPOs" `
                   -Status "$i of $totalGpos — $($gpo.DisplayName)" `
                   -PercentComplete (($i / $totalGpos) * 100)

    # GPO path in SYSVOL
    $sysvol = "\\$domainName\SYSVOL\$domainName\Policies\{$($gpo.Id)}"

    # Linked scope
    $scope = Get-GPOLinks -GpoId $gpo.Id.ToString()
    if ([string]::IsNullOrWhiteSpace($scope)) { $scope = "(Not Linked)" }

    # WMI filter (if any)
    $wmiFilter = if ($gpo.WmiFilter) { $gpo.WmiFilter.Name } else { "(None)" }

    $results.Add( [PSCustomObject] @{
        "Name"              = $gpo.DisplayName
        "UniqueID"          = "{$($gpo.Id)}"
        "Status"            = Get-GPOStatusText $gpo.GpoStatus
        "Path (SYSVOL)"     = $sysvol
        "AD Path"           = "CN={$($gpo.Id)},CN=Policies,CN=System,$domainDN"
        "Linked Scope"      = $scope
        "Domain"            = $gpo.DomainName
        "Owner"             = $gpo.Owner
        "WMI Filter"        = $wmiFilter
        "User Ver (AD)"     = $gpo.User.DSVersion
        "User Ver (SYSVOL)" = $gpo.User.SysvolVersion
        "Comp Ver (AD)"     = $gpo.Computer.DSVersion
        "Comp Ver (SYSVOL)" = $gpo.Computer.SysvolVersion
        "Created"           = $gpo.CreationTime
        "Last Modified"     = $gpo.ModificationTime
        "Description"       = $gpo.Description
    } )
}

Write-Progress -Activity "Processing GPOs" -Completed

# ── Output ───────────────────────────────────────────────────────────────────
if ($ExportCsv) {
    $results | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Exported $($results.Count) GPOs to: $ExportCsv" -ForegroundColor Green
}
else {
    foreach ($r in $results) {
        Write-Host ("─" * 70) -ForegroundColor DarkGray
        Write-Host "  Name         : " -NoNewline -ForegroundColor Yellow
        Write-Host $r.Name
        Write-Host "  Unique ID    : " -NoNewline -ForegroundColor Yellow
        Write-Host $r.UniqueID
        Write-Host "  Status       : " -NoNewline -ForegroundColor Yellow
        Write-Host $r.Status
        Write-Host "  Path (SYSVOL): " -NoNewline -ForegroundColor Yellow
        Write-Host $r."Path (SYSVOL)"
        Write-Host "  AD Path      : " -NoNewline -ForegroundColor Yellow
        Write-Host $r."AD Path"
        Write-Host "  Linked Scope : " -NoNewline -ForegroundColor Yellow
        Write-Host $r."Linked Scope"
        Write-Host "  Domain       : " -NoNewline -ForegroundColor Yellow
        Write-Host $r.Domain
        Write-Host "  Owner        : " -NoNewline -ForegroundColor Yellow
        Write-Host $r.Owner
        Write-Host "  WMI Filter   : " -NoNewline -ForegroundColor Yellow
        Write-Host $r."WMI Filter"
        Write-Host "  Versions     : " -NoNewline -ForegroundColor Yellow
        Write-Host ("User AD:{0} SYSVOL:{1}  |  Comp AD:{2} SYSVOL:{3}" -f `
            $r."User Ver (AD)", $r."User Ver (SYSVOL)", `
            $r."Comp Ver (AD)", $r."Comp Ver (SYSVOL)")
        Write-Host "  Created      : " -NoNewline -ForegroundColor Yellow
        Write-Host $r.Created
        Write-Host "  Last Modified: " -NoNewline -ForegroundColor Yellow
        Write-Host $r."Last Modified"
        if ($r.Description) {
            Write-Host "  Description  : " -NoNewline -ForegroundColor Yellow
            Write-Host $r.Description
        }
    }

    Write-Host ("─" * 70) -ForegroundColor DarkGray
    Write-Host "`nTotal GPOs found: $($results.Count)" -ForegroundColor Cyan
}
