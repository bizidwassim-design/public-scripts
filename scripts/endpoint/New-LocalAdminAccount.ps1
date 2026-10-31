<#
.SYNOPSIS
    Creates a local administrator account and adds it to the built-in Administrators group (language independent).
.DESCRIPTION
    Resolves the Administrators group by its well-known SID (S-1-5-32-544) so the script works on
    French and English Windows alike, creates the local user if it does not exist and makes sure it
    is a member of the group. Intended for deployment through an RMM/GPO before LAPS takes over the
    password management.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin | Microsoft.PowerShell.LocalAccounts (Windows 10 / Server 2016+)
    Impact      : Creates a local user and adds it to the local Administrators group
    License     : MIT
.EXAMPLE
    .\New-LocalAdminAccount.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
#Paramètres
$UserName = "AdminContoso"
# Interactive prompt; for unattended deployment, fetch the password from your vault instead (LAPS takes over afterwards)
$Password = Read-Host -Prompt "Initial password for $UserName" -AsSecureString
#Le mot de passe sera changé par l'application LAPS

$Description = "Local administrator account created by script"
# -------------------------------------------------------------------------

#vérification si c'est Administrateurs ou Administrators
$GroupSID = "S-1-5-32-544"
$GroupName = (Get-LocalGroup |?{$_.SID -like $GroupSID}).name

#Vérifie si l'utilisateur existe déjà

$User = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

if ($User -eq $null) {
    # Crée un nouvel utilisateur
    New-LocalUser -Name $UserName -Password $Password -Description $Description


# Ajoute l'utilisateur au groupe Administrateurs
Add-LocalGroupMember -Group $GroupName -Member $UserName

Write-Output "L'utilisateur $UserName a été créé et ajouté au groupe Administrateurs."
} else {
    Write-Output "L'utilisateur $UserName existe déjà."
}
#Vérifie si l'utilisateur est membre du groupe Administrateurs

$GroupMember = Get-LocalGroupMember -Group $GroupName -Member $UserName -ErrorAction SilentlyContinue

if ($GroupMember -eq $null) {
    # Ajoute l'utilisateur au groupe Administrateurs si pas encore ajouté
    Add-LocalGroupMember -Group $GroupName -Member $UserName
    Write-Output "L'utilisateur $UserName a été ajouté au groupe Administrateurs."
} else {
    Write-Output "L'utilisateur $UserName est déjà membre du groupe Administrateurs."
}
