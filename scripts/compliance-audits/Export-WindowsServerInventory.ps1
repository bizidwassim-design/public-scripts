<#
.SYNOPSIS
    Monthly check: counts enabled Windows Server computer objects by OS version and emails the report.
.DESCRIPTION
    Queries Active Directory for enabled computers whose OperatingSystem is "Windows Server*",
    exports Name/OperatingSystem to a dated CSV, prints a per-version breakdown
    (2008/2012/2016/2019/2022/2025) to the console and sends an HTML summary email with the CSV attached.
    End-of-life versions are flagged in the email and on the console.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | SMTP relay
    Impact      : Read-only (writes a CSV, sends an email)
    License     : MIT
.EXAMPLE
    .\Export-WindowsServerInventory.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$searchBase   = "DC=corp,DC=contoso,DC=local"
$outputDir    = "C:\Scripts\Reports"
$smtpServer   = "smtp.contoso.com"
$from         = "it-support@contoso.com"
$emailaddress = "security@contoso.com"
# -------------------------------------------------------------------------

# Import the Active Directory module
Import-Module ActiveDirectory

# Define the search criteria
$filter = {OperatingSystem -like '*Windows Server*' -and Enabled -eq $true}

# Retrieve active computer objects with specified OS version
$computers = Get-ADComputer -Filter $filter -SearchBase $searchBase -Property OperatingSystem

# Specify the output file path
if (-not (Test-Path $outputDir)) { New-Item -Path $outputDir -ItemType Directory | Out-Null }
$outputFilePath = Join-Path $outputDir "serverlist_$(Get-Date -Format 'yyyyMMdd').csv"

# Export the results to a CSV file
$computers | Select-Object Name, OperatingSystem | Export-Csv -Path $outputFilePath -NoTypeInformation

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  INVENTAIRE DES SERVEURS WINDOWS - CONTOSO" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Group by operation system
$OS = @()
$OS = $computers | Select-Object Name, OperatingSystem
$i = $j = $k = $l = $m = $n2025 = 0

foreach ($O in $OS)
{
    if ($O.OperatingSystem.contains("2008")) {$i++}
    if ($O.OperatingSystem.contains("2012")) {$j++}
    if ($O.OperatingSystem.contains("2016")) {$k++}
    if ($O.OperatingSystem.contains("2019")) {$l++}
    if ($O.OperatingSystem.contains("2022")) {$m++}
    if ($O.OperatingSystem.contains("2025")) {$n2025++}
}

# Affichage des résultats
Write-Host "RÉPARTITION PAR VERSION:" -ForegroundColor Cyan
Write-Host "  $($i) Windows Server 2008" -ForegroundColor $(if ($i -gt 0) {"Red"} else {"Gray"})
Write-Host "  $($j) Windows Server 2012" -ForegroundColor $(if ($j -gt 0) {"Yellow"} else {"Gray"})
Write-Host "  $($k) Windows Server 2016" -ForegroundColor $(if ($k -gt 0) {"Yellow"} else {"Gray"})
Write-Host "  $($l) Windows Server 2019" -ForegroundColor $(if ($l -gt 0) {"Green"} else {"Gray"})
Write-Host "  $($m) Windows Server 2022" -ForegroundColor $(if ($m -gt 0) {"Green"} else {"Gray"})
Write-Host "  $($n2025) Windows Server 2025" -ForegroundColor $(if ($n2025 -gt 0) {"Green"} else {"Gray"})

$n = $i + $j + $k + $l + $m + $n2025

Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  TOTAL: $n serveurs Windows actifs" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════`n" -ForegroundColor Cyan

Write-Host "✓ Export terminé: $outputFilePath" -ForegroundColor Green

# Ouvrir le fichier CSV
Start-Process $outputFilePath

# Préparation de l'email
$subject = "Monthly check: number of operating systems grouped by version - $(Get-Date -Format 'MMMM yyyy')"

# Construction du corps de l'email avec support 2025
$body = @"
<html>
<head>
    <style>
        body { font-family: Calibri, Arial, sans-serif; }
        h3 { color: #0066cc; }
        .warning { color: #ff6600; font-weight: bold; }
        .critical { color: #cc0000; font-weight: bold; }
        .good { color: #00cc00; }
        table { border-collapse: collapse; margin: 20px 0; }
        td { padding: 5px 15px; }
        .version { font-weight: bold; }
    </style>
</head>
<body>
    <font face="calibri">
        <h2>Inventaire mensuel des serveurs Windows - Contoso</h2>

        <p>Bonjour,</p>

        <p>Veuillez noter que nous démarrons le nouveau mois avec <strong>$n serveurs Windows actifs</strong>, répartis comme suit par version d'OS :</p>

        <table>
            <tr>
                <td class="version">•</td>
                <td class="critical">$i Windows Server 2008</td>
                <td>$(if ($i -gt 0) {"⚠️ FIN DE VIE - Mise à niveau urgente requise"} else {""})</td>
            </tr>
            <tr>
                <td class="version">•</td>
                <td class="warning">$j Windows Server 2012</td>
                <td>$(if ($j -gt 0) {"⚠️ FIN DE VIE - Planifier migration"} else {""})</td>
            </tr>
            <tr>
                <td class="version">•</td>
                <td class="warning">$k Windows Server 2016</td>
                <td>$(if ($k -gt 0) {"⚠️ Support étendu - Planifier migration"} else {""})</td>
            </tr>
            <tr>
                <td class="version">•</td>
                <td class="good">$l Windows Server 2019</td>
                <td>$(if ($l -gt 0) {"✓ Support mainstream"} else {""})</td>
            </tr>
            <tr>
                <td class="version">•</td>
                <td class="good">$m Windows Server 2022</td>
                <td>$(if ($m -gt 0) {"✓ Version actuelle"} else {""})</td>
            </tr>
            <tr>
                <td class="version">•</td>
                <td class="good">$n2025 Windows Server 2025</td>
                <td>$(if ($n2025 -gt 0) {"✓ Dernière version"} else {""})</td>
            </tr>
        </table>

        <h3>Total: $n serveurs</h3>

        <p><em>Date du rapport: $(Get-Date -Format 'dd MMMM yyyy HH:mm')</em></p>

        <p>Cordialement,<br>
        Système automatisé Contoso IT</p>
    </font>
</body>
</html>
"@

# Ajouter la pièce jointe à l'email
$attachment = $outputFilePath

# Envoyer l'email avec la pièce jointe
Write-Host "Envoi de l'email..." -ForegroundColor Cyan
try {
    Send-MailMessage -SmtpServer $smtpServer `
                     -From $from `
                     -To $emailaddress `
                     -Subject $subject `
                     -Body $body `
                     -BodyAsHtml `
                     -Priority High `
                     -Encoding ([System.Text.Encoding]::UTF8) `
                     -Attachment $attachment

    Write-Host "✓ Email envoyé avec succès à $emailaddress" -ForegroundColor Green
} catch {
    Write-Host "✗ Erreur lors de l'envoi de l'email: $_" -ForegroundColor Red
}

# Affichage des versions obsolètes (avertissement)
if ($i -gt 0 -or $j -gt 0) {
    Write-Host "`n⚠️  ATTENTION: Serveurs avec versions obsolètes détectés!" -ForegroundColor Red
    if ($i -gt 0) {
        Write-Host "   → $i serveur(s) Windows Server 2008 (FIN DE VIE)" -ForegroundColor Red
    }
    if ($j -gt 0) {
        Write-Host "   → $j serveur(s) Windows Server 2012 (FIN DE VIE)" -ForegroundColor Red
    }
    Write-Host "   Action requise: Planifier migration urgente`n" -ForegroundColor Yellow
}

Write-Host "`n✓ Script terminé avec succès" -ForegroundColor Green
