<#
.SYNOPSIS
    List enabled AD computers that have no EDR agent and workstations that have no PDQ Connect agent.
.DESCRIPTION
    Compares every enabled AD computer against two exported inventories (EDR console and PDQ Connect)
    and writes two CSV files: computers without EDR, and L-*/D-* workstations without PDQ Connect.
    Naming convention assumed: laptops start with "L-", desktops with "D-".
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-DevicesWithoutEDRAndPDQ.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$EDRInputFile   = "C:\Scripts\EDRInputList.txt"     # hostnames exported from the EDR console
$PDQInputFile   = "C:\Scripts\PDQInputList.txt"     # hostnames exported from PDQ Connect
$ExcludePattern = "*kiosk*"                          # AD computers to ignore (e.g. time clocks)
$WithoutEDRCsv  = "C:\Scripts\WithoutEDR.csv"
$WithoutPDQCsv  = "C:\Scripts\WithoutPDQC.csv"
# -------------------------------------------------------------------------

# read input values
$EDRInputList = Get-Content $EDRInputFile
$PDQInputList = Get-Content $PDQInputFile
$computers = (Get-ADComputer -Filter {(Enabled -eq $true) -and (-not (Name -like $ExcludePattern))}|select name).name
$WithoutEDR = @()
$WithoutPDQC = @()

# display Endpoints without EDR agent
foreach ($computer in $Computers)
{if ($EDRInputList -match $computer) { }  else { $WithoutEDR += $computer}
}

# display Endpoints without PDQ Connect agent
foreach ($computer in $Computers)
{
if ($PDQInputList -match $computer ) { }
else { if ($computer -like "d-*" -or $computer -like "l-*")	{ $WithoutPDQC += $computer	}}
}

$WithoutEDR
$WithoutEDR | Export-Csv $WithoutEDRCsv -Encoding UTF8
$WithoutPDQC
$WithoutPDQC | Export-Csv $WithoutPDQCsv -Encoding UTF8
