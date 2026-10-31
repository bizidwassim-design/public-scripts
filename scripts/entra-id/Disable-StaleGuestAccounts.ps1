<#
.SYNOPSIS
    Disables Entra ID guest (B2B) accounts with no sign-in activity for more than N days (default 180).
.DESCRIPTION
    Connects to Graph with an app registration + certificate, lists enabled guests with their
    signInActivity, flags those whose last sign-in (or creation date if never signed in) is older
    than the threshold, and disables them when -Apply is passed. Writes an Excel audit log.
    Without -Apply the script only previews. Accounts are never deleted.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : Microsoft.Graph.Authentication, Microsoft.Graph.Users, ImportExcel | app registration with User.ReadWrite.All + AuditLog.Read.All | Entra ID P1/P2 (signInActivity)
    Impact      : Modifies Entra ID (sets accountEnabled=false on stale guests; reversible)
    License     : MIT
.EXAMPLE
    .\Disable-StaleGuestAccounts.ps1 -CertificatePath Cert:\CurrentUser\My\<THUMBPRINT> -MailTo security@contoso.com
    .\Disable-StaleGuestAccounts.ps1 -CertificatePath Cert:\CurrentUser\My\<THUMBPRINT> -MailTo security@contoso.com -Apply
#>

<#
=====================================================================
 Desactivation automatique des invites externes inactifs (6 mois)
 Gouvernance du cycle de vie des invites
---------------------------------------------------------------------
 OBJECTIF :
   Si un invite (Guest) n'a AUCUNE activite de connexion depuis plus
   de 180 jours (6 mois), son compte est DESACTIVE (accountEnabled=$false).
   -> Desactiver le compte coupe d'un coup TOUS ses acces
      (SharePoint, OneDrive, Teams) sans toucher les permissions
      fichier par fichier. Action REVERSIBLE (ideal consultants saisonniers).

 REGLE :
   - Activite < 180 j                -> on ne touche pas
   - Aucune activite >= 180 j         -> DESACTIVER
   - Jamais connecte ET cree > 180 j  -> DESACTIVER
   La SUPPRESSION n'est jamais faite par ce script (desactivation seulement).

 UTILISATION :
   1) Apercu (rien n'est modifie) :   .\Disable-StaleGuestAccounts.ps1
   2) Execution reelle :              .\Disable-StaleGuestAccounts.ps1 -Apply
   Prerequis : module Microsoft.Graph, roles delegues + licence Entra P1/P2
               (signInActivity), permissions User.ReadWrite.All + AuditLog.Read.All
=====================================================================
#>

param(
    [int] $InactiveDays = 180,          # seuil = 6 mois
    [switch] $Apply,                     # sans -Apply => mode APERCU

    [Parameter()]
    [string] $CertificatePath = $env:CERT_PATH,

    [Parameter()]
    [string] $MailTo = $env:MAILTO
)

# ---- EDIT ME ------------------------------------------------------------
$ClientId         = "<CLIENT-ID>"                                   # app registration (certificate auth)
$TenantId         = "<TENANT-ID>"
$WorkingDirectory = "C:\Scripts\Reports\Disable-StaleGuestAccounts"  # Excel audit log folder
# -------------------------------------------------------------------------

function Get-LocalCertificate {
    [CmdletBinding()]
    param(
        [Parameter( Mandatory )]
        [string] $CertificatePath
    )

    $NotFoundError = "Can't find '{0}'."
    $PrivateKeyError = "Can't read the private key of certificate '{0}'."

    $cert = $CertificatePath | dir

    if (-not $cert) {
        throw $NotFoundError -f $CertificatePath
    }
    if (-not $cert.HasPrivateKey) {
        throw $PrivateKeyError -f $CertificatePath
    }

    return $cert
}

$ErrorActionPreference = "Stop"

# Journal horodate (audit)
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ConnectParams = @{
    Certificate = Get-LocalCertificate $CertificatePath
    ClientId = $ClientId
    NoWelcome = $true
    TenantId = $TenantId
}
$ExcelParams = @{
    AutoSize = $true
    ClearSheet = $true
    FreezeTopRowFirstColumn = $true
    Path = Join-Path $WorkingDirectory "Invites-inactifs-$Stamp.xlsx"
    TableName = "InactiveGuests"
    TableStyle = "Light15"
    WorksheetName = "InactiveGuests"
}
$MgScopes = "User.ReadWrite.All", "AuditLog.Read.All"
$MgUserParams = @{
	All = $true
	Filter = "userType eq 'Guest' and accountEnabled eq true"
	Property = "Id,DisplayName,Mail,UserPrincipalName,CreatedDateTime,SignInActivity"
	ConsistencyLevel = "Eventual"
	CountVariable = "Total"
}
$Modules = "ImportExcel", "Microsoft.Graph.Authentication", "Microsoft.Graph.Users"

if (-not $CertificatePath) {
    throw "CertificatePath parameter is empty"
}
if (-not $MailTo) {
    throw "MailTo parameter is empty."
}
if (-not (Test-Path $WorkingDirectory)) {
    New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
}

Write-Verbose "Loading modules."
$Modules | Import-Module

Connect-MgGraph @ConnectParams -ErrorAction Stop
Write-Verbose "Connected to Graph."

$cutoff = (Get-Date).ToUniversalTime().AddDays(-$InactiveDays)
Write-Host "Seuil d'inactivite : $InactiveDays jours (avant le $($cutoff.ToString('yyyy-MM-dd')))" -ForegroundColor Cyan
Write-Host ("Mode : {0}" -f ($(if($Apply){"EXECUTION REELLE"}else{"APERCU (aucune modification)"}))) -ForegroundColor Yellow

# Recuperer les invites ACTIFS avec leur activite de connexion
$guests = Get-MgUser @MgUserParams

$log = @()
foreach ($g in $guests) {
    $sa = $g.SignInActivity
    $dates = @()
    if ($sa) {
        foreach ($p in @($sa.LastSignInDateTime,$sa.LastNonInteractiveSignInDateTime,$sa.LastSuccessfulSignInDateTime)) {
            if ($p) {
                $dates += [datetime]$p
            }
        }
    }
    $last = $null
    if ($dates.Count) {
        $last = ($dates | measure -Maximum).Maximum
    }

    # Reference d'inactivite : derniere connexion, sinon date de creation
    $ref = $null
    if ($last) {
        $ref = $last
    } elseif ($g.CreatedDateTime) {
        $ref = [datetime]$g.CreatedDateTime
    }

    if (-not $ref) {
        continue
    }

    if ($ref -lt $cutoff) {
        $days = [int] ((Get-Date).ToUniversalTime() - $ref).TotalDays
        $motif = "Jamais connecte (cree il y a $days j)"
        if ($last) {
            $motif = "Inactif $days j"
        }
        $log += [pscustomobject] @{
            Nom = $g.DisplayName
			Courriel = if ($g.Mail -ne $null) { $g.Mail } else { $g.UserPrincipalName }
            DerniereActivite = ($(if($last){$last.ToString('yyyy-MM-dd')}else{'JAMAIS'}))
            JoursInactif = $days
            Motif  = $motif
            Action = $(if($Apply){"DESACTIVE"}else{"A desactiver (apercu)"})
        }
        if ($Apply) {
            try {
                Update-MgUser -UserId $g.Id -AccountEnabled:$false
                Write-Host "  DESACTIVE : $($g.Mail)  ($motif)" -ForegroundColor Green
            } catch {
                Write-Warning "  ECHEC $($g.Mail) : $($_.Exception.Message)"
            }
        } else {
            Write-Host "  [apercu] $($g.Mail)  ($motif)" -ForegroundColor DarkYellow
        }
    }
}

Disconnect-MgGraph | Out-Null
Write-Verbose "Disconnected from Graph."

$log | Export-Excel @ExcelParams

Write-Host ""
Write-Host "Invites analyses : $($guests.Count)" -ForegroundColor Cyan
Write-Host "Invites concernes (>= $InactiveDays j) : $($log.Count)" -ForegroundColor Cyan
Write-Host "Journal : $($ExcelParams.Path)" -ForegroundColor Cyan

if (-not $Apply) {
    Write-Host "APERCU termine - relancer avec -Apply pour desactiver reellement." -ForegroundColor Yellow
}

<#
---------------------------------------------------------------------
 PLANIFICATION (executer chaque mois) :
   Option A - Azure Automation Runbook :
     - Creer un compte Automation + identite managee
     - Importer le module Microsoft.Graph.Authentication + Users
     - Coller ce script (retirer Connect-MgGraph certificat -> Connect-MgGraph -Identity)
     - Planning : mensuel
   Option B - Tache planifiee Windows sur un serveur d'admin :
     - pwsh.exe -File Disable-StaleGuestAccounts.ps1 -Apply
     - Declencheur mensuel

 ETAPE SUIVANTE (facultative) - suppression apres periode de grace :
   Un second script mensuel qui SUPPRIME les invites desactives depuis > 30 j
   sans demande de reactivation (Remove-MgUser). A valider separement.
---------------------------------------------------------------------
#>
