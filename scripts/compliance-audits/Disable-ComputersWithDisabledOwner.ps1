<#
.SYNOPSIS
    Monthly check: disable L-*/D-* workstations whose owner account is disabled, and flag OU mismatches.
.DESCRIPTION
    For every enabled workstation, reads the owner's display name from the computer Description,
    looks the user up in AD, compares the first OU of user and computer, and DISABLES the computer
    account when the owner is disabled. Exports a full CSV and always emails an HTML summary.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module | permission to disable computer objects
    Impact      : Modifies AD (disables computer accounts whose owner is disabled)
    License     : MIT
.EXAMPLE
    .\Disable-ComputersWithDisabledOwner.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$outputFilePath = "C:\Scripts\MonthlyDisabledDevice\ComputerDescriptions.csv"

# Define email settings
$smtpServer   = "smtp.contoso.com"
$from         = "it-support@contoso.com"
$emailaddress = "it-support@contoso.com"
$subject      = "Monthly check: disabled computer accounts based on their owner disabled accounts."
# -------------------------------------------------------------------------

$attachment = $outputFilePath

$results = @()
$dynamicArray = @()
$TNonSameOU = $NonSameOU = @()

$computerNames = Get-ADComputer -Filter {
    (Enabled -eq $true) -and ((Name -like "L-*") -or (Name -like "D-*"))
} | Select-Object -ExpandProperty Name

foreach ($computerName in $computerNames) {
    $computer = Get-ADComputer -Properties Name, Description, DistinguishedName -Filter {
        Name -eq $computerName
    }
    $Check = "FALSE"

    if ($computer) {
        # Set the full name of the user you want to find
        $fullName = $computer.Description

        if (!($fullName)) {
            $results += [PSCustomObject] @{
                ComputerName = $computer.Name
                Enabled = $computer.Enabled
                Description = "Description field empty"
                Path = $computer.DistinguishedName
                Owner = "owner not defined"
                Email = "owner not defined"
                OwnerLocation = "owner not defined"
                ComputerAndUserInTheSameLocation = $Check
            }

        }
        else {
            # Retrieve the user based on their full name
            #$user = Get-ADUser -Filter {Name -like $fullName} -Properties name, EmailAddress, DistinguishedName
            $user = Get-ADUser -Properties DisplayName, name, EmailAddress, DistinguishedName, Enabled -Filter {
                DisplayName -eq $fullName
            }

            # Check if the user was found and display their email address
            if ($user) {
                $Uname = $user.name
                $Uemail = $user.EmailAddress
                $Ulocation = $user.DistinguishedName

                # Extract the first OU value from each distinguished name
                $ouValue1 = ($user.DistinguishedName -split ",OU=")[1]
                $ouValue2 = ($computer.DistinguishedName -split ",OU=")[1]

                # Compare the first OU values
                if ($ouValue1 -eq $ouValue2) {
                    $Check = "True"
                }

                # Define an empty dynamic array
                if (!$user.Enabled) {
                    Disable-ADAccount -Identity $computer.DistinguishedName -Confirm:$false
                    Write-Host $computer.Name "This computer is disabled because the associated user account ["$user.name "] is already in a disabled state."-ForegroundColor yellow -BackgroundColor Black

                    # Add a phrase to the dynamic array
                    $dynamicArray += "$($computer.Name) This computer is disabled because the associated user account $($user.name) is already in a disabled state.<br>"
                }
            }
            else {
                $Uname = $Uemail = $Ulocation = $Check = "User not found in AD."
            }

            $results += [PSCustomObject] @{
                ComputerName = $computer.Name
                Enabled = $computer.Enabled
                Description = $computer.Description
                Path = $computer.DistinguishedName
                Owner = $Uname
                Email = $Uemail
                Active = $user.Enabled
                OwnerLocation = $Ulocation
                ComputerAndUserInTheSameLocation = $Check
            }
        }
    }
    else {
        $results += [PSCustomObject]@{
            ComputerName = $computerName
            Enabled = "Computer not found in AD"
            Description = "Computer not found in AD"
            Path = "Computer not found in AD"
            Owner = "Computer not found in AD"
            Email = "Computer not found in AD"
            OwnerLocation = "Computer not found in AD"
            ComputerAndUserInTheSameLocation = "Computer not found in AD"
        }
    }
}

$results | Export-Csv -Path $outputFilePath -NoTypeInformation -encoding utf8

$TNonSameOU = $results | ? {
    ($_.ComputerAndUserInTheSameLocation -eq "FALSE") -and ($_.OwnerLocation -notlike "owner not defined")
}

$NonSameOU = $TNonSameOU | ForEach-Object {
    "<tr><td>$($_.Owner)</td><td>$($_.'ComputerName')</td><td>$($_.OwnerLocation)</td><td>$($_.path)</td></tr>"
}

$NonSameOU = "<table border='1'><thead><tr><th>Owner</th><th>ComputerName</th><th>OwnerLocation</th><th>path</th></tr></thead><tbody>$($NonSameOU -join "`n")</tbody></table>"

# Build email body dynamically based on available data
$emailBody = @"
<font face="calibri">
Hello Team,
"@

# Check if there are any issues to report
if (($dynamicArray.count -gt 0) -or $TNonSameOU) {
    # Add disabled computers section only if there are any
    if ($dynamicArray.count -gt 0) {
        $emailBody += @"
<p>Please note that computers below were disabled:<br>
<h3>Disabled Computers in AD:</h3>
$dynamicArray
<br><br>
"@
    }

    # Add non-same OU section only if there are any
    if ($TNonSameOU) {
        $emailBody += @"
<p>List of user accounts that are not in the same OU as their corresponding computers:<br>
<h3>User and computer are not in the same OU path:</h3>
$NonSameOU
<br><br>
"@
    }

    # Add closing and attachment info
    $emailBody += @"
<p>In the attached file, you will find details of all active devices and their respective user owners.<br><br>
<p>Cordialement,<br><br>
<p>L'équipe de cybersécurité
</font>
"@
}
else {
    # No issues found - send notification email
    $emailBody += @"
<p>No changes were made during this monthly check.<br><br>
<p>All active computer accounts are correctly configured and their associated user accounts are enabled.<br><br>
<p>In the attached file, you will find details of all active devices and their respective user owners.<br><br>
<p>Cordialement,<br><br>
<p>L'équipe de cybersécurité
</font>
"@
}

# Always send email
try {
    Send-MailMessage -smtpServer $smtpServer `
        -from $from `
        -to $emailaddress `
        -subject $subject `
        -body $emailBody `
        -bodyasHTML `
        -priority High `
        -Encoding ([System.Text.Encoding]::UTF8) `
        -Attachment $attachment

    Write-Host "Email sent successfully." -ForegroundColor Green

    if (($dynamicArray.count -gt 0) -or $TNonSameOU) {
        Write-Host "  - Disabled computers: $($dynamicArray.count)" -ForegroundColor Cyan
        Write-Host "  - OU mismatches: $(@($TNonSameOU).count)" -ForegroundColor Cyan
    } else {
        Write-Host "  - No issues found" -ForegroundColor Green
    }
} catch {
    Write-Host "Error sending email: $_" -ForegroundColor Red
}
