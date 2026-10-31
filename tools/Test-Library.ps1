<#
.SYNOPSIS
    Repository self-check: every script parses, and nothing that looks like a secret or an internal identifier is present.
.DESCRIPTION
    1. Parses every .ps1 with the PowerShell parser (no execution) and fails on syntax errors.
    2. Scans every file under scripts/ for patterns that must never be committed: private IP addresses,
       e-mail addresses outside contoso.com, GUIDs, "password = '...'" literals, bearer tokens, Slack/Teams webhooks,
       and a deny-list of words in tools/denylist.txt (one per line, case-insensitive).
    Exit code 1 on any finding. Runs in CI on every push and pull request.
.NOTES
    Author     : Wassim Bizid
    License    : MIT
#>
[CmdletBinding()]
param([string]$Root = (Join-Path $PSScriptRoot ".."))

$ErrorActionPreference = "Stop"
$scripts = Join-Path $Root "scripts"
$failures = New-Object System.Collections.Generic.List[string]

# 1. Syntax ---------------------------------------------------------------
Get-ChildItem $scripts -Recurse -Filter *.ps1 | ForEach-Object {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($e in $errors) { $failures.Add("SYNTAX  $($_.FullName.Substring($Root.Length)) :$($e.Extent.StartLineNumber) $($e.Message)") }
}

# 2. Leak patterns --------------------------------------------------------
$patterns = @{
    "private IPv4"        = '\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b'
    "non-example e-mail"  = '\b[\w.+-]+@(?!contoso\.com\b)(?!example\.(com|org|net)\b)[\w-]+\.[\w.-]+\b'
    "GUID"                = '\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
    "password literal"    = '(?i)(password|passwd|pwd)\s*=\s*["''][^"''<$]{4,}["'']'
    "bearer / api token"  = '(?i)(bearer\s+[a-z0-9\-_\.]{20,}|api[_-]?key\s*=\s*["''][a-z0-9\-_]{16,}["''])'
    "webhook URL"         = '(?i)https://[\w.-]*(webhook\.office\.com|hooks\.slack\.com)[^\s"'']*'
}
# denylist.txt is committed (generic examples). denylist.local.txt is git-ignored: put YOUR organisation's name,
# domains, site codes and server prefixes there so they are never published, and never appear in the repository.
$deny = @()
foreach ($name in "denylist.txt", "denylist.local.txt") {
    $file = Join-Path $PSScriptRoot $name
    if (Test-Path $file) { $deny += Get-Content $file | Where-Object { $_ -and -not $_.StartsWith("#") } }
}

Get-ChildItem $scripts -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($Root.Length)
    $lines = Get-Content $_.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        foreach ($name in $patterns.Keys) {
            if ($line -match $patterns[$name]) { $failures.Add("LEAK    $rel :$($i+1) [$name] $($line.Trim())") }
        }
        foreach ($word in $deny) {
            if ($line -imatch [regex]::Escape($word)) { $failures.Add("DENY    $rel :$($i+1) [$word]") }
        }
    }
}

# 3. The deny-list also applies to documentation and tooling (catalogue, README, changelog...), not only scripts/
$docFiles = @(Get-ChildItem (Join-Path $Root "docs") -Recurse -File -ErrorAction SilentlyContinue) +
            @(Get-ChildItem $Root -File -Include *.md, *.csv, *.yml, *.json, *.py -ErrorAction SilentlyContinue) +
            @(Get-ChildItem (Join-Path $Root "tools") -File -Filter *.py -ErrorAction SilentlyContinue) +
            @(Get-ChildItem (Join-Path $Root ".github") -Recurse -File -ErrorAction SilentlyContinue)
foreach ($f in $docFiles) {
    $rel = $f.FullName.Substring($Root.Length)
    $lines = Get-Content $f.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($word in $deny) {
            if ($lines[$i] -imatch [regex]::Escape($word)) { $failures.Add("DENY    $rel :$($i+1) [$word]") }
        }
    }
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "`n$($failures.Count) problem(s) found." -ForegroundColor Red
    exit 1
}
$count = (Get-ChildItem $scripts -Recurse -File).Count
Write-Host "OK — $count files parsed and scanned, nothing found." -ForegroundColor Green
