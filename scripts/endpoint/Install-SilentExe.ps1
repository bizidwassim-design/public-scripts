<#
.SYNOPSIS
    Download an .exe installer to the user's Downloads folder and run it silently.
.DESCRIPTION
    Template for unattended software deployment: downloads the installer from a URL, launches it
    with the vendor's silent switch (/S here, WinRAR as the example) and checks that the expected
    executable exists afterwards. Adapt the URL, silent switch and verification path to your product.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin
    Impact      : Modifies endpoint (installs software)
    License     : MIT
.EXAMPLE
    .\Install-SilentExe.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Define the URL of the WinRAR installer
$WinRARInstallerURL = "https://www.example.com/winrar_installer.exe"  # Replace with the actual download link
$InstallerArguments = "/S"                                             # vendor silent switch
$VerifyPath         = "C:\Program Files\WinRAR\WinRAR.exe"             # file that proves the install worked
# -------------------------------------------------------------------------

# Get the path to the user's Downloads folder
$DownloadsFolder = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::UserProfile) + "\Downloads"

# Define the path for saving the downloaded installer
$InstallerPath = Join-Path -Path $DownloadsFolder -ChildPath "winrar_installer.exe"

# Download the WinRAR installer
Invoke-WebRequest -Uri $WinRARInstallerURL -OutFile $InstallerPath

# Check if the download was successful
if (Test-Path $InstallerPath) {
    Write-Host "WinRAR installer downloaded to $InstallerPath"

    # Perform a silent installation of WinRAR
    Start-Process -FilePath $InstallerPath -ArgumentList $InstallerArguments -Wait

    # Check if WinRAR was installed successfully
    if (Test-Path $VerifyPath) {
        Write-Host "WinRAR was installed successfully."
    } else {
        Write-Host "WinRAR installation failed."
    }
} else {
    Write-Host "Failed to download the WinRAR installer."
}
