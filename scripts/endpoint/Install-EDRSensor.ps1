<#
.SYNOPSIS
    Copy the EDR sensor installer from a file share and install it silently on the local computer.
.DESCRIPTION
    Creates C:\temp, copies the EDR installer archive from an internal share, extracts it, makes sure
    PowerShellGet is present, then runs the sensor installer silently (step 2) and validates the
    outbound connection to the EDR cloud (step 3). Steps 2 and 3 are run from an elevated cmd prompt.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin | read access to the installer share
    Impact      : Modifies endpoint (installs the EDR sensor)
    License     : MIT
.EXAMPLE
    .\Install-EDRSensor.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$InstallerShare = "\\SRV-FILE01\IT-Support\installer\edr_installer_windows.zip"
$EdrHost        = "<EDR-SERVER-HOST>"     # host given by the EDR vendor
$EdrPort        = 443
$EdrTenant      = "contoso"               # tenant name given by the EDR vendor
$EdrCloudIpMask = ".*192\.0\.2\.1[0-3]:443.*"   # regex of the EDR cloud IP:port, for the netstat check
# -------------------------------------------------------------------------

#1) voici un script powershell pour installer EDR

if(!(Test-Path -Path "C:\temp" -PathType Container)){
    New-Item -ItemType Directory -Path "C:\temp"
}

copy $InstallerShare C:\temp\

if(Test-Path -Path "C:\temp\edr_installer_windows.zip" -PathType Leaf){
    Expand-Archive -Path C:\temp\edr_installer_windows.zip -DestinationPath c:\temp\edr -Force
}

try {

$ErrorActionPreference = 'stop'

if (!(Get-Module -ListAvailable -Name PowerShellGet)) {
    Write-Host "PowerShellGet module not found. Installing..."
    Install-Module -Name PowerShellGet -Force -Scope CurrentUser -Confirm:$false
} else {
    Write-Host "Updating PowerShellGet module..."
    Update-Module -Name PowerShellGet -Force -Confirm:$false
}

if (!(Get-Module -ListAvailable -Name PowerShell)) {
    Write-Host "PowerShell module not found. Installing..."
    Install-Module -Name PowerShell -Force -Scope CurrentUser -Confirm:$false
} else {
    Write-Host "Updating PowerShell module..."
    Update-Module -Name PowerShell -Force -Confirm:$false
}

$psVersionTable = $PSVersionTable.PSVersion
Write-Host "PowerShell version $($psVersionTable.Major).$($psVersionTable.Minor).$($psVersionTable.Build) installed successfully."
}
catch {
    Write-Warning "An error occurred while installing the module. Continuing execution..."

}

#2) puis via cmd lance ces commandes :
#
#   cd c:\temp\edr
#   start /wait "" "EDR_Sensor_Installer.exe" /S /HOST:"<EDR-SERVER-HOST>" /PORT:443 /TENANT:"contoso" && echo %ERRORLEVEL%
#
# Equivalent PowerShell :
Set-Location c:\temp\edr
Start-Process -FilePath ".\EDR_Sensor_Installer.exe" -ArgumentList "/S /HOST:`"$EdrHost`" /PORT:$EdrPort /TENANT:`"$EdrTenant`"" -Wait

#3) au final , validation :

netstat -anp TCP | findstr /R /C:"$EdrCloudIpMask"
