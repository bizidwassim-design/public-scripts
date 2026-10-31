<#
.SYNOPSIS
    Rename the built-in local Administrator (RID 500), set a per-host password and make sure it is enabled.
.DESCRIPTION
    Finds the local account whose SID ends in -500, renames it to $newAdminName and resets its
    password (prompted as a SecureString). If an account with the new name already
    exists, only the password is updated. Finally the account is enabled if it was disabled.
    Intended to be pushed by an RMM / GPO startup script. Prefer LAPS when available.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin (Microsoft.PowerShell.LocalAccounts)
    Impact      : Modifies local accounts (rename, password reset, enable)
    License     : MIT
.EXAMPLE
    .\Rename-LocalAdminAccount.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$newAdminName = "LocalAdmin"                # new name for the built-in administrator
# Password: prompted here. For unattended RMM/GPO deployment, replace with a value from your secret store
# (or, better, let LAPS manage this account's password after the rename).
$newPassword  = Read-Host -Prompt "New password for $newAdminName" -AsSecureString
# -------------------------------------------------------------------------

# Function to rename and reset the password of the local administrator account
function Rename-AdminAccount {
    # Get the local administrator account
    $adminAccount = Get-LocalUser | Where-Object { $_.SID -match '-500$' }

    # Check if the renamed account already exists
    $renamedAccount = Get-LocalUser -Name $newAdminName -ErrorAction SilentlyContinue

    if ($renamedAccount -ne $null) {
        # Update the password for the existing renamed account
        $renamedAccount | Set-LocalUser -Password $newPassword
        Write-Output "The password for the local administrator account '$newAdminName' has been updated."
    } elseif ($adminAccount -ne $null) {
        # Check if the local administrator account is already renamed
        if ($adminAccount.Name -eq $newAdminName) {
            Write-Output "The native local administrator account is already named '$newAdminName'. Exiting the script."
            return
        }

        # Rename the local administrator account
        Rename-LocalUser -Name $adminAccount.Name -NewName $newAdminName

        # Set the new password for the renamed administrator account
        $adminAccount | Set-LocalUser -Password $newPassword

        Write-Output "The local administrator account has been renamed to $newAdminName and its password has been reset."
    } else {
        Write-Output "The local administrator account could not be found."
    }
}

# Prompt for the username to check
$username = $newAdminName
if (!($username))
{
# Run the function
Rename-AdminAccount

}
# Check if the user account exists
if (Get-LocalUser -Name $username -ErrorAction SilentlyContinue) {
    Write-Host "The user account '$username' exists on this system."

    # Get the user account
    $user = Get-LocalUser -Name $username

    if ($user.Enabled -eq $false) {
        Write-Host "The user account is currently disabled."

        try {
            # Enable the account without confirmation
            Enable-LocalUser -Name $username -Confirm:$false
            Write-Host "The user account '$username' has been successfully enabled."
        }
        catch {
            Write-Host "An error occurred while trying to enable the account: $_"
        }
    }
    else {
        Write-Host "The user account is already enabled."
    }
}
else {
    Write-Host "The user account '$username' does not exist on this system."
}
