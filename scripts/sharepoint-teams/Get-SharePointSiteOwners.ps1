<#
.SYNOPSIS
    Audits the owners of a list of SharePoint Online sites (cleanup candidates) via Microsoft Graph.
.DESCRIPTION
    For each site URL in the list, resolves the site ID, looks for the backing Microsoft 365 group
    (by mailNickname) and lists its owners; falls back to the site permissions "owner" role when
    there is no group. Exports one CSV row per owner (or an "AUCUN OWNER"/"ERREUR" row) and
    prints a summary. Authenticates with device code.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Microsoft.Graph.Authentication (Sites.Read.All, GroupMember.Read.All, Directory.Read.All)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-SharePointSiteOwners.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$TenantId     = "<TENANT-ID>"
$SharePointHost = "contoso.sharepoint.com"
$OutputCSV    = "C:\Scripts\Reports\SPO_Owners_$(Get-Date -f yyyyMMdd_HHmm).csv"

# ── Liste des sites a auditer (Name = libelle, Url = URL complete du site) ──
$sites = @(
    [PSCustomObject]@{ Name = "Document Center";   Url = "https://$SharePointHost/sites/DocumentCenter" }
    [PSCustomObject]@{ Name = "IT Guide";          Url = "https://$SharePointHost/sites/ITGuide" }
    [PSCustomObject]@{ Name = "Finance Direction"; Url = "https://$SharePointHost/sites/Finance_Direction" }
)
# -------------------------------------------------------------------------

# ── Connexion ─────────────────────────────────────────────────────────────────
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

Write-Host ""
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "   Audit Owners Sites SharePoint ($($sites.Count) sites)" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

Write-Host "`n[AUTH] Connexion Device Code..." -ForegroundColor Yellow
Write-Host "       Va sur https://microsoft.com/devicelogin et entre le code`n" -ForegroundColor Gray

Connect-MgGraph -TenantId $TenantId `
                -Scopes "Sites.Read.All","GroupMember.Read.All","Directory.Read.All" `
                -UseDeviceAuthentication `
                -NoWelcome

Write-Host "[AUTH] Connecte : $((Get-MgContext).Account)`n" -ForegroundColor Green

# ── Output dir ────────────────────────────────────────────────────────────────
$outputDir = Split-Path $OutputCSV
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }

# ── Boucle sur chaque site ────────────────────────────────────────────────────
$report  = [System.Collections.Generic.List[PSCustomObject]]::new()
$counter = 0

foreach ($site in $sites) {
    $counter++
    $siteName = $site.Name
    $siteUrl  = $site.Url
    $slug     = $siteUrl.Split('/')[-1]

    Write-Progress -Activity "Audit Owners" `
                   -Status "$counter / $($sites.Count) -- $siteName" `
                   -PercentComplete ([math]::Round($counter / $sites.Count * 100))

    Write-Host "[$counter/$($sites.Count)] $siteName" -ForegroundColor Yellow -NoNewline

    $siteId       = $null
    $groupId      = $null
    $owners       = @()
    $errorMsg     = $null

    # 1. Resoudre le Site ID
    try {
        $hostname = $SharePointHost
        $sitePath = $siteUrl -replace "https://$SharePointHost",""
        $siteResp = Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/sites/${hostname}:${sitePath}?`$select=id,displayName" `
            -ErrorAction Stop
        $siteId = $siteResp.id
    } catch {
        $errorMsg = "Site ID introuvable: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))"
    }

    # 2. Chercher le groupe M365
    if ($siteId -and -not $errorMsg) {
        try {
            $groupResp = Invoke-MgGraphRequest -Method GET `
                -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=startswith(mailNickname,'$slug')&`$select=id,displayName,mail" `
                -ErrorAction Stop

            if ($groupResp.value -and $groupResp.value.Count -gt 0) {
                $groupId = $groupResp.value[0].id
            }
        } catch { }
    }

    # 3a. Owners via groupe M365
    if ($groupId) {
        try {
            $ownersResp = Invoke-MgGraphRequest -Method GET `
                -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/owners?`$select=displayName,mail,userPrincipalName,jobTitle" `
                -ErrorAction Stop
            $owners = $ownersResp.value
        } catch {
            $errorMsg = "Erreur owners groupe: $($_.Exception.Message.Substring(0,[Math]::Min(80,$_.Exception.Message.Length)))"
        }
    }

    # 3b. Fallback via site permissions si pas de groupe
    if (-not $groupId -and $siteId -and -not $errorMsg) {
        try {
            $permsResp = Invoke-MgGraphRequest -Method GET `
                -Uri "https://graph.microsoft.com/v1.0/sites/$siteId/permissions?`$select=roles,grantedToIdentitiesV2" `
                -ErrorAction SilentlyContinue
            if ($permsResp -and $permsResp.value) {
                $ownerPerms = $permsResp.value | Where-Object { $_.roles -contains "owner" }
                $owners = $ownerPerms | ForEach-Object {
                    $_.grantedToIdentitiesV2 | ForEach-Object {
                        [PSCustomObject]@{
                            displayName     = $_.user.displayName
                            mail            = $_.user.email
                            userPrincipalName = $_.user.email
                            jobTitle        = ""
                        }
                    }
                } | Where-Object { $_ }
            }
        } catch { }
    }

    # 4. Construire les lignes CSV (1 ligne par owner)
    if ($errorMsg) {
        $report.Add([PSCustomObject]@{
            SiteName     = $siteName
            SiteURL      = $siteUrl
            OwnerCount   = 0
            OwnerName    = "ERREUR"
            OwnerEmail   = $errorMsg
            OwnerTitle   = ""
            GroupId      = if ($groupId) { $groupId } else { "N/A" }
            Status       = "ERREUR"
        })
        Write-Host " --> ERREUR" -ForegroundColor Red
    } elseif ($owners.Count -eq 0) {
        $report.Add([PSCustomObject]@{
            SiteName     = $siteName
            SiteURL      = $siteUrl
            OwnerCount   = 0
            OwnerName    = "AUCUN OWNER"
            OwnerEmail   = ""
            OwnerTitle   = ""
            GroupId      = if ($groupId) { $groupId } else { "N/A" }
            Status       = "SANS OWNER"
        })
        Write-Host " --> AUCUN OWNER" -ForegroundColor Red
    } else {
        foreach ($o in $owners) {
            $email = if ($o.mail) { $o.mail } else { $o.userPrincipalName }
            $report.Add([PSCustomObject]@{
                SiteName     = $siteName
                SiteURL      = $siteUrl
                OwnerCount   = $owners.Count
                OwnerName    = $o.displayName
                OwnerEmail   = $email
                OwnerTitle   = if ($o.jobTitle) { $o.jobTitle } else { "" }
                GroupId      = if ($groupId) { $groupId } else { "N/A" }
                Status       = "OK"
            })
        }
        $ownerNames = ($owners | ForEach-Object { $_.displayName }) -join ", "
        Write-Host " --> $($owners.Count) owner(s): $ownerNames" -ForegroundColor Green
    }
}

Write-Progress -Activity "Audit Owners" -Completed

# ── Export CSV ────────────────────────────────────────────────────────────────
$report | Export-Csv -Path $OutputCSV -NoTypeInformation -Encoding UTF8

# ── Resume console ────────────────────────────────────────────────────────────
$okCount    = ($report | Where-Object { $_.Status -eq "OK" } | Select-Object SiteURL -Unique).Count
$noOwner    = ($report | Where-Object { $_.Status -eq "SANS OWNER" }).Count
$errorCount = ($report | Where-Object { $_.Status -eq "ERREUR" }).Count

Write-Host ""
Write-Host "=================================================" -ForegroundColor Green
Write-Host "   RESUME" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green
Write-Host "  Sites traites     : $($sites.Count)" -ForegroundColor White
Write-Host "  Avec owners       : $okCount" -ForegroundColor Green
Write-Host "  Sans owner        : $noOwner" -ForegroundColor Red
Write-Host "  Erreurs           : $errorCount" -ForegroundColor Yellow
Write-Host ""
Write-Host "=== DETAILS ===" -ForegroundColor Cyan
$report | Select-Object SiteName, OwnerCount, OwnerName, OwnerEmail | Format-Table -AutoSize -Wrap

try { Disconnect-MgGraph | Out-Null } catch {}

Write-Host ""
Write-Host "=================================================" -ForegroundColor Green
Write-Host "  [DONE] CSV exporte :" -ForegroundColor Green
Write-Host "  $OutputCSV" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Green
