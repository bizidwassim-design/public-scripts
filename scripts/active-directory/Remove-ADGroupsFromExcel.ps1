<#
.SYNOPSIS
    Delete AD groups listed in an Excel file (DistinguishedName column), e.g. the empty groups found by Get-EmptyADGroups.
.DESCRIPTION
    Reads the workbook with ImportExcel and removes every group whose DistinguishedName is listed.
    Set $WhatIf = $true to only print the groups that would be deleted.
    Expected columns: Name (A), DistinguishedName (B).
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | ImportExcel
    Impact      : Modifies AD (deletes groups, no confirmation)
    License     : MIT
.EXAMPLE
    .\Remove-ADGroupsFromExcel.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$WhatIf       = $true                        # $false pour supprimer réellement
$FichierExcel = "C:\Scripts\Input\empty_ADGroup.xlsx"
# -------------------------------------------------------------------------

# Importer les modules nécessaires
Import-Module ActiveDirectory
Import-Module ImportExcel

# Charger les données Excel
$ExcelData = Import-Excel -Path $FichierExcel

# Parcourir chaque ligne et supprimer le groupe
foreach ($row in $ExcelData) {
	$group = $row.DistinguishedName # Colonne B : DistinguishedName du groupe
	if ($WhatIf) {
		Write-Host "WHATIF: Groupe AD a supprimer $group"  #Vérification de la donnée
	} else {
		Remove-ADGroup -Identity "$group" -Confirm:$false #Changement des données
	}
}
exit
