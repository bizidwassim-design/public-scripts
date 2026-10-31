<#
.SYNOPSIS
    Silently uninstalls every Mozilla Firefox installation on a Windows machine (system-wide and per-user).
.DESCRIPTION
    Scans HKLM (64/32-bit), HKCU and every local user's NTUSER.DAT hive for Firefox uninstall
    entries, aborts if Firefox is running, deduplicates by uninstall string and runs each
    uninstaller with /S (falls back to the default helper.exe paths). Non-interactive; suitable
    for RMM (NinjaOne) or PDQ deployment. Profiles/user data are kept.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin
    Impact      : Modifies the local machine (uninstalls software, temporarily loads user registry hives)
    License     : MIT
.EXAMPLE
    .\Uninstall-Firefox.ps1
#>

# Uninstall ALL Firefox installations from Windows (system-wide and per-user)
# Run this script as Administrator

$ErrorActionPreference = "Continue"

function Get-FirefoxInstallations {
    $regPaths = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*";        Scope = "System (64-bit)" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"; Scope = "System (32-bit)" },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*";        Scope = "Current User" }
    )

    $installs = @()
    foreach ($entry in $regPaths) {
        $matches = Get-ItemProperty $entry.Path -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*Mozilla Firefox*" }
        foreach ($m in $matches) {
            $installs += [PSCustomObject]@{
                DisplayName     = $m.DisplayName
                Version         = $m.DisplayVersion
                UninstallString = $m.UninstallString
                Scope           = $entry.Scope
            }
        }
    }

    # Also enumerate per-user registry hives for other local accounts
    $profileList = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*" |
        Where-Object { $_.PSChildName -match "^S-1-5-21" }

    foreach ($profile in $profileList) {
        $sid = $profile.PSChildName
        # Skip if this SID is already loaded (i.e. the current user, already checked above)
        $loaded = (Get-Item "HKU:\$sid" -ErrorAction SilentlyContinue) -ne $null

        if (-not $loaded) {
            $hive = $profile.ProfileImagePath + "\NTUSER.DAT"
            if (Test-Path $hive) {
                reg load "HKU\$sid" $hive 2>$null | Out-Null
            }
        }

        $hivePath = "Registry::HKU\$sid\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        $matches = Get-ItemProperty $hivePath -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*Mozilla Firefox*" }

        foreach ($m in $matches) {
            $installs += [PSCustomObject]@{
                DisplayName     = $m.DisplayName
                Version         = $m.DisplayVersion
                UninstallString = $m.UninstallString
                Scope           = "User: $($profile.ProfileImagePath | Split-Path -Leaf)"
            }
        }
    }

    return $installs
}

function Invoke-FirefoxUninstaller {
    param([string]$UninstallString)

    # Extract exe path — strip quotes and any trailing arguments
    $exe = ($UninstallString -replace '"', '').Trim()
    $exe = ($exe -split '\s+/')[0].Trim()

    # Try registry path first, then well-known fallback paths
    $candidates = @(
        $exe,
        "$env:ProgramFiles\Mozilla Firefox\uninstall\helper.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\uninstall\helper.exe"
    ) | Select-Object -Unique

    foreach ($path in $candidates) {
        if (Test-Path $path) {
            Write-Host "  Running: $path /S" -ForegroundColor DarkGray
            Start-Process -FilePath $path -ArgumentList "/S" -Wait -NoNewWindow
            return $true
        }
    }
    return $false
}

# ── Main ────────────────────────────────────────────────────────────────────

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Please run this script as Administrator."
    exit 1
}

# Mount HKU if not already available
if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
}

Write-Host "`nScanning for Firefox installations...`n" -ForegroundColor Cyan
$installs = Get-FirefoxInstallations

if ($installs.Count -eq 0) {
    Write-Host "No Firefox installations found." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($installs.Count) Firefox installation(s):`n" -ForegroundColor Green
$installs | ForEach-Object {
    Write-Host "  [$($_.Scope)]  $($_.DisplayName) $($_.Version)" -ForegroundColor White
}

# Fail if Firefox is running
$ffProcs = Get-Process -Name "firefox" -ErrorAction SilentlyContinue
if ($ffProcs) {
    Write-Error "Firefox is currently running. Please close it before running this script."
    exit 1
}

# Deduplicate by UninstallString so the same installer isn't run twice
$unique = $installs | Sort-Object UninstallString -Unique

Write-Host "`nUninstalling..." -ForegroundColor Cyan
$successCount = 0
foreach ($inst in $unique) {
    Write-Host "`n  [$($inst.Scope)]  $($inst.DisplayName) $($inst.Version)"
    $ok = Invoke-FirefoxUninstaller -UninstallString $inst.UninstallString
    if ($ok) {
        Write-Host "  Uninstalled successfully." -ForegroundColor Green
        $successCount++
    } else {
        Write-Warning "  Could not locate uninstaller for this entry. Skipping."
    }
}

Write-Host "`n$successCount of $($unique.Count) installation(s) removed." -ForegroundColor Cyan
