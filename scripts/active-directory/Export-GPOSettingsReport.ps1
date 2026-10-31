#Requires -Modules GroupPolicy, ActiveDirectory

<#
.SYNOPSIS
    Exports every configured setting of every GPO in the domain (parsed from the GPO XML report) to CSV and/or HTML.
.DESCRIPTION
    For each GPO, collects metadata (status, links, owner, WMI filter, dates) and recursively parses
    the Get-GPOReport XML to flatten administrative templates, security settings, scripts, folder
    redirection, software installation and preferences into Scope/Category/Setting/Value rows.
    Writes one CSV row per setting (default .\all-gpo-details.csv) and optionally a collapsible
    HTML report; prints to console when neither export is requested.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : GroupPolicy + ActiveDirectory modules (RSAT) | domain read access
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Export-GPOSettingsReport.ps1
    .\Export-GPOSettingsReport.ps1 -ExportCsv "C:\Scripts\Reports\GPOSettings.csv"
    .\Export-GPOSettingsReport.ps1 -ExportHtml "C:\Scripts\Reports\GPOReport.html"
#>

param(
    [string]$ExportCsv = '.\all-gpo-details.csv',
    [string]$ExportHtml
)

# ── Prerequisites ────────────────────────────────────────────────────────────
Import-Module GroupPolicy     -ErrorAction Stop
Import-Module ActiveDirectory -ErrorAction Stop
Add-Type -AssemblyName System.Web   # HtmlEncode is used while building the HTML sections

$domain     = Get-ADDomain
$domainDN   = $domain.DistinguishedName
$domainName = $domain.DNSRoot

Write-Host "`nQuerying all GPOs in domain: $domainName ...`n" -ForegroundColor Cyan

# ── Helper: resolve linked OUs for a GPO ────────────────────────────────────
function Get-GPOLinks {
    param([string]$GpoId)
    $links = @()
    $bases = @($domainDN)
    $bases += Get-ADOrganizationalUnit -Filter * -SearchBase $domainDN |
              Select-Object -ExpandProperty DistinguishedName
    foreach ($base in $bases) {
        try {
            $obj = Get-ADObject -Identity $base -Properties gpLink,DistinguishedName -ErrorAction SilentlyContinue
            if ($obj.gpLink -and $obj.gpLink -match $GpoId) { $links += $obj.DistinguishedName }
        } catch {}
    }
    try {
        Get-ADObject -Filter { ObjectClass -eq "site" } `
                     -SearchBase "CN=Sites,CN=Configuration,$domainDN" `
                     -Properties gpLink,DistinguishedName -ErrorAction SilentlyContinue |
        Where-Object { $_.gpLink -match $GpoId } |
        ForEach-Object { $links += $_.DistinguishedName }
    } catch {}
    return ($links -join " | ")
}

# ── Helper: decode GPO status ────────────────────────────────────────────────
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

# ── Helper: recursively parse XML nodes into flat setting rows ───────────────
# Returns a plain array (@()) — safe regardless of 0, 1, or many results.
function Parse-GPOSettings {
    param(
        [System.Xml.XmlElement]$Node,
        [string]$Scope,
        [string]$Category = ""
    )

    $rows = @()

    foreach ($child in $Node.ChildNodes) {
        if ($child -isnot [System.Xml.XmlElement]) { continue }

        $localName = $child.LocalName
        $crumb     = if ($Category) { "$Category > $localName" } else { $localName }

        $settingName  = $null
        $settingValue = $null

        switch -Regex ($localName) {

            # Administrative Templates
            "^Policy$" {
                $settingName  = $child.Name
                $settingValue = if ($child.State)   { $child.State }
                               elseif ($child.Value) { $child.Value }
                               else                  { "(Configured)" }
                $items = $child.SelectNodes("*[local-name()='DropDownList' or local-name()='Numeric' or local-name()='Text' or local-name()='CheckBox']")
                if ($items.Count -gt 0) {
                    $extras = foreach ($it in $items) {
                        "$($it.Name)=$($it.Value)$($it.State)$($it.InnerText)".Trim("=")
                    }
                    $settingValue = "$settingValue | $($extras -join '; ')"
                }
            }

            # Security settings
            "^(Account|Password|Lockout|Audit|UserRight|SecurityOption|EventLog|RestrictedGroup|SystemService|Registry|FileSystem)$" {
                $settingName  = if ($child.Name)       { $child.Name }
                               elseif ($child.KeyName) { $child.KeyName }
                               else                    { $localName }
                $settingValue = if ($child.SettingNumber)      { $child.SettingNumber }
                               elseif ($child.SettingBoolean)  { $child.SettingBoolean }
                               elseif ($child.SettingStrings)  { ($child.SettingStrings.Value -join ", ") }
                               elseif ($child.Member)          { ($child.SelectNodes("*//@Name") | ForEach-Object { $_.Value }) -join ", " }
                               else                            { $child.InnerText.Trim() }
            }

            # Scripts
            "^Script$" {
                $settingName  = "Script ($($child.Type))"
                $settingValue = "$($child.Command) $($child.Parameters)".Trim()
            }

            # Folder Redirection
            "^(Folder|FolderRedirectionSetting)$" {
                $settingName  = "Folder Redirection: $($child.Id)$($child.Name)"
                $settingValue = if ($child.Location.DestinationPath) { $child.Location.DestinationPath } else { $child.InnerText.Trim() }
            }

            # Software Installation
            "^(Package|ManagedPackage)$" {
                $settingName  = "Software: $($child.Name)"
                $settingValue = "Action=$($child.Action)  Path=$($child.Path)"
            }

            # Preferences
            "^(Drive|Printer|LocalUser|LocalGroup|ScheduledTask|Service|Shortcut|DataSource|Device|NetworkOption|EnvironmentVariable|IniFile|InternetOption|RegionalOption|StartMenuProperty)$" {
                $settingName  = "${localName}: $($child.name)$($child.Name)$($child.id)"
                $attrs        = $child.Attributes | ForEach-Object { "$($_.Name)=$($_.Value)" }
                $settingValue = "Action=$($child.action)$($child.Action)  $($attrs -join '  ')".Trim()
            }

            # IE / Proxy / generic leaf nodes
            "^(Url|Proxy|Connection|ZoneMaps|Site)$" {
                $settingName  = $localName
                $settingValue = $child.InnerText.Trim()
            }

            default {
                $childElements = @($child.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] })
                if ($childElements.Count -eq 0) {
                    $settingName  = $localName
                    $settingValue = $child.InnerText.Trim()
                    if ([string]::IsNullOrWhiteSpace($settingValue)) {
                        $settingValue = ($child.Attributes | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join "  "
                    }
                }
            }
        }

        if ($null -ne $settingName) {
            $rows += [PSCustomObject]@{
                Scope    = $Scope
                Category = $Category
                Setting  = $settingName
                Value    = $settingValue
            }
        } else {
            # Recurse — use @() to guarantee an array is returned
            $rows += @(Parse-GPOSettings -Node $child -Scope $Scope -Category $crumb)
        }
    }

    return $rows   # always a plain array
}

# ── Helper: extract all settings from GPO XML report ────────────────────────
function Get-GPOSettingsList {
    param([string]$GpoId, [string]$Domain)

    [xml]$report = Get-GPOReport -Guid $GpoId -ReportType Xml -Domain $Domain
    $settings    = @()

    foreach ($scope in @("Computer", "User")) {
        $section = $report.GPO.$scope
        if (-not $section) { continue }
        foreach ($ext in $section.ExtensionData) {
            if (-not $ext.Extension) { continue }
            $settings += @(Parse-GPOSettings -Node $ext.Extension -Scope $scope -Category $ext.Name)
        }
    }

    if ($settings.Count -eq 0) {
        $settings += [PSCustomObject]@{
            Scope    = "-"
            Category = "-"
            Setting  = "(No settings configured)"
            Value    = ""
        }
    }
    return $settings
}

# ── Main ─────────────────────────────────────────────────────────────────────
$allGpos  = Get-GPO -All -Domain $domainName
$total    = $allGpos.Count
$allRows  = @()
$htmlSections = [System.Text.StringBuilder]::new()

$i = 0
foreach ($gpo in $allGpos) {
    $i++
    Write-Progress -Activity "Processing GPOs" `
                   -Status "$i of $total — $($gpo.DisplayName)" `
                   -PercentComplete (($i / $total) * 100)

    $sysvol = "\\$domainName\SYSVOL\$domainName\Policies\{$($gpo.Id)}"
    $adPath = "CN={$($gpo.Id)},CN=Policies,CN=System,$domainDN"
    $scope  = Get-GPOLinks -GpoId $gpo.Id.ToString()
    if ([string]::IsNullOrWhiteSpace($scope)) { $scope = "(Not Linked)" }
    $wmi    = if ($gpo.WmiFilter) { $gpo.WmiFilter.Name } else { "(None)" }
    $status = Get-GPOStatusText $gpo.GpoStatus

    $settings = @(Get-GPOSettingsList -GpoId $gpo.Id.ToString() -Domain $domainName)

    # ── Flat rows for CSV ────────────────────────────────────────────────
    foreach ($s in $settings) {
        $allRows += [PSCustomObject]@{
            "GPO Name"          = $gpo.DisplayName
            "GPO UniqueID"      = "{$($gpo.Id)}"
            "GPO Status"        = $status
            "GPO Path (SYSVOL)" = $sysvol
            "GPO AD Path"       = $adPath
            "Linked Scope"      = $scope
            "Domain"            = $gpo.DomainName
            "Owner"             = $gpo.Owner
            "WMI Filter"        = $wmi
            "Created"           = $gpo.CreationTime
            "Last Modified"     = $gpo.ModificationTime
            "Setting Scope"     = $s.Scope
            "Setting Category"  = $s.Category
            "Setting Name"      = $s.Setting
            "Setting Value"     = $s.Value
        }
    }

    # ── Console output ───────────────────────────────────────────────────
    if (-not $ExportCsv -and -not $ExportHtml) {
        Write-Host ("═" * 80) -ForegroundColor Cyan
        Write-Host "  GPO Name     : $($gpo.DisplayName)" -ForegroundColor White
        Write-Host "  Unique ID    : {$($gpo.Id)}"
        Write-Host "  Status       : $status"
        Write-Host "  SYSVOL Path  : $sysvol"
        Write-Host "  AD Path      : $adPath"
        Write-Host "  Linked Scope : $scope"
        Write-Host "  Owner        : $($gpo.Owner)"
        Write-Host "  WMI Filter   : $wmi"
        Write-Host "  Created      : $($gpo.CreationTime)"
        Write-Host "  Modified     : $($gpo.ModificationTime)"
        if ($gpo.Description) { Write-Host "  Description  : $($gpo.Description)" }

        Write-Host "`n  SETTINGS:" -ForegroundColor Yellow
        $grouped = $settings | Group-Object -Property Scope
        foreach ($grp in $grouped) {
            Write-Host "  ┌─ $($grp.Name) Configuration" -ForegroundColor DarkYellow
            foreach ($cat in ($grp.Group | Group-Object -Property Category)) {
                Write-Host "  │  [$($cat.Name)]" -ForegroundColor DarkCyan
                foreach ($s in $cat.Group) {
                    Write-Host ("  │    {0,-55} {1}" -f $s.Setting, $s.Value)
                }
            }
        }
        Write-Host ""
    }

    # ── HTML section ─────────────────────────────────────────────────────
    if ($ExportHtml) {
        $settingsHtml = [System.Text.StringBuilder]::new()
        foreach ($grp in ($settings | Group-Object -Property Scope)) {
            [void]$settingsHtml.Append("<h3>$($grp.Name) Configuration</h3>")
            foreach ($cat in ($grp.Group | Group-Object -Property Category)) {
                [void]$settingsHtml.Append("<h4>$([System.Web.HttpUtility]::HtmlEncode($cat.Name))</h4><table>")
                [void]$settingsHtml.Append("<tr><th>Setting</th><th>Value</th></tr>")
                foreach ($s in $cat.Group) {
                    [void]$settingsHtml.Append("<tr><td>$([System.Web.HttpUtility]::HtmlEncode($s.Setting))</td><td>$([System.Web.HttpUtility]::HtmlEncode($s.Value))</td></tr>")
                }
                [void]$settingsHtml.Append("</table>")
            }
        }

        [void]$htmlSections.Append(@"
<div class='gpo-card'>
  <div class='gpo-header' onclick='toggle(this)'>
    <span class='gpo-title'>$([System.Web.HttpUtility]::HtmlEncode($gpo.DisplayName))</span>
    <span class='gpo-status'>$status</span>
  </div>
  <div class='gpo-body'>
    <table class='meta'>
      <tr><td>Unique ID</td><td>{$($gpo.Id)}</td></tr>
      <tr><td>SYSVOL Path</td><td>$sysvol</td></tr>
      <tr><td>AD Path</td><td>$adPath</td></tr>
      <tr><td>Linked Scope</td><td>$([System.Web.HttpUtility]::HtmlEncode($scope))</td></tr>
      <tr><td>Owner</td><td>$([System.Web.HttpUtility]::HtmlEncode($gpo.Owner))</td></tr>
      <tr><td>WMI Filter</td><td>$wmi</td></tr>
      <tr><td>Created</td><td>$($gpo.CreationTime)</td></tr>
      <tr><td>Last Modified</td><td>$($gpo.ModificationTime)</td></tr>
      $(if ($gpo.Description) { "<tr><td>Description</td><td>$([System.Web.HttpUtility]::HtmlEncode($gpo.Description))</td></tr>" })
    </table>
    <div class='settings'>$($settingsHtml.ToString())</div>
  </div>
</div>
"@)
    }
}

Write-Progress -Activity "Processing GPOs" -Completed

# ── Export CSV ───────────────────────────────────────────────────────────────
if ($ExportCsv) {
    $allRows | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "Exported $($allRows.Count) setting rows ($total GPOs) to: $ExportCsv" -ForegroundColor Green
}

# ── Export HTML ──────────────────────────────────────────────────────────────
if ($ExportHtml) {
    $html = @"
<!DOCTYPE html>
<html lang='en'>
<head>
<meta charset='UTF-8'>
<title>GPO Report — $domainName</title>
<style>
  body { font-family: Segoe UI, sans-serif; background:#1a1a2e; color:#e0e0e0; margin:0; padding:20px; }
  h1   { color:#00d4ff; }
  h2   { color:#aaa; font-size:.9em; margin-top:-10px; }
  .gpo-card   { background:#16213e; border:1px solid #0f3460; border-radius:8px; margin:12px 0; overflow:hidden; }
  .gpo-header { display:flex; justify-content:space-between; align-items:center;
                padding:12px 16px; background:#0f3460; cursor:pointer; user-select:none; }
  .gpo-header:hover { background:#1a4a80; }
  .gpo-title  { font-weight:600; font-size:1em; color:#fff; }
  .gpo-status { font-size:.8em; padding:3px 8px; border-radius:12px; background:#00d4ff22; color:#00d4ff; }
  .gpo-body   { padding:16px; display:none; }
  table       { width:100%; border-collapse:collapse; margin:8px 0 16px; font-size:.85em; }
  table.meta td:first-child { color:#00d4ff; width:160px; font-weight:600; padding:4px 8px 4px 0; vertical-align:top; }
  table.meta td { padding:4px 8px 4px 0; border-bottom:1px solid #0f3460; word-break:break-all; }
  .settings h3 { color:#00d4ff; font-size:.95em; margin:16px 0 4px; border-bottom:1px solid #0f3460; padding-bottom:4px; }
  .settings h4 { color:#aaa; font-size:.85em; margin:10px 0 4px; }
  .settings table th { text-align:left; color:#888; font-weight:500; padding:4px 8px; background:#0a1628; }
  .settings table td { padding:4px 8px; border-bottom:1px solid #0f3460; word-break:break-word; }
  .settings table tr:hover td { background:#0f3460; }
  .summary { color:#aaa; font-size:.9em; margin-bottom:20px; }
</style>
</head>
<body>
<h1>Group Policy Object Report</h1>
<h2>Domain: $domainName</h2>
<p class='summary'>Generated: $(Get-Date)  &nbsp;|&nbsp;  Total GPOs: $total</p>
$($htmlSections.ToString())
<script>
function toggle(el){ var b=el.nextElementSibling; b.style.display=b.style.display==='block'?'none':'block'; }
</script>
</body></html>
"@
    [System.IO.File]::WriteAllText($ExportHtml, $html, [System.Text.Encoding]::UTF8)
    Write-Host "HTML report ($total GPOs) saved to: $ExportHtml" -ForegroundColor Green
}

if (-not $ExportCsv -and -not $ExportHtml) {
    Write-Host ("═" * 80) -ForegroundColor Cyan
    Write-Host "`nTotal GPOs processed: $total" -ForegroundColor Cyan
}
