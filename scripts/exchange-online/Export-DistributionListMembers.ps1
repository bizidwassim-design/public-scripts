<#
.SYNOPSIS
    Exports every Exchange Online distribution list with its members to a single CSV.
.DESCRIPTION
    Enumerates all distribution groups, lists the members of each (one row per member, or a
    placeholder row for empty lists) with the member's display name, SMTP address and recipient
    type, and writes the result to CSV.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ExchangeOnlineManagement
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Export-DistributionListMembers.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$OutputPath = "C:\Scripts\Reports\DL_Members.csv"
# -------------------------------------------------------------------------

Connect-ExchangeOnline

$Results = @()

Get-DistributionGroup -ResultSize Unlimited | ForEach-Object {
    $DL = $_
    Write-Host "Traitement : $($DL.DisplayName)" -ForegroundColor Cyan

    $Members = Get-DistributionGroupMember -Identity $DL.Identity -ResultSize Unlimited

    if ($Members.Count -eq 0) {
        $Results += [PSCustomObject]@{
            ListeDistribution = $DL.DisplayName
            ListeEmail        = $DL.PrimarySmtpAddress
            MembreNom         = "(Aucun membre)"
            MembreEmail       = ""
            MembreType        = ""
        }
    }
    else {
        foreach ($Member in $Members) {
            $Results += [PSCustomObject]@{
                ListeDistribution = $DL.DisplayName
                ListeEmail        = $DL.PrimarySmtpAddress
                MembreNom         = $Member.DisplayName
                MembreEmail       = $Member.PrimarySmtpAddress
                MembreType        = $Member.RecipientType
            }
        }
    }
}

$Results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "`nExport terminé : $($Results.Count) entrées dans $OutputPath" -ForegroundColor Green
