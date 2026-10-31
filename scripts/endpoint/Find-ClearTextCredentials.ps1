<#
.SYNOPSIS
    Scan every local drive for script files that contain clear-text credential keywords.
.DESCRIPTION
    Walks all FileSystem drives, reads *.ps1 / *.bat / *.vbs / *.sh / *.py / *.cmd files line by line
    and records every line matching one of the search terms (password, secret, key, ...).
    Results are written to a CSV: File Path, File Name, Line Number, Found Text.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin (to read all folders)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Find-ClearTextCredentials.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$outputCsv   = "C:\Scripts\Reports\ScriptCredentialsScanResults.csv"
# Terms to search for in the scripts
$searchTerms = @('password', 'passwd', 'pwd', 'credential', 'creds', 'auth', 'key', 'secret')
# -------------------------------------------------------------------------

# Initialize the CSV file with headers
"File Path,File Name,Line Number,Found Text" | Out-File -FilePath $outputCsv -Encoding UTF8

# List all available local drives
$drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root

foreach ($drive in $drives) {
    # Search for script files (*.ps1, *.bat, *.vbs, *.sh, *.py, *.cmd) in each drive
    $scriptFiles = Get-ChildItem -Path $drive -Recurse -Include *.ps1, *.bat, *.vbs, *.sh, *.py, *.cmd -ErrorAction SilentlyContinue

    foreach ($file in $scriptFiles) {
        # Read each script file line by line
        $fileContent = Get-Content -Path $file.FullName

        for ($i = 0; $i -lt $fileContent.Length; $i++) {
            $line = $fileContent[$i]

            # Check if the line contains any of the search terms
            foreach ($term in $searchTerms) {
                if ($line -match $term) {
                    # Extract the line containing the term
                    $foundText = $line.Trim()

                    # Output the results to the CSV file
                    $output = "$($file.FullName),$($file.Name),$($i + 1),$foundText"
                    $output | Out-File -FilePath $outputCsv -Append -Encoding UTF8
                }
            }
        }
    }
}

Write-Host "Scan completed. Results are saved to $outputCsv"
