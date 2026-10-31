<#
.SYNOPSIS
    Weekly report of enabled AD computers that have no LAPS password stored (ms-Mcs-AdmPwd empty).
.DESCRIPTION
    Enumerates enabled computer objects (excluding clusters, Hyper-V hosts, DCs and other
    exceptions), checks the legacy LAPS attribute ms-Mcs-AdmPwd, writes the hostnames without a
    LAPS password to a CSV, emails it through an anonymous internal SMTP relay and deletes the file.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | read permission on ms-Mcs-AdmPwd
    Impact      : Read-only (sends an email)
    License     : MIT
.EXAMPLE
    .\Get-NonLAPSComputers.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$OutputPath = "C:\Scripts\Reports\hostwithoutlaps.csv"
$From       = "alerts@contoso.com"
$To         = "it-support@contoso.com"
$SMTPServer = "smtp.contoso.com"
$SMTPPort   = "25"
# -------------------------------------------------------------------------

$Array = [System.Collections.ArrayList]@()
$computers = Get-ADComputer -Filter {Enabled -eq $true -and Name -notlike '*kiosk*' -and Name -notlike '*cluster*' -and Name -notlike '*hyperv*' -and Name -notlike '*-DC*' -and Name -notlike 'SRV-AADC01' -and Name -notlike 'SRV-NAS01' -and Name -notlike 'ILO*' -and Name -notlike 'SRV-LEGACY01' -and Name -notlike 'SRV-LEGACY02'} -Properties Name | Select-Object -ExpandProperty Name
foreach ($computer in $computers) {
    $laps = Get-ADComputer -Identity $computer -Properties ms-Mcs-AdmPwd | Select-Object -ExpandProperty ms-Mcs-AdmPwd
    if ($laps -eq $null) {
                            $arrayID = $Array.Add((Get-ADComputer -Identity $computer).name)

    }
}
$Array > $OutputPath

## Export the result to the support team via email ##

$Subject = "Weekly LAPS report"
$Body = "The attached file contains the endpoint that not integrated yet to LAPS"
$Attachment = $OutputPath
$Cred = [System.Management.Automation.PSCredential]::new( 'NT AUTHORITY\ANONYMOUS LOGON', [System.Security.SecureString]::New() )
Send-MailMessage -From $From -to $To -Subject $Subject -Body $Body -SmtpServer $SMTPServer -port $SMTPPort -Attachments $Attachment -Credential $Cred -Verbose


Remove-Item $OutputPath -Force
