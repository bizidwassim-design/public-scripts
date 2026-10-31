<#
.SYNOPSIS
    Silently uninstall TeamViewer / TeamViewer Host and clean up leftover files and registry keys.
.DESCRIPTION
    Finds TeamViewer products in the Uninstall registry keys (32/64-bit) and via Win32_Product, runs
    the silent uninstaller (MSI or EXE), then removes the Program Files / AppData folders and the
    TeamViewer registry hives. Must run elevated. Intended for RMM deployment.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin
    Impact      : Modifies endpoint (uninstalls software, deletes folders and registry keys)
    License     : MIT
.EXAMPLE
    .\Uninstall-TeamViewer.ps1
#>

# TeamViewer Uninstaller Script
# Checks for TeamViewer and TeamViewer Host installations and removes them

# Requires Administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script requires Administrator privileges. Please run as Administrator." -ForegroundColor Red
    exit 1
}

Write-Host "Checking for TeamViewer installations..." -ForegroundColor Yellow

# Function to uninstall via WMI
function Uninstall-Program {
    param(
        [string]$ProductName,
        [string]$UninstallString
    )

    try {
        Write-Host "Attempting to uninstall: $ProductName" -ForegroundColor Green

        if ($UninstallString -like "*msiexec*") {
            # MSI uninstall
            $guid = ($UninstallString -split "/I")[1].Trim()
            Start-Process "msiexec.exe" -ArgumentList "/x $guid /quiet /norestart" -Wait -NoNewWindow
        } else {
            # EXE uninstall
            if ($UninstallString -like "*TeamViewer*uninstall.exe*") {
                Start-Process $UninstallString -ArgumentList "/S" -Wait -NoNewWindow
            } else {
                Start-Process $UninstallString -ArgumentList "/SILENT /NORESTART" -Wait -NoNewWindow
            }
        }

        Write-Host "Successfully uninstalled: $ProductName" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Failed to uninstall $ProductName`: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Check installed programs via registry (both 32-bit and 64-bit)
$registryPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$teamviewerPrograms = @()

foreach ($path in $registryPaths) {
    $programs = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match "TeamViewer" }

    $teamviewerPrograms += $programs
}

# Also check via WMI
$wmiPrograms = Get-WmiObject -Class Win32_Product |
               Where-Object { $_.Name -match "TeamViewer" }

if ($teamviewerPrograms.Count -eq 0 -and $wmiPrograms.Count -eq 0) {
    Write-Host "No TeamViewer installations found." -ForegroundColor Green
    exit 0
}

Write-Host "Found TeamViewer installations:" -ForegroundColor Yellow

# Display found programs
foreach ($program in $teamviewerPrograms) {
    Write-Host "  - $($program.DisplayName) (Version: $($program.DisplayVersion))" -ForegroundColor Cyan
}

foreach ($program in $wmiPrograms) {
    Write-Host "  - $($program.Name) (Version: $($program.Version))" -ForegroundColor Cyan
}

# Uninstall programs found in registry
$uninstallSuccess = $true
foreach ($program in $teamviewerPrograms) {
    if ($program.UninstallString) {
        $success = Uninstall-Program -ProductName $program.DisplayName -UninstallString $program.UninstallString
        if (-not $success) { $uninstallSuccess = $false }
    }
}

# Uninstall programs found via WMI
foreach ($program in $wmiPrograms) {
    try {
        Write-Host "Attempting to uninstall via WMI: $($program.Name)" -ForegroundColor Green
        $result = $program.Uninstall()
        if ($result.ReturnValue -eq 0) {
            Write-Host "Successfully uninstalled: $($program.Name)" -ForegroundColor Green
        } else {
            Write-Host "Failed to uninstall $($program.Name) - Return code: $($result.ReturnValue)" -ForegroundColor Red
            $uninstallSuccess = $false
        }
    }
    catch {
        Write-Host "Failed to uninstall $($program.Name): $($_.Exception.Message)" -ForegroundColor Red
        $uninstallSuccess = $false
    }
}

# Clean up remaining TeamViewer files and folders
Write-Host "Cleaning up remaining TeamViewer files..." -ForegroundColor Yellow

$cleanupPaths = @(
    "$env:ProgramFiles\TeamViewer",
    "${env:ProgramFiles(x86)}\TeamViewer",
    "$env:APPDATA\TeamViewer",
    "$env:LOCALAPPDATA\TeamViewer"
)

foreach ($path in $cleanupPaths) {
    if (Test-Path $path) {
        try {
            Remove-Item $path -Recurse -Force -ErrorAction Stop
            Write-Host "Removed: $path" -ForegroundColor Green
        }
        catch {
            Write-Host "Could not remove: $path - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Clean up registry entries
Write-Host "Cleaning up registry entries..." -ForegroundColor Yellow

$regPaths = @(
    "HKLM:\SOFTWARE\TeamViewer",
    "HKLM:\SOFTWARE\WOW6432Node\TeamViewer",
    "HKCU:\SOFTWARE\TeamViewer"
)

foreach ($regPath in $regPaths) {
    if (Test-Path $regPath) {
        try {
            Remove-Item $regPath -Recurse -Force -ErrorAction Stop
            Write-Host "Removed registry key: $regPath" -ForegroundColor Green
        }
        catch {
            Write-Host "Could not remove registry key: $regPath - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

# Final status
if ($uninstallSuccess) {
    Write-Host "`nTeamViewer uninstallation completed successfully!" -ForegroundColor Green
    Write-Host "Please reboot the system to complete the removal process." -ForegroundColor Yellow
} else {
    Write-Host "`nTeamViewer uninstallation completed with some errors." -ForegroundColor Yellow
    Write-Host "Please check the output above and manually remove any remaining components." -ForegroundColor Yellow
}
