<#
.SYNOPSIS
    List every .NET Framework, .NET Core / .NET 5+ SDK and runtime installed on the local computer.
.DESCRIPTION
    Reads the NDP registry keys (mapping Release numbers to 4.5-4.8.1), runs dotnet --list-sdks /
    --list-runtimes, scans the ASP.NET / .NETCore / Uninstall registry hives and the Program Files
    dotnet folders. Everything is captured in a transcript file (DotNetVersions.txt).
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : nothing special (run as admin for a complete registry view)
    Impact      : Read-only
    License     : MIT
.EXAMPLE
    .\Get-DotNetVersions.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$outputFolder = "C:\Scripts\Reports"
# -------------------------------------------------------------------------

# PowerShell Script to List All .NET versions
# This script checks for various .NET installations including:
# - .NET Framework
# - .NET Core
# - .NET SDK
# - ASP.NET Core Runtime
# - .NET Desktop Runtime
# - .NET Runtime

# Create output directory if it doesn't exist
$outputFile = "$outputFolder\DotNetVersions.txt"

if (-not (Test-Path -Path $outputFolder)) {
    Write-Host "Creating directory $outputFolder..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
    Write-Host "Directory created successfully." -ForegroundColor Green
}

# Start transcript to capture all output
Start-Transcript -Path $outputFile -Force

# Create a function to output section headers
function Write-Header {
    param ([string]$Title)
    Write-Host "`n$Title" -ForegroundColor Cyan
    Write-Host ("-" * $Title.Length) -ForegroundColor Cyan
}

# System information
Write-Header "System Information"
Write-Host "Computer Name: $env:COMPUTERNAME"
Write-Host "Date of Scan: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Windows Version: $(Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object -ExpandProperty Caption)"

# Check for .NET Framework versions
Write-Header ".NET Framework Versions"
Get-ChildItem "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP" -Recurse |
    Get-ItemProperty -Name Version, Release -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^v\d' } |
    ForEach-Object {
        $version = $_.Version
        $release = $_.Release
        # Convert release number to version for .NET 4.5 and later
        if ($release -ge 378389) {
            $version = switch ($release) {
                { $_ -ge 533320 } { "4.8.1 or later"; break }
                { $_ -ge 528040 } { "4.8"; break }
                { $_ -ge 461808 } { "4.7.2"; break }
                { $_ -ge 461308 } { "4.7.1"; break }
                { $_ -ge 460798 } { "4.7"; break }
                { $_ -ge 394802 } { "4.6.2"; break }
                { $_ -ge 394254 } { "4.6.1"; break }
                { $_ -ge 393295 } { "4.6"; break }
                { $_ -ge 379893 } { "4.5.2"; break }
                { $_ -ge 378675 } { "4.5.1"; break }
                { $_ -ge 378389 } { "4.5"; break }
                default { $version }
            }
        }
        [PSCustomObject]@{
            Version = $version
            Release = $release
            Path = $_.PSPath
        }
    } | Format-Table -AutoSize -Property Version, Release

# Check for .NET Core, .NET 5+ and related components
Write-Header ".NET Core, .NET 5+ SDK Versions"
$dotnetCommand = Get-Command dotnet -ErrorAction SilentlyContinue
if ($dotnetCommand) {
    try {
        $sdkList = dotnet --list-sdks
        if ($sdkList) {
            $sdkList | ForEach-Object {
                $_ -replace '\[.*\]', ''
            }
        } else {
            Write-Host "No .NET SDK installations found." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Error listing .NET SDKs: $_" -ForegroundColor Red
    }
} else {
    Write-Host "dotnet command not found. .NET Core/.NET 5+ SDK may not be installed." -ForegroundColor Yellow
}

Write-Header ".NET Core, .NET 5+ Runtime Versions"
if ($dotnetCommand) {
    try {
        $runtimeList = dotnet --list-runtimes
        if ($runtimeList) {
            $runtimeList | ForEach-Object {
                $_ -replace '\[.*\]', ''
            }
        } else {
            Write-Host "No .NET runtime installations found." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Error listing .NET runtimes: $_" -ForegroundColor Red
    }
} else {
    Write-Host "dotnet command not found. .NET Core/.NET 5+ runtime may not be installed." -ForegroundColor Yellow
}

# Check for installed .NET components from Windows Registry
Write-Header "Installed .NET Components from Registry"
$paths = @(
    "HKLM:\SOFTWARE\Microsoft\ASP.NET Core\Shared Framework",
    "HKLM:\SOFTWARE\Microsoft\ASP.NET\Shared Framework",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\ASP.NET Core\Shared Framework",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\ASP.NET\Shared Framework",
    "HKLM:\SOFTWARE\Microsoft\.NETFramework",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework",
    "HKLM:\SOFTWARE\Microsoft\.NETCore",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETCore",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "Microsoft|\.NET|ASP\.NET|Core|Runtime|Framework|SDK" } |
            ForEach-Object {
                try {
                    $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
                    if ($props) {
                        [PSCustomObject]@{
                            Component = $_.PSChildName
                            Path = $_.PSPath
                            Version = if ($props.Version) { $props.Version } else { "Unknown" }
                            DisplayName = if ($props.DisplayName) { $props.DisplayName } else { "Unknown" }
                        }
                    }
                } catch {
                    # Silently continue if there's an error reading a registry key
                }
            } | Where-Object { $_.DisplayName -ne "Unknown" } | Sort-Object -Property DisplayName -Unique |
            Format-Table -AutoSize -Property DisplayName, Version
    }
}

# Additional check for programfiles installations
Write-Header ".NET Installations in Program Files"
$programFilesPaths = @(
    "${env:ProgramFiles}\dotnet",
    "${env:ProgramFiles(x86)}\dotnet",
    "${env:ProgramFiles}\Microsoft SDKs",
    "${env:ProgramFiles(x86)}\Microsoft SDKs",
    "${env:ProgramFiles}\Microsoft.NET",
    "${env:ProgramFiles(x86)}\Microsoft.NET"
)

foreach ($path in $programFilesPaths) {
    if (Test-Path $path) {
        Write-Host "Found .NET installation directory: $path" -ForegroundColor Green
        Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Name |
            ForEach-Object { "- $_" }
    }
}

# Summary
Write-Header "Summary"
Write-Host "This script has detected all installed .NET versions on this system."
Write-Host "Results have been saved to: $outputFile"
Write-Host "Scan completed on: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Stop transcript (saves to file)
Stop-Transcript
