<#
.SYNOPSIS
    Bulk-update the Manager attribute of AD users from an Excel sheet (employee name -> new manager name).
.DESCRIPTION
    Reads the worksheet with ImportExcel, resolves the DistinguishedName of the employee (column Name)
    and of the new manager (column FutureManager) by display name, then sets the Manager attribute.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | ImportExcel
    Impact      : Modifies AD (user Manager attribute)
    License     : MIT
.EXAMPLE
    .\Set-ADManagerFromExcel.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$FichierExcel  = "C:\Scripts\Input\manager_list.xlsx"
$WorksheetName = "IT task"
# -------------------------------------------------------------------------

# Importer les modules nécessaires
Import-Module ActiveDirectory
Import-Module ImportExcel

# Charger les données Excel
$ExcelData = Import-Excel -Path $FichierExcel -WorksheetName $WorksheetName

# Parcourir chaque ligne et mettre à jour le manager
foreach ($row in $ExcelData) {
	$User = $row.Name # Colonne B : nom de l'employé
    $Manager = $row.FutureManager # Colonne D : nom du nouveau manager
    $UserDN = Get-ADUser -Filter "Name -like '$User'" | Select-Object -ExpandProperty DistinguishedName #Recherche du DN du collaborateur
    $ManagerDN = Get-ADUser -Filter "Name -like '$Manager'" | Select-Object -ExpandProperty DistinguishedName #Recherche du DN du Manager
    #Write-Host "Personne $UserDN, nouveau manager $ManagerDN !" #Vérification de la donnée
    Set-ADUser -Identity $UserDN -Manager $ManagerDN #Changement des données
}
exit
