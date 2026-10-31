<#
.SYNOPSIS
    Creates a local "technician" account and adds it to the built-in Administrators group.
.DESCRIPTION
    Exits if the user already exists; otherwise creates the local account, then resolves the
    Administrators group by its well-known SID (S-1-5-32-544, language independent) and adds the
    user to it. Every step is wrapped in try/catch and reported on the console.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin | Microsoft.PowerShell.LocalAccounts (Windows 10 / Server 2016+)
    Impact      : Creates a local user and adds it to the local Administrators group
    License     : MIT
.EXAMPLE
    .\New-LocalTechnicianAccount.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Define the new user credentials
$username = "technician"
# Interactive prompt; for unattended deployment, fetch the password from your vault instead
$password = Read-Host -Prompt "Initial password for $username" -AsSecureString
# -------------------------------------------------------------------------

# Check if the user already exists
try {
    $user = Get-LocalUser -Name $username -ErrorAction Stop
    Write-Output "User '$username' already exists. No action taken."
    exit
} catch {
    Write-Output "User '$username' does not exist. Proceeding with creation."
}

# Create the new local user account with a shorter description
try {
    New-LocalUser -Name $username -Password $password -FullName "Technician Account" -Description "Local admin account"
    Write-Output "User '$username' has been created."
} catch {
    Write-Output "Failed to create user '$username'. Error: $_"
    exit
}

# Get the name of the Administrators group based on its SID
$adminGroupSID = "S-1-5-32-544"
try {
    $adminGroupName = (Get-LocalGroup | Where-Object { $_.SID -eq $adminGroupSID }).Name
    if ($adminGroupName) {
        # Add the new user to the Administrators group using the group name
        Add-LocalGroupMember -Group $adminGroupName -Member $username
        Write-Output "User '$username' has been added to the '$adminGroupName' group."
    } else {
        Write-Output "Failed to find the Administrators group by SID."
    }
} catch {
    Write-Output "Failed to add user '$username' to the Administrators group. Error: $_"
}
