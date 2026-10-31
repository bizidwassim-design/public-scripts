<#
.SYNOPSIS
    Sets the AD employeeID (physical access card number) from a CSV, matching users by first AND last name.
.DESCRIPTION
    Auto-detects the CSV delimiter and normalises column names (first name / last name / card),
    searches AD by first name then validates both names with accent-insensitive, typo-tolerant
    matching (compound names, inverted first/last supported), skips users whose employeeID is
    already correct, warns before overwriting, writes employeeID and exports a per-row report
    CSV plus a log. Supports -WhatIf.
    Convention: employeeNumber (AD) = HR employee number; employeeID (AD) = physical access card.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module (RSAT) | write permission on employeeID
    Impact      : Modifies AD (employeeID attribute); use -WhatIf to preview
    License     : MIT
.EXAMPLE
    .\Set-EmployeeIDFromCsv.ps1 -InputFile C:\Scripts\Input\badges.csv -WhatIf
#>

<#
.SYNOPSIS
    Lit un fichier CSV, recherche les utilisateurs dans AD par prénom ET nom,
    puis met à jour l'attribut employeeID avec le numéro de carte.

.PARAMETER InputFile
    Chemin vers le fichier CSV d'entrée

.PARAMETER SimilarityThreshold
    Seuil de similarité pour la correspondance des noms (0.0 à 1.0, défaut: 0.80 = 80%)

.PARAMETER WhatIf
    Mode simulation - affiche les changements sans les appliquer
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    # ---- EDIT ME (defaults) ------------------------------------------------
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$InputFile = "C:\Scripts\Input\badges.csv",

    [Parameter(Mandatory = $false)]
    [ValidateRange(0.0, 1.0)]
    [double]$SimilarityThreshold = 0.80,

    [Parameter(Mandatory = $false)]
    [string]$LogPath = ".\Set-EmployeeID_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    # -------------------------------------------------------------------------
)

#region Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        'ERROR'   { Write-Host $logEntry -ForegroundColor Red }
        'WARNING' { Write-Host $logEntry -ForegroundColor Yellow }
        'SUCCESS' { Write-Host $logEntry -ForegroundColor Green }
        default   { Write-Host $logEntry -ForegroundColor Cyan }
    }

    Add-Content -Path $LogPath -Value $logEntry -ErrorAction SilentlyContinue
}

function Normalize-String {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }

    # Convertir en minuscules et supprimer espaces début/fin
    $result = $Text.ToLower().Trim()

    # Remplacer les accents courants
    $result = $result -replace '[àáâãäå]', 'a'
    $result = $result -replace '[èéêë]', 'e'
    $result = $result -replace '[ìíîï]', 'i'
    $result = $result -replace '[òóôõö]', 'o'
    $result = $result -replace '[ùúûü]', 'u'
    $result = $result -replace '[ýÿ]', 'y'
    $result = $result -replace '[ñ]', 'n'
    $result = $result -replace '[ç]', 'c'

    # Supprimer les caractères non alphanumériques sauf espaces
    $result = $result -replace '[^a-z0-9 ]', ''

    return $result
}

function Test-NameMatch {
    <#
    .SYNOPSIS
        Vérifie si deux noms correspondent (exact ou similaire)
        Retourne: Match (bool), Similarity (0-1), IsExact (bool)
    #>
    param(
        [string]$Name1,
        [string]$Name2,
        [double]$Threshold
    )

    $n1 = Normalize-String -Text $Name1
    $n2 = Normalize-String -Text $Name2

    # Match exact
    if ($n1 -eq $n2) {
        return @{ Match = $true; Similarity = 1.0; IsExact = $true }
    }

    # Comparer sans espaces (pour "Ait Bouzid" vs "Ait-Bouzid")
    $n1NoSpace = $n1 -replace ' ', ''
    $n2NoSpace = $n2 -replace ' ', ''

    if ($n1NoSpace -eq $n2NoSpace) {
        return @{ Match = $true; Similarity = 1.0; IsExact = $true }
    }

    # Vérifier si l'un commence par l'autre (pour BOUZID vs BOUZIAD)
    if ($n1NoSpace.Length -ge 4 -and $n2NoSpace.Length -ge 4) {
        $shorter = if ($n1NoSpace.Length -le $n2NoSpace.Length) { $n1NoSpace } else { $n2NoSpace }
        $longer = if ($n1NoSpace.Length -gt $n2NoSpace.Length) { $n1NoSpace } else { $n2NoSpace }

        # Si le plus court est contenu dans le plus long
        if ($longer.Contains($shorter)) {
            $sim = [Math]::Round($shorter.Length / $longer.Length, 4)
            if ($sim -ge $Threshold) {
                return @{ Match = $true; Similarity = $sim; IsExact = $false }
            }
        }

        # Si ils commencent pareil (au moins 80% des caractères du plus court)
        $prefixLen = 0
        for ($i = 0; $i -lt $shorter.Length; $i++) {
            if ($i -lt $longer.Length -and $shorter[$i] -eq $longer[$i]) {
                $prefixLen++
            } else {
                break
            }
        }
        if ($prefixLen -ge ($shorter.Length * 0.8)) {
            $sim = [Math]::Round($prefixLen / $longer.Length, 4)
            if ($sim -ge ($Threshold - 0.1)) {  # Un peu plus flexible pour les préfixes
                return @{ Match = $true; Similarity = [Math]::Max($sim, $Threshold); IsExact = $false }
            }
        }
    }

    # Comparer caractère par caractère avec tolérance pour 1-2 erreurs
    $maxLen = [Math]::Max($n1NoSpace.Length, $n2NoSpace.Length)
    $minLen = [Math]::Min($n1NoSpace.Length, $n2NoSpace.Length)

    if ($maxLen -eq 0) { return @{ Match = $false; Similarity = 0; IsExact = $false } }

    # Si longueurs très différentes, pas de match
    if ($minLen -lt ($maxLen * 0.7)) {
        return @{ Match = $false; Similarity = 0; IsExact = $false }
    }

    # Compter caractères identiques à la même position
    $matchCount = 0
    for ($i = 0; $i -lt $minLen; $i++) {
        if ($n1NoSpace[$i] -eq $n2NoSpace[$i]) { $matchCount++ }
    }

    # Calculer similarité
    $similarity = [Math]::Round($matchCount / $maxLen, 4)

    # Bonus si les premiers caractères matchent (important pour les noms)
    $firstCharsMatch = ($n1NoSpace.Length -ge 3 -and $n2NoSpace.Length -ge 3 -and $n1NoSpace.Substring(0,3) -eq $n2NoSpace.Substring(0,3))
    if ($firstCharsMatch -and $similarity -ge ($Threshold - 0.1)) {
        $similarity = [Math]::Min(1.0, $similarity + 0.05)
    }

    return @{
        Match = ($similarity -ge $Threshold)
        Similarity = $similarity
        IsExact = $false
    }
}

function Test-NameMatchPartial {
    <#
    .SYNOPSIS
        Vérifie si un nom CSV est contenu dans un nom AD composé
        Ex: "Esparza" match "Esparza Garcia", "Christopher" match "Christopher Moises"
    #>
    param(
        [string]$SearchName,
        [string]$ADName,
        [double]$Threshold
    )

    $searchNorm = Normalize-String -Text $SearchName
    $adNorm = Normalize-String -Text $ADName

    # Séparer le nom AD en parties
    $adParts = $adNorm -split ' '

    # Vérifier si le nom recherché correspond à une des parties
    foreach ($part in $adParts) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }

        # Match exact avec une partie
        if ($searchNorm -eq $part) {
            return @{ Match = $true; Similarity = 0.95; IsExact = $false }
        }

        # Match partiel avec une partie (pour BOUZID vs BOUZIAD)
        $partMatch = Test-NameMatch -Name1 $searchNorm -Name2 $part -Threshold $Threshold
        if ($partMatch.Match) {
            return @{ Match = $true; Similarity = $partMatch.Similarity; IsExact = $false }
        }
    }

    # Vérifier si le nom recherché commence pareil que le nom AD
    $searchNoSpace = $searchNorm -replace ' ', ''
    $adNoSpace = $adNorm -replace ' ', ''

    if ($adNoSpace.StartsWith($searchNoSpace) -or $searchNoSpace.StartsWith($adNoSpace)) {
        $sim = [Math]::Min($searchNoSpace.Length, $adNoSpace.Length) / [Math]::Max($searchNoSpace.Length, $adNoSpace.Length)
        if ($sim -ge 0.6) {
            return @{ Match = $true; Similarity = [Math]::Max($sim, 0.85); IsExact = $false }
        }
    }

    return @{ Match = $false; Similarity = 0; IsExact = $false }
}

function Find-ADUserByName {
    <#
    .SYNOPSIS
        Recherche un utilisateur AD par prénom ET nom de famille
        Essaie aussi avec prénom/nom inversés si pas trouvé
    #>
    param(
        [string]$FirstName,
        [string]$LastName,
        [double]$Threshold
    )

    $searchFirstName = $FirstName.Trim()
    $searchLastName = $LastName.Trim()

    # Essayer d'abord dans l'ordre normal
    $match = Find-ADUserByNameInternal -SearchFirst $searchFirstName -SearchLast $searchLastName -Threshold $Threshold

    if ($match) {
        return $match
    }

    # Si pas trouvé, essayer avec prénom/nom inversés
    $matchInverted = Find-ADUserByNameInternal -SearchFirst $searchLastName -SearchLast $searchFirstName -Threshold $Threshold

    if ($matchInverted) {
        # Marquer que c'était inversé (pour le log)
        $matchInverted | Add-Member -NotePropertyName "WasInverted" -NotePropertyValue $true -Force
        return $matchInverted
    }

    return $null
}

function Find-ADUserByNameInternal {
    <#
    .SYNOPSIS
        Recherche interne - cherche un utilisateur AD par prénom ET nom
        Gère les noms composés (ex: "Esparza" match "Esparza Garcia")
    #>
    param(
        [string]$SearchFirst,
        [string]$SearchLast,
        [double]$Threshold
    )

    # Extraire le premier mot du prénom pour la recherche AD
    $firstNamePart = ($SearchFirst -split ' ')[0]

    # Rechercher par prénom dans AD
    try {
        $users = @(Get-ADUser -Filter "GivenName -like '$firstNamePart*'" -Properties GivenName, Surname, employeeID, SamAccountName, DisplayName, Enabled -ErrorAction Stop)

        # Si pas trouvé, essayer aussi par nom de famille (pour les cas inversés ou noms composés)
        if ($users.Count -eq 0) {
            $lastNamePart = ($SearchLast -split ' ')[0]
            $users = @(Get-ADUser -Filter "Surname -like '$lastNamePart*' -or GivenName -like '$lastNamePart*'" -Properties GivenName, Surname, employeeID, SamAccountName, DisplayName, Enabled -ErrorAction Stop)
        }
    }
    catch {
        return $null
    }

    if ($users.Count -eq 0) { return $null }

    # Évaluer chaque utilisateur - DOIT matcher le prénom ET le nom
    $matches = [System.Collections.ArrayList]::new()

    foreach ($user in $users) {
        $adFirstName = $user.GivenName
        $adLastName = $user.Surname

        if ([string]::IsNullOrWhiteSpace($adLastName)) { continue }

        # Vérifier le prénom (avec support noms composés)
        $firstNameMatch = Test-NameMatch -Name1 $SearchFirst -Name2 $adFirstName -Threshold $Threshold

        # Si prénom ne match pas directement, vérifier si c'est un sous-ensemble
        if (-not $firstNameMatch.Match) {
            # Vérifier si le prénom CSV est contenu dans le prénom AD (ex: "Christopher" dans "Christopher Moises")
            $firstNameMatch = Test-NameMatchPartial -SearchName $SearchFirst -ADName $adFirstName -Threshold $Threshold
        }

        if (-not $firstNameMatch.Match) { continue }

        # Vérifier le nom de famille (avec support noms composés)
        $lastNameMatch = Test-NameMatch -Name1 $SearchLast -Name2 $adLastName -Threshold $Threshold

        # Si nom ne match pas directement, vérifier si c'est un sous-ensemble
        if (-not $lastNameMatch.Match) {
            # Vérifier si le nom CSV est contenu dans le nom AD (ex: "Esparza" dans "Esparza Garcia")
            $lastNameMatch = Test-NameMatchPartial -SearchName $SearchLast -ADName $adLastName -Threshold $Threshold
        }

        if (-not $lastNameMatch.Match) { continue }

        # Les deux matchent!
        $combinedSimilarity = ($firstNameMatch.Similarity + $lastNameMatch.Similarity) / 2

        [void]$matches.Add([PSCustomObject]@{
            User            = $user
            FirstSimilarity = $firstNameMatch.Similarity
            LastSimilarity  = $lastNameMatch.Similarity
            Similarity      = $combinedSimilarity
            IsExact         = ($firstNameMatch.IsExact -and $lastNameMatch.IsExact)
            WasInverted     = $false
        })
    }

    if ($matches.Count -eq 0) { return $null }

    # Retourner le meilleur match
    return ($matches | Sort-Object -Property Similarity -Descending | Select-Object -First 1)
}

#endregion Functions

#region Main Script

Write-Log "========================================" -Level INFO
Write-Log "Début du traitement - Set-EmployeeIDFromCsv" -Level INFO
Write-Log "Fichier d'entrée: $InputFile" -Level INFO
Write-Log "Seuil de similarité: $($SimilarityThreshold * 100)%" -Level INFO
Write-Log "Mode WhatIf: $WhatIfPreference" -Level INFO
Write-Log "========================================" -Level INFO

# Vérifier le module AD
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Log "Le module ActiveDirectory n'est pas installé!" -Level ERROR
    exit 1
}

Import-Module ActiveDirectory -ErrorAction Stop

# Lire le fichier CSV
try {
    $firstLine = Get-Content -Path $InputFile -First 2 -Encoding UTF8
    $delimiter = if ($firstLine -match "`t") { "`t" }
                 elseif ($firstLine -match ";") { ";" }
                 else { "," }

    Write-Log "Délimiteur détecté: $(if($delimiter -eq "`t"){'TAB'}else{$delimiter})" -Level INFO

    $csvData = Import-Csv -Path $InputFile -Delimiter $delimiter -Encoding UTF8

    # Normaliser les noms de colonnes
    $csvData = $csvData | ForEach-Object {
        $row = $_
        $props = @{}

        foreach ($prop in $row.PSObject.Properties) {
            $normalizedName = $prop.Name.Trim().ToLower()
            switch -Regex ($normalizedName) {
                'prenom|firstname|given' { $props['prenom'] = $prop.Value }
                '^nom$|lastname|surname|sn' { $props['nom'] = $prop.Value }
                'card|carte|employeeid|badge' { $props['card'] = $prop.Value }
            }
        }

        [PSCustomObject]$props
    }

    $totalCount = @($csvData).Count
    Write-Log "Nombre d'entrées dans le CSV: $totalCount" -Level INFO
}
catch {
    Write-Log "Erreur lors de la lecture du CSV: $($_.Exception.Message)" -Level ERROR
    exit 1
}

# Statistiques
$stats = @{
    Total      = $totalCount
    Success    = 0
    NotFound   = 0
    Skipped    = 0
    Errors     = 0
}

$results = [System.Collections.ArrayList]::new()
$counter = 0

# Traiter chaque entrée
try {
foreach ($entry in $csvData) {
    $counter++
    $prenom = $entry.prenom
    $nom = $entry.nom
    $card = $entry.card

    # Afficher progression tous les 100 enregistrements
    if ($counter % 100 -eq 0) {
        Write-Log "Progression: $counter / $totalCount" -Level INFO
    }

    # Validation des données
    if ([string]::IsNullOrWhiteSpace($prenom) -or [string]::IsNullOrWhiteSpace($nom) -or [string]::IsNullOrWhiteSpace($card)) {
        $stats.Skipped++
        [void]$results.Add([PSCustomObject]@{
            Prenom     = $prenom
            Nom        = $nom
            Card       = $card
            Status     = 'SKIPPED'
            Reason     = 'Données incomplètes'
            ADUser     = $null
            ADFirstName = $null
            ADLastName  = $null
            Similarity = $null
            Inverted   = $null
        })
        continue
    }

    # Rechercher l'utilisateur AD
    try {
        $match = Find-ADUserByName -FirstName $prenom -LastName $nom -Threshold $SimilarityThreshold
    }
    catch {
        Write-Log "ERREUR recherche AD pour '$prenom $nom': $($_.Exception.Message)" -Level ERROR
        $stats.Errors++
        [void]$results.Add([PSCustomObject]@{
            Prenom     = $prenom
            Nom        = $nom
            Card       = $card
            Status     = 'ERROR'
            Reason     = "Erreur recherche: $($_.Exception.Message)"
            ADUser     = $null
            ADFirstName = $null
            ADLastName  = $null
            Similarity = $null
            Inverted   = $null
        })
        continue
    }

    if (-not $match) {
        $stats.NotFound++
        [void]$results.Add([PSCustomObject]@{
            Prenom     = $prenom
            Nom        = $nom
            Card       = $card
            Status     = 'NOT_FOUND'
            Reason     = 'Aucune correspondance AD'
            ADUser     = $null
            ADFirstName = $null
            ADLastName  = $null
            Similarity = $null
            Inverted   = $null
        })
        continue
    }

    $adUser = $match.User
    $similarityPct = [Math]::Round($match.Similarity * 100, 1)

    # Vérifier si employeeID est déjà défini avec la même valeur
    if (-not [string]::IsNullOrWhiteSpace($adUser.employeeID) -and $adUser.employeeID -eq $card) {
        $stats.Skipped++
        [void]$results.Add([PSCustomObject]@{
            Prenom      = $prenom
            Nom         = $nom
            Card        = $card
            Status      = 'SKIPPED'
            Reason      = 'EmployeeID déjà correct'
            ADUser      = $adUser.SamAccountName
            ADFirstName = $adUser.GivenName
            ADLastName  = $adUser.Surname
            Similarity  = $similarityPct
            Inverted    = $match.WasInverted
        })
        continue
    }

    # Log du match
    $invertedNote = if ($match.WasInverted) { " [INVERSÉ]" } else { "" }
    Write-Log "Match: $prenom $nom -> $($adUser.GivenName) $($adUser.Surname) [$($adUser.SamAccountName)] (Sim: $similarityPct%)$invertedNote" -Level INFO

    # Avertissement si écrasement
    if (-not [string]::IsNullOrWhiteSpace($adUser.employeeID)) {
        Write-Log "  ATTENTION: Écrasement $($adUser.employeeID) -> $card" -Level WARNING
    }

    # Mettre à jour employeeID
    try {
        if ($PSCmdlet.ShouldProcess("$($adUser.SamAccountName)", "Set-ADUser -EmployeeID '$card'")) {
            Set-ADUser -Identity $adUser.SamAccountName -EmployeeID $card -ErrorAction Stop
            Write-Log "SUCCESS: $($adUser.SamAccountName) -> $card" -Level SUCCESS
            $stats.Success++
            [void]$results.Add([PSCustomObject]@{
                Prenom      = $prenom
                Nom         = $nom
                Card        = $card
                Status      = 'SUCCESS'
                Reason      = 'EmployeeID mis à jour'
                ADUser      = $adUser.SamAccountName
                ADFirstName = $adUser.GivenName
                ADLastName  = $adUser.Surname
                Similarity  = $similarityPct
                Inverted    = $match.WasInverted
            })
        }
        else {
            $stats.Success++
            [void]$results.Add([PSCustomObject]@{
                Prenom      = $prenom
                Nom         = $nom
                Card        = $card
                Status      = 'WHATIF'
                Reason      = 'Serait mis à jour'
                ADUser      = $adUser.SamAccountName
                ADFirstName = $adUser.GivenName
                ADLastName  = $adUser.Surname
                Similarity  = $similarityPct
                Inverted    = $match.WasInverted
            })
        }
    }
    catch {
        Write-Log "ERREUR $($adUser.SamAccountName): $($_.Exception.Message)" -Level ERROR
        $stats.Errors++
        [void]$results.Add([PSCustomObject]@{
            Prenom      = $prenom
            Nom         = $nom
            Card        = $card
            Status      = 'ERROR'
            Reason      = $_.Exception.Message
            ADUser      = $adUser.SamAccountName
            ADFirstName = $adUser.GivenName
            ADLastName  = $adUser.Surname
            Similarity  = $similarityPct
            Inverted    = $match.WasInverted
        })
    }
}
}
catch {
    Write-Log "ERREUR CRITIQUE à la ligne $counter ($prenom $nom): $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level ERROR
}
finally {
    # Toujours générer le rapport même en cas d'erreur
    Write-Log "========================================" -Level INFO
    Write-Log "RAPPORT FINAL (traités: $counter / $totalCount)" -Level INFO
    Write-Log "========================================" -Level INFO
}

# Rapport final
Write-Log "Total traités:    $($stats.Total)" -Level INFO
Write-Log "Succès:           $($stats.Success)" -Level SUCCESS
Write-Log "Non trouvés:      $($stats.NotFound)" -Level WARNING
Write-Log "Ignorés:          $($stats.Skipped)" -Level INFO
Write-Log "Erreurs:          $($stats.Errors)" -Level ERROR
Write-Log "========================================" -Level INFO

# Exporter le rapport
$reportPath = ".\Set-EmployeeID_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
Write-Log "Rapport exporté: $reportPath" -Level INFO

# Ouvrir le rapport automatiquement
Start-Process $reportPath

return $results

#endregion Main Script
