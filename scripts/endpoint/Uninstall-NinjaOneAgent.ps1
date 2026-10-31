<#
.SYNOPSIS
    Force-removes a broken NinjaOne agent (MSI uninstall, service deletion, program folder removal) before reinstalling.
.DESCRIPTION
    Runs MsiExec /X with the agent's product code, then deletes the NinjaRMMAgent service and the
    NinjaOne program folder as a fallback. Used when an endpoint stops reporting live data to
    NinjaOne (e.g. after a full disk) so the agent can be redeployed through PDQ Deploy.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin
    Impact      : Modifies the local machine (uninstalls the RMM agent, deletes a service and a folder)
    License     : MIT
.EXAMPLE
    .\Uninstall-NinjaOneAgent.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# MSI product code of your NinjaOne agent. Find it with:
#   Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object DisplayName -like 'NinjaRMM*' | Select-Object DisplayName, PSChildName
$NinjaOneProductCode = "{<NINJAONE-MSI-PRODUCT-CODE>}"
$NinjaOnePath        = "${env:PROGRAMFILES(X86)}\NinjaOne"
# -------------------------------------------------------------------------

# This command for sure uninstalls NinjaOne, even if it fails to uninstall from the Control Panel.
MsiExec.exe /X $NinjaOneProductCode /passive /quiet /qn /norestart /log output.log

# Assuming that doesn't work, delete the service manually
sc.exe query NinjaRMMAgent
sc.exe delete NinjaRMMAgent
# sc.exe query NinjaRMMAgent

# and delete the program files
Get-ChildItem "$NinjaOnePath"
Remove-Item -Force -Recurse "$NinjaOnePath"
# Get-Item "$NinjaOnePath"
