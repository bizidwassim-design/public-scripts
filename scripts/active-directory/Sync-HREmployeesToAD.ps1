<#
.SYNOPSIS
    Fuzzy-matches employees from an HR CSV export to AD users and updates employeeID, employeeNumber and Title.
.DESCRIPTION
    Loads the HR CSV (first name, last name, employee number, badge/card number, position),
    normalises accents, matches each employee to an AD user by first name then last name with a
    Levenshtein-based similarity score (generic/service accounts skipped), compares job titles
    and, when -UpdateAD $true, writes employeeID (badge), employeeNumber and Title to AD.
    Always exports a match/update report CSV. Default is preview mode.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module (RSAT) | write permission on user attributes
    Impact      : Modifies AD (employeeID, employeeNumber, Title) when -UpdateAD $true; read-only otherwise
    License     : MIT
.EXAMPLE
    .\Sync-HREmployeesToAD.ps1
    # Runs in preview mode - no AD changes

.EXAMPLE
    .\Sync-HREmployeesToAD.ps1 -UpdateAD $true
    # Actually updates AD attributes
#>

<#
.PARAMETER InputFile
    Path to the input CSV file. Default: C:\Scripts\Input\employees.csv

.PARAMETER OutputFile
    Path to the output CSV file. Default: C:\Scripts\Reports\employees_matched.csv

.PARAMETER Delimiter
    CSV delimiter character. Default: semicolon (;)

.PARAMETER FuzzyThreshold
    Minimum similarity percentage for fuzzy matching (0-100). Default: 70

.PARAMETER UpdateAD
    If $true, actually updates AD. If $false, runs in preview/report mode. Default: $false
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$InputFile = "C:\Scripts\Input\employees.csv",

    [Parameter()]
    [string]$OutputFile = "C:\Scripts\Reports\employees_matched.csv",

    [Parameter()]
    [string]$Delimiter = ';',

    [Parameter()]
    [int]$FuzzyThreshold = 70,

    [Parameter()]
    [bool]$UpdateAD = $false
)

# ---- EDIT ME ------------------------------------------------------------
# Column names in the HR CSV export (adapt to your HR system)
$ColFirstName      = 'FirstName'        # -> matched against GivenName
$ColLastName       = 'LastName'         # -> matched against Surname
$ColEmployeeNumber = 'EmployeeNumber'   # -> employeeNumber (HR number)
$ColBadge          = 'BadgeNumber'      # -> employeeID (physical access card)
$ColPosition       = 'Position'         # -> Title (code prefix removed)
# Extra columns copied as-is into the report (optional, leave empty strings if absent)
$ColStatus         = 'Status'
$ColCompany        = 'Company'
$ColSite           = 'Site'
$ColSupervisor     = 'Supervisor'
# Position code prefix to strip, e.g. "02-022, Electromecanicien" -> "Electromecanicien"
$PositionCodeRegex = '^\d{2}-\d{2,3},\s*'
# -------------------------------------------------------------------------

#region Functions

function Get-LevenshteinDistance {
    param(
        [string]$String1,
        [string]$String2
    )

    $s1 = $String1.ToLower()
    $s2 = $String2.ToLower()

    $len1 = $s1.Length
    $len2 = $s2.Length

    if ($len1 -eq 0) { return $len2 }
    if ($len2 -eq 0) { return $len1 }

    $matrix = New-Object 'System.Collections.Generic.List[System.Collections.Generic.List[int]]'
    for ($i = 0; $i -le $len1; $i++) {
        $row = New-Object 'System.Collections.Generic.List[int]'
        for ($j = 0; $j -le $len2; $j++) {
            $row.Add(0)
        }
        $matrix.Add($row)
    }

    for ($i = 0; $i -le $len1; $i++) { $matrix[$i][0] = $i }
    for ($j = 0; $j -le $len2; $j++) { $matrix[0][$j] = $j }

    for ($i = 1; $i -le $len1; $i++) {
        for ($j = 1; $j -le $len2; $j++) {
            $cost = if ($s1[$i - 1] -eq $s2[$j - 1]) { 0 } else { 1 }

            $deletion = $matrix[$i - 1][$j] + 1
            $insertion = $matrix[$i][$j - 1] + 1
            $substitution = $matrix[$i - 1][$j - 1] + $cost

            $minVal = $deletion
            if ($insertion -lt $minVal) { $minVal = $insertion }
            if ($substitution -lt $minVal) { $minVal = $substitution }

            $matrix[$i][$j] = $minVal
        }
    }

    return $matrix[$len1][$len2]
}

function Get-StringSimilarity {
    param(
        [string]$String1,
        [string]$String2
    )

    if ([string]::IsNullOrWhiteSpace($String1) -or [string]::IsNullOrWhiteSpace($String2)) {
        return 0
    }

    $distance = Get-LevenshteinDistance -String1 $String1 -String2 $String2
    $maxLength = [Math]::Max($String1.Length, $String2.Length)

    if ($maxLength -eq 0) { return 100 }

    $similarity = (1 - ($distance / $maxLength)) * 100
    return [Math]::Round($similarity, 2)
}

function Get-NormalizedName {
    param(
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }

    $normalized = $Name.Normalize([System.Text.NormalizationForm]::FormD)
    $chars = $normalized.ToCharArray() | Where-Object {
        [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark
    }
    $result = -join $chars
    $result = $result -replace '\s+', ' '
    $result = $result.Trim()

    return $result
}

function Test-IsGenericAccount {
    param(
        [object]$ADUser
    )

    $genericPatterns = @(
        '^admin',
        '^service',
        '^svc',
        '^test',
        '^user\d',
        '^compte',
        '^generic',
        '^shared',
        '^template',
        '^default',
        '^system',
        '^backup',
        '^scan',
        '^printer',
        '^fax',
        '^conference',
        '^salle',
        '^room'
    )

    $samAccount = $ADUser.SamAccountName.ToLower()
    $displayName = if ($ADUser.DisplayName) { $ADUser.DisplayName.ToLower() } else { "" }
    $givenName = if ($ADUser.GivenName) { $ADUser.GivenName.ToLower() } else { "" }

    foreach ($pattern in $genericPatterns) {
        if ($samAccount -match $pattern -or $displayName -match $pattern -or $givenName -match $pattern) {
            return $true
        }
    }

    if ([string]::IsNullOrWhiteSpace($ADUser.Surname) -and [string]::IsNullOrWhiteSpace($ADUser.GivenName)) {
        return $true
    }

    return $false
}

function Get-TitleFromPosition {
    <#
    .SYNOPSIS
        Extracts the job title from Position field, removing the code prefix.
        Preserves French characters (é, è, ê, ç, etc.)
        Example: "02-022, Électromécanicien junior" -> "Électromécanicien junior"
    #>
    param(
        [string]$Position
    )

    if ([string]::IsNullOrWhiteSpace($Position)) { return "" }

    # Remove code prefix (pattern: XX-XXX, or XX-XX, at the beginning)
    $cleaned = $Position -replace $PositionCodeRegex, ''

    return $cleaned.Trim()
}

function Compare-JobTitles {
    param(
        [string]$CsvTitle,
        [string]$AdTitle
    )

    if ([string]::IsNullOrWhiteSpace($CsvTitle) -and [string]::IsNullOrWhiteSpace($AdTitle)) {
        return @{ Status = "N/A"; Score = 0 }
    }
    if ([string]::IsNullOrWhiteSpace($CsvTitle) -or [string]::IsNullOrWhiteSpace($AdTitle)) {
        return @{ Status = "No"; Score = 0 }
    }

    $csvNorm = (Get-NormalizedName -Name $CsvTitle).ToLower()
    $adNorm = (Get-NormalizedName -Name $AdTitle).ToLower()

    if ($csvNorm -eq $adNorm) {
        return @{ Status = "Yes"; Score = 100 }
    }

    if ($csvNorm.Contains($adNorm) -or $adNorm.Contains($csvNorm)) {
        return @{ Status = "Partial"; Score = 90 }
    }

    $similarity = Get-StringSimilarity -String1 $csvNorm -String2 $adNorm

    if ($similarity -ge 85) {
        return @{ Status = "Yes"; Score = $similarity }
    }
    elseif ($similarity -ge 60) {
        return @{ Status = "Partial"; Score = $similarity }
    }
    else {
        return @{ Status = "No"; Score = $similarity }
    }
}

function Test-FirstNameMatch {
    param(
        [string]$CsvFirstName,
        [string]$AdFirstName
    )

    if ([string]::IsNullOrWhiteSpace($CsvFirstName) -or [string]::IsNullOrWhiteSpace($AdFirstName)) {
        return @{ Match = $false; Score = 0 }
    }

    $csvNorm = (Get-NormalizedName -Name $CsvFirstName).ToLower()
    $adNorm = (Get-NormalizedName -Name $AdFirstName).ToLower()

    if ($csvNorm -eq $adNorm) {
        return @{ Match = $true; Score = 100 }
    }

    if ($csvNorm.Contains($adNorm) -or $adNorm.Contains($csvNorm)) {
        return @{ Match = $true; Score = 95 }
    }

    $csvWords = $csvNorm -split '\s+' | Where-Object { $_.Length -ge 2 }
    $adWords = $adNorm -split '\s+' | Where-Object { $_.Length -ge 2 }

    if ($csvWords.Count -gt 0 -and $adWords.Count -gt 0) {
        if ($csvWords[0] -eq $adWords[0]) {
            return @{ Match = $true; Score = 90 }
        }

        foreach ($cw in $csvWords) {
            foreach ($aw in $adWords) {
                if ($cw -eq $aw -and $cw.Length -ge 3) {
                    return @{ Match = $true; Score = 85 }
                }
            }
        }

        $firstWordSimilarity = Get-StringSimilarity -String1 $csvWords[0] -String2 $adWords[0]
        $fullSimilarity = Get-StringSimilarity -String1 $csvNorm -String2 $adNorm

        $bestSimilarity = [Math]::Max($firstWordSimilarity, $fullSimilarity)

        if ($bestSimilarity -ge 80) {
            return @{ Match = $true; Score = $bestSimilarity }
        }

        return @{ Match = $false; Score = $bestSimilarity }
    }

    return @{ Match = $false; Score = 0 }
}

function Get-LastNameMatchScore {
    param(
        [string]$CsvLastName,
        [string]$AdLastName
    )

    if ([string]::IsNullOrWhiteSpace($CsvLastName) -or [string]::IsNullOrWhiteSpace($AdLastName)) {
        return 0
    }

    $csvNorm = (Get-NormalizedName -Name $CsvLastName).ToLower()
    $adNorm = (Get-NormalizedName -Name $AdLastName).ToLower()

    if ($csvNorm -eq $adNorm) {
        return 100
    }

    if ($csvNorm.Contains($adNorm) -or $adNorm.Contains($csvNorm)) {
        return 95
    }

    $csvWords = $csvNorm -split '\s+' | Where-Object { $_.Length -ge 2 }
    $adWords = $adNorm -split '\s+' | Where-Object { $_.Length -ge 2 }

    $matchedWords = 0
    $totalWords = [Math]::Max($csvWords.Count, $adWords.Count)

    foreach ($cw in $csvWords) {
        foreach ($aw in $adWords) {
            if ($cw -eq $aw) {
                $matchedWords++
                break
            }
        }
    }

    if ($totalWords -gt 0 -and $matchedWords -gt 0) {
        if ($matchedWords -eq $totalWords) {
            return 95
        }
        elseif ($matchedWords -ge 1) {
            return 80 + (($matchedWords / $totalWords) * 15)
        }
    }

    return Get-StringSimilarity -String1 $csvNorm -String2 $adNorm
}

function Find-ADUserByFirstNameThenLastName {
    param(
        [string]$FirstName,
        [string]$LastName,
        [array]$ADUsers,
        [int]$Threshold
    )

    $csvFirstName = Get-NormalizedName -Name $FirstName
    $csvLastName = Get-NormalizedName -Name $LastName

    $firstNameMatches = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($adUser in $ADUsers) {
        if (Test-IsGenericAccount -ADUser $adUser) {
            continue
        }

        $adFirstName = $adUser.GivenName
        $adLastName = $adUser.Surname

        $firstNameResult = Test-FirstNameMatch -CsvFirstName $csvFirstName -AdFirstName $adFirstName

        if ($firstNameResult.Match) {
            $firstNameMatches.Add([PSCustomObject]@{
                User = $adUser
                FirstNameScore = $firstNameResult.Score
                ADFirstName = $adFirstName
                ADLastName = $adLastName
            })
        }
    }

    if ($firstNameMatches.Count -eq 0) {
        return $null
    }

    if ($firstNameMatches.Count -eq 1) {
        $candidate = $firstNameMatches[0]
        $lastNameScore = Get-LastNameMatchScore -CsvLastName $csvLastName -AdLastName $candidate.ADLastName

        $combinedScore = ($candidate.FirstNameScore * 0.4) + ($lastNameScore * 0.6)

        if ($combinedScore -ge $Threshold) {
            $matchType = if ($combinedScore -ge 95) { "Exact" }
                        elseif ($combinedScore -ge 85) { "High" }
                        elseif ($combinedScore -ge 75) { "Medium" }
                        else { "Low" }

            return @{
                User = $candidate.User
                Score = $combinedScore
                MatchType = $matchType
                FirstNameScore = $candidate.FirstNameScore
                LastNameScore = $lastNameScore
            }
        }
        return $null
    }

    $bestMatch = $null
    $bestScore = 0
    $bestMatchType = "None"
    $bestFirstNameScore = 0
    $bestLastNameScore = 0

    foreach ($candidate in $firstNameMatches) {
        $lastNameScore = Get-LastNameMatchScore -CsvLastName $csvLastName -AdLastName $candidate.ADLastName

        $combinedScore = ($candidate.FirstNameScore * 0.3) + ($lastNameScore * 0.7)

        if ($combinedScore -gt $bestScore -and $combinedScore -ge $Threshold) {
            $bestScore = $combinedScore
            $bestMatch = $candidate.User
            $bestFirstNameScore = $candidate.FirstNameScore
            $bestLastNameScore = $lastNameScore

            $bestMatchType = if ($combinedScore -ge 95) { "Exact" }
                            elseif ($combinedScore -ge 85) { "High" }
                            elseif ($combinedScore -ge 75) { "Medium" }
                            else { "Low" }
        }
    }

    if ($bestMatch) {
        return @{
            User = $bestMatch
            Score = $bestScore
            MatchType = $bestMatchType
            FirstNameScore = $bestFirstNameScore
            LastNameScore = $bestLastNameScore
            CandidatesCount = $firstNameMatches.Count
        }
    }

    return $null
}

function Update-ADUserAttributes {
    <#
    .SYNOPSIS
        Updates AD user attributes: employeeID, employeeNumber, and Title
        Properly handles French characters (é, è, ê, ç, etc.) in Title field
    #>
    param(
        [string]$SamAccountName,
        [string]$EmployeeID,      # From badge/card number
        [string]$EmployeeNumber,  # From HR employee number
        [string]$Title            # From Position (without code) - supports French characters
    )

    $changes = @()

    try {
        # Get the AD user object
        $adUser = Get-ADUser -Identity $SamAccountName -Properties EmployeeID, EmployeeNumber, Title

        # Update employeeID (badge)
        if (-not [string]::IsNullOrWhiteSpace($EmployeeID) -and $EmployeeID -ne "0") {
            Set-ADUser -Identity $SamAccountName -EmployeeID $EmployeeID -ErrorAction Stop
            $changes += "employeeID: $EmployeeID"
        }

        # Update employeeNumber (HR number)
        if (-not [string]::IsNullOrWhiteSpace($EmployeeNumber)) {
            Set-ADUser -Identity $SamAccountName -EmployeeNumber $EmployeeNumber -ErrorAction Stop
            $changes += "employeeNumber: $EmployeeNumber"
        }

        # Update Title (Position without code) - French characters are preserved
        if (-not [string]::IsNullOrWhiteSpace($Title)) {
            # Use Replace parameter to ensure proper Unicode handling
            Set-ADUser -Identity $SamAccountName -Replace @{Title = $Title} -ErrorAction Stop
            $changes += "Title: $Title"
        }

        if ($changes.Count -eq 0) {
            return @{
                Success = $false
                Message = "No attributes to update"
                Changes = @()
            }
        }

        return @{
            Success = $true
            Message = "Updated $SamAccountName"
            Changes = $changes
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Error updating $SamAccountName : $($_.Exception.Message)"
            Changes = @()
        }
    }
}

#endregion Functions

#region Main Script

try {
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Employee to AD Matching & Update Script" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    if ($UpdateAD -eq $true) {
        Write-Host "MODE: " -NoNewline -ForegroundColor Yellow
        Write-Host "UPDATE AD" -ForegroundColor Red
        Write-Host "  - $ColBadge -> employeeID" -ForegroundColor Gray
        Write-Host "  - $ColEmployeeNumber -> employeeNumber" -ForegroundColor Gray
        Write-Host "  - $ColPosition -> Title (French supported)" -ForegroundColor Gray
    }
    else {
        Write-Host "MODE: " -NoNewline -ForegroundColor Yellow
        Write-Host "PREVIEW ONLY (use -UpdateAD `$true to apply changes)" -ForegroundColor Green
    }
    Write-Host ""

    # Check for Active Directory module
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "Active Directory PowerShell module is not installed. Please install RSAT tools."
    }

    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "[OK] Active Directory module loaded" -ForegroundColor Green

    # Check input file
    if (-not (Test-Path -Path $InputFile)) {
        throw "Input file not found: $InputFile"
    }
    Write-Host "[OK] Input file found: $InputFile" -ForegroundColor Green

    # Read CSV file with multiple encoding attempts
    Write-Host ""
    Write-Host "Reading CSV file..." -ForegroundColor Yellow

    $employees = $null

    # Try different encodings
    $encodings = @('UTF8', 'Default', 'Unicode')

    foreach ($encoding in $encodings) {
        try {
            $testRead = Import-Csv -Path $InputFile -Delimiter $Delimiter -Encoding $encoding
            if ($testRead -and $testRead.Count -gt 0) {
                $employees = $testRead
                Write-Host "[OK] CSV loaded with encoding: $encoding" -ForegroundColor Green
                break
            }
        }
        catch {
            continue
        }
    }

    # If still not loaded, try reading raw content
    if (-not $employees -or $employees.Count -eq 0) {
        Write-Host "[INFO] Trying alternative CSV reading method..." -ForegroundColor Yellow
        $rawContent = Get-Content -Path $InputFile -Raw -Encoding UTF8
        $employees = $rawContent | ConvertFrom-Csv -Delimiter $Delimiter
    }

    if (-not $employees -or $employees.Count -eq 0) {
        throw "Failed to load CSV file or file is empty. Please check the file format and encoding."
    }

    $totalEmployees = @($employees).Count
    Write-Host "[OK] Loaded $totalEmployees employees from CSV" -ForegroundColor Green

    # Verify French characters
    $samplePosition = $employees[0].$ColPosition
    Write-Host "[INFO] Sample Position: $samplePosition" -ForegroundColor Gray

    # Display detected columns
    Write-Host ""
    Write-Host "Detected columns:" -ForegroundColor Yellow
    $columns = $employees[0].PSObject.Properties.Name
    $columns | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }

    # Get all AD users
    Write-Host ""
    Write-Host "Loading Active Directory users..." -ForegroundColor Yellow
    $adUsers = Get-ADUser -Filter * -Properties GivenName, Surname, Title, EmployeeID, EmployeeNumber, DisplayName, Department, Mail
    $totalADUsers = @($adUsers).Count
    Write-Host "[OK] Loaded $totalADUsers AD users" -ForegroundColor Green

    # Process each employee
    Write-Host ""
    Write-Host "Processing employees..." -ForegroundColor Yellow
    Write-Host ""

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $matchedCount = 0
    $notMatchedCount = 0
    $updatedCount = 0
    $updateErrorCount = 0
    $titleMismatchCount = 0
    $counter = 0

    foreach ($employee in $employees) {
        $counter++

        # Safe percentage calculation
        if ($totalEmployees -gt 0) {
            $percentComplete = [Math]::Round(($counter / $totalEmployees) * 100, 0)
        }
        else {
            $percentComplete = 0
        }

        # Get employee info from CSV
        $csvFirstName = $employee.$ColFirstName
        $csvLastName = $employee.$ColLastName
        $csvNumero = $employee.$ColEmployeeNumber
        $csvCarte = $employee.$ColBadge
        $csvPosition = $employee.$ColPosition

        # Extract job title from Position (remove code prefix)
        $csvJobTitle = Get-TitleFromPosition -Position $csvPosition

        Write-Progress -Activity "Matching employees to AD" -Status "Processing: $csvFirstName $csvLastName ($counter/$totalEmployees)" -PercentComplete $percentComplete

        # Find matching AD user
        $match = Find-ADUserByFirstNameThenLastName -FirstName $csvFirstName -LastName $csvLastName -ADUsers $adUsers -Threshold $FuzzyThreshold

        # Create result object
        $result = [PSCustomObject]@{
            'EmployeeNumber'      = $csvNumero
            'BadgeNumber'         = $csvCarte
            'FirstName'           = $csvFirstName
            'LastName'            = $csvLastName
            'Position'            = $csvPosition
            'Position_Title'      = $csvJobTitle
            'Status'              = $employee.$ColStatus
            'Company'             = $employee.$ColCompany
            'Site'                = $employee.$ColSite
            'Supervisor'          = $employee.$ColSupervisor
            'AD_SamAccountName'   = ""
            'AD_GivenName'        = ""
            'AD_Surname'          = ""
            'AD_DisplayName'      = ""
            'AD_Title'            = ""
            'AD_EmployeeID'       = ""
            'AD_EmployeeNumber'   = ""
            'AD_Email'            = ""
            'AD_Department'       = ""
            'Match_Type'          = "NOT FOUND"
            'Match_Score'         = 0
            'Title_Match'         = "N/A"
            'Title_Score'         = 0
            'AD_Update_Status'    = "N/A"
            'AD_Update_Details'   = ""
        }

        if ($match) {
            $adUser = $match.User
            $adTitle = $adUser.Title

            $result.AD_SamAccountName = $adUser.SamAccountName
            $result.AD_GivenName = $adUser.GivenName
            $result.AD_Surname = $adUser.Surname
            $result.AD_DisplayName = $adUser.DisplayName
            $result.AD_Title = $adTitle
            $result.AD_EmployeeID = $adUser.EmployeeID
            $result.AD_EmployeeNumber = $adUser.EmployeeNumber
            $result.AD_Email = $adUser.Mail
            $result.AD_Department = $adUser.Department
            $result.Match_Type = $match.MatchType
            $result.Match_Score = [Math]::Round($match.Score, 2)

            # Compare job titles
            $titleComparison = Compare-JobTitles -CsvTitle $csvJobTitle -AdTitle $adTitle
            $result.Title_Match = $titleComparison.Status
            $result.Title_Score = [Math]::Round($titleComparison.Score, 2)

            if ($titleComparison.Status -eq "No") {
                $titleMismatchCount++
            }

            $matchedCount++

            # Update AD if requested
            if ($UpdateAD -eq $true) {
                $updateResult = Update-ADUserAttributes `
                    -SamAccountName $adUser.SamAccountName `
                    -EmployeeID $csvCarte `
                    -EmployeeNumber $csvNumero `
                    -Title $csvJobTitle

                if ($updateResult.Success) {
                    $result.AD_Update_Status = "Updated"
                    $result.AD_Update_Details = ($updateResult.Changes -join "; ")
                    $updatedCount++
                }
                else {
                    $result.AD_Update_Status = "Error"
                    $result.AD_Update_Details = $updateResult.Message
                    $updateErrorCount++
                }
            }
            else {
                $result.AD_Update_Status = "Preview"
                $result.AD_Update_Details = "employeeID=$csvCarte; employeeNumber=$csvNumero; Title=$csvJobTitle"
            }

            # Console output
            $color = switch ($match.MatchType) {
                "Exact"  { "Green" }
                "High"   { "Green" }
                "Medium" { "Yellow" }
                "Low"    { "Red" }
                default  { "White" }
            }

            Write-Host "  [$counter/$totalEmployees] " -NoNewline
            Write-Host "$csvFirstName $csvLastName" -NoNewline -ForegroundColor White
            Write-Host " -> " -NoNewline
            Write-Host "$($adUser.GivenName) $($adUser.Surname)" -NoNewline -ForegroundColor $color
            Write-Host " ($($match.MatchType))" -NoNewline -ForegroundColor $color

            if ($UpdateAD -eq $true) {
                if ($updateResult.Success) {
                    Write-Host " [UPDATED]" -ForegroundColor Green
                }
                else {
                    Write-Host " [ERROR]" -ForegroundColor Red
                }
            }
            else {
                Write-Host " [Preview]" -ForegroundColor Cyan
            }
        }
        else {
            $notMatchedCount++
            Write-Host "  [$counter/$totalEmployees] " -NoNewline
            Write-Host "$csvFirstName $csvLastName" -NoNewline -ForegroundColor White
            Write-Host " -> " -NoNewline
            Write-Host "NOT FOUND" -ForegroundColor Red
        }

        $results.Add($result)
    }

    Write-Progress -Activity "Matching employees to AD" -Completed

    # Export results
    Write-Host ""
    Write-Host "Exporting results..." -ForegroundColor Yellow

    $utf8WithBom = New-Object System.Text.UTF8Encoding $true
    $csvContent = ($results | ConvertTo-Csv -Delimiter $Delimiter -NoTypeInformation) -join "`r`n"
    [System.IO.File]::WriteAllText($OutputFile, $csvContent, $utf8WithBom)

    Write-Host "[OK] Results exported to: $OutputFile" -ForegroundColor Green

    # Summary
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  SUMMARY" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Total employees processed: $totalEmployees" -ForegroundColor White
    Write-Host "  Matched:                   $matchedCount" -ForegroundColor Green
    Write-Host "  Not matched:               $notMatchedCount" -ForegroundColor Red

    if ($totalEmployees -gt 0) {
        Write-Host "  Match rate:                $([Math]::Round(($matchedCount / $totalEmployees) * 100, 1))%" -ForegroundColor Yellow
    }
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    # AD Update Summary
    if ($UpdateAD -eq $true) {
        Write-Host "AD UPDATE SUMMARY:" -ForegroundColor Cyan
        Write-Host "  Successfully updated: $updatedCount" -ForegroundColor Green
        Write-Host "  Errors:               $updateErrorCount" -ForegroundColor Red
        Write-Host ""
    }
    else {
        Write-Host "AD UPDATE PREVIEW:" -ForegroundColor Cyan
        Write-Host "  Would update: $matchedCount users" -ForegroundColor Yellow
        Write-Host "  Run with -UpdateAD `$true to apply changes" -ForegroundColor Yellow
        Write-Host ""
    }

    # Name Match Quality
    $exactMatches = @($results | Where-Object { $_.Match_Type -eq "Exact" }).Count
    $highMatches = @($results | Where-Object { $_.Match_Type -eq "High" }).Count
    $mediumMatches = @($results | Where-Object { $_.Match_Type -eq "Medium" }).Count
    $lowMatches = @($results | Where-Object { $_.Match_Type -eq "Low" }).Count

    Write-Host "Name Match Quality:" -ForegroundColor Cyan
    Write-Host "  Exact:   $exactMatches" -ForegroundColor Green
    Write-Host "  High:    $highMatches" -ForegroundColor Green
    Write-Host "  Medium:  $mediumMatches" -ForegroundColor Yellow
    Write-Host "  Low:     $lowMatches" -ForegroundColor Red
    Write-Host ""

    # Title Comparison
    $titleYes = @($results | Where-Object { $_.Title_Match -eq "Yes" }).Count
    $titlePartial = @($results | Where-Object { $_.Title_Match -eq "Partial" }).Count
    $titleNo = @($results | Where-Object { $_.Title_Match -eq "No" }).Count

    Write-Host "Job Title Comparison (Before Update):" -ForegroundColor Cyan
    Write-Host "  Matching:     $titleYes" -ForegroundColor Green
    Write-Host "  Partial:      $titlePartial" -ForegroundColor Yellow
    Write-Host "  Not Matching: $titleNo" -ForegroundColor Red
    Write-Host ""

    # Not Found List
    if ($notMatchedCount -gt 0) {
        Write-Host "============================================" -ForegroundColor Red
        Write-Host "  EMPLOYEES NOT FOUND IN AD ($notMatchedCount total)" -ForegroundColor Red
        Write-Host "============================================" -ForegroundColor Red
        $notFoundList = @($results | Where-Object { $_.Match_Type -eq "NOT FOUND" }) | Select-Object -First 30
        $notFoundList | ForEach-Object {
            Write-Host "  - $($_.FirstName) $($_.LastName) (EmployeeNumber: $($_.EmployeeNumber))" -ForegroundColor Yellow
        }
        if ($notMatchedCount -gt 30) {
            Write-Host "  ... and $($notMatchedCount - 30) more" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    Write-Host "Script completed successfully!" -ForegroundColor Green

    if ($UpdateAD -ne $true) {
        Write-Host ""
        Write-Host "NOTE: This was a preview run. To actually update AD, run:" -ForegroundColor Yellow
        Write-Host "  .\Sync-HREmployeesToAD.ps1 -UpdateAD `$true" -ForegroundColor Cyan
    }
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "Details: $($_.Exception)" -ForegroundColor Red
    exit 1
}
start $OutputFile
#endregion Main Script
