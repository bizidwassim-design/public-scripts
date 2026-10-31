<#
.SYNOPSIS
    Weekly audit of AD user accounts created / modified in the last 8 days, enriched with M365 licences.
.DESCRIPTION
    Pulls AD users whose whenCreated or whenChanged is within the last 8 days, looks up their
    Microsoft 365 licences (MSOnline), flags New / Recently Updated / Recently Disabled accounts and
    builds a per-user recommendation (tag for security-awareness training, move to Disabled OU,
    unassign licence...). Exports a CSV and emails it to the IT team with the recommendation count.
    Designed to run from Task Scheduler.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | MSOnline module | SMTP relay
    Impact      : Read-only (sends an email)
    License     : MIT
.EXAMPLE
    .\Report-WeeklyADUserAudit.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$LogPath        = "C:\Scripts\WeeklyAudit\log\script_log.txt"
$CsvFileName    = "C:\Scripts\WeeklyAudit\log\UserDetails.csv"
$username       = "svc-scheduler@contoso.com"      # MSOnline service account
$CredentialFile = "C:\Scripts\WeeklyAudit\msol.cred.xml"   # created once with: Get-Credential | Export-Clixml <file> (DPAPI, same user + host)
$smtpServer     = "smtp.contoso.com"
$from           = "it-support@contoso.com"
$emailaddress   = "it-support@contoso.com"
$Bcc            = "security@contoso.com"
$TenantPrefix   = "contoso"                         # licence SKU prefix, e.g. contoso:SPE_E5
$TrainingTag    = "CyberSecurityTraining"           # value stored in extensionAttribute1
# -------------------------------------------------------------------------

# Start transcript to log the script execution
Start-Transcript -Path $LogPath -Append -Force

# Ensure the script stops on any error
$ErrorActionPreference = "Continue"

# Connect to the Microsoft Online Service
$credential = if (Test-Path $CredentialFile) { Import-Clixml $CredentialFile } else { Get-Credential -UserName $username -Message "Microsoft 365 service account" }
Connect-MsolService -Credential $credential

$SkuF1 = "$($TenantPrefix):SPE_F1"
$SkuE5 = "$($TenantPrefix):SPE_E5"

# Define the cutoff date for user creation and modification (last 8 days)
$cutoffDate = (Get-Date).AddDays(-8)

# Get AD users created or modified in the last 8 days
$Users = Get-ADUser -Filter { whenCreated -gt $cutoffDate -or whenChanged -gt $cutoffDate } -Properties enabled, UserPrincipalName, extensionAttribute1, extensionAttribute2, extensionAttribute3, extensionAttribute4, extensionAttribute5, extensionAttribute6, extensionAttribute7, extensionAttribute8, extensionAttribute9, extensionAttribute10, extensionAttribute11, extensionAttribute12, extensionAttribute13, extensionAttribute14, extensionAttribute15, whenCreated, whenChanged, lastLogonTimestamp, DistinguishedName

# Initialize an array to hold the user details
$Results = @()

# Process each user
foreach ($user in $Users) {
    $userPrincipalName = $user.UserPrincipalName

    # Skip users without UserPrincipalName
    if (-not $userPrincipalName) {
        Write-Host "Skipping user: $($user.Name), no UserPrincipalName found"
        continue
    }

    Write-Host "Processing user: $($user.Name)"

    # Get Office 365 User and Licenses
    $Usr = Get-MsolUser -UserPrincipalName $userPrincipalName -ErrorAction SilentlyContinue
    if (-not $Usr) {
        $licenseInfo = "Not Found in Office 365"
    } elseif (-not $Usr.Licenses) {
        $licenseInfo = "No Licenses Assigned"
    } else {
        $licenseInfo = ($Usr.Licenses | ForEach-Object { $_.AccountSkuId }) -join ", "
    }

    # Determine if the account is new or recently updated
    $isNew = if (((Get-Date) - $user.WhenCreated).Days -le 7) { "New" } else { "Recently Updated" }

    # Check if the account was disabled recently (within the last 7 days)
    $isRecentlyDisabled = if (-not $user.Enabled -and ((Get-Date) - $user.whenChanged).Days -le 7) { "Recently Disabled" } else { "" }

    # Update the modified time and handle cases where no modifications occurred
    $modifiedTime = if ($user.whenCreated -eq $user.whenChanged) { "No Any Modification" } else { $user.whenChanged }

    $recommendation = ""
    if ($user.DistinguishedName -notmatch "Administrative") {
		if ($licenseInfo -like "No Licenses Assigned" -and $user.extensionAttribute1 -eq $TrainingTag){$recommendation = "Clear the extensionAttribute1"}
        if ($user.extensionAttribute1 -eq $TrainingTag -and ($licenseInfo -contains $SkuF1 -Or $licenseInfo -contains $SkuE5)) {
            # Do not add recommendation if already set
            $recommendation = ""
        } elseif ($user.Enabled -and ($licenseInfo -contains $SkuF1 -Or $licenseInfo -contains $SkuE5) -and ($user.extensionAttribute17 -ne "UserDontUseEmails") -and ($user.extensionAttribute1 -ne $TrainingTag)) {
            $recommendation = "Add extensionAttribute1=$TrainingTag"
            if ($user.extensionAttribute11 -like "ADonly" -OR $user.extensionAttribute12 -like "Generic") {
                $recommendation = "Add extensionAttribute1=$TrainingTag AND correct the other tag(s)"
            }
        } elseif (-not $user.Enabled -and $isRecentlyDisabled -ne "" -and $user.DistinguishedName -notlike "*disabled*" -and $licenseInfo -ne "Not Found in Office 365" -and $user.extensionAttribute15 -ne "ServiceAccount") {

            $recommendation = "Move the user account to Disabled OU and disable his computer object"

            if ($licenseInfo -like "*$SkuF1*" -Or $licenseInfo -like "*$SkuE5*")
            {
              $recommendation = "Move the user account to Disabled OU and unassign the licence"

              if ($user.extensionAttribute1 -like $TrainingTag)
              {$recommendation = "Move the user account to Disabled OU, unassign the licence and Clear the extensionAttribute1 "}
            }
        }
    } else {
		$recommendation = ""

    }

    # Construct the user details as an object
    $userDetails = [PSCustomObject]@{
        Recommendation         = $recommendation
        New                    = $isNew
        Name                   = $user.Name
        UserPrincipalName      = $userPrincipalName
        Enabled                = $user.Enabled
        OUPath                 = $user.DistinguishedName
        CreatedTime            = $user.WhenCreated
        ModifiedTime           = $modifiedTime
        Office365Licenses      = $licenseInfo
        extensionAttribute1    = $user.extensionAttribute1
        extensionAttribute2    = $user.extensionAttribute2
        extensionAttribute3    = $user.extensionAttribute3
        extensionAttribute4    = $user.extensionAttribute4
        extensionAttribute5    = $user.extensionAttribute5
        extensionAttribute6    = $user.extensionAttribute6
        extensionAttribute7    = $user.extensionAttribute7
        extensionAttribute8    = $user.extensionAttribute8
        extensionAttribute9    = $user.extensionAttribute9
        extensionAttribute10   = $user.extensionAttribute10
        extensionAttribute11   = $user.extensionAttribute11
        extensionAttribute12   = $user.extensionAttribute12
        extensionAttribute13   = $user.extensionAttribute13
        extensionAttribute14   = $user.extensionAttribute14
        extensionAttribute15   = $user.extensionAttribute15
    }

    # Add the user details to the results array
    $Results += $userDetails
}

# Sort the results so that 'New' users are first, followed by 'Disabled', then 'Recently Updated'
$SortedResults = $Results | Sort-Object -Property @{Expression = "New"; Descending = $true}

# Count the number of recommendations
$recommendationCount = ($Results | Where-Object { $_.Recommendation -ne "" }).Count

# Export the results to a CSV file
$SortedResults | Export-Csv -Path $CsvFileName -NoTypeInformation

# Start the CSV file
Start-Process -FilePath $CsvFileName

# Define the email details
$subject = "Weekly AD Audit Report"
$body = @"

   <p>Hello Team </p>

    <p>Attached, you will find the weekly audit report for Active Directory (AD).</p>

	<p>This report covers user account modifications over <strong>the past 7 days</strong>, including recently created and disabled accounts.</p>

    <p>Please note that the <strong>first column</strong> of the report highlights a total of <strong>$recommendationCount</strong> recommendations.</p>

	</p><strong>The second column</strong> provides details on the last modified user accounts, which includes recent changes to accounts.</p>

    <p>I kindly ask that you review these recommendations thoroughly and take the necessary actions to ensure compliance and security within our system.</p>

    <p>Thank you for your prompt attention to this matter.</p>

    <p>Best regards,<br>
    The Contoso Cybersecurity Team</p>

"@

# Attach the CSV report to the email
$attachment = $CsvFileName

# Send the email with the attachment
try {
    Send-MailMessage -smtpServer $smtpServer `
                     -from $from `
                     -to $emailaddress `
					 -Bcc $Bcc `
                     -subject $subject `
                     -body $body `
                     -bodyasHTML `
                     -priority High `
                     -Encoding ([System.Text.Encoding]::UTF8) `
                     -Attachment $attachment
    Write-Host "Email sent successfully."
} catch {
    Write-Host "Error sending the email: $_"
}

# Stop transcript
Stop-Transcript
