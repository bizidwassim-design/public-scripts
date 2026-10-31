<#
.SYNOPSIS
    Connects a shared network printer (\\server\printer) for the current user, optionally as default.
.DESCRIPTION
    Calls Add-Printer -ConnectionName with the UNC path and, with -SetAsDefault, sets it as the
    default printer through WScript.Network. Must run in the user's context (e.g. an RMM
    "run as current user" automation). Uses only built-in cmdlets.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as the logged-on user | PrintManagement module (built-in)
    Impact      : Modifies the user profile (adds a printer connection)
    License     : MIT
.EXAMPLE
    .\Add-SharedPrinter.ps1 -PrinterPath "\\SRV-PRINT01\Office-Printer"
    .\Add-SharedPrinter.ps1 -PrinterPath "\\SRV-PRINT01\Office-Printer" -SetAsDefault
#>

# Add Shared Network Printer
# No additional modules required - uses built-in Windows cmdlets

param(
    [Parameter(Mandatory=$true)]
    [string]$PrinterPath,        # e.g. \\printserver\PrinterName

    [switch]$SetAsDefault        # Optional: set as default printer
)

try {
    Write-Host "Connecting to printer: $PrinterPath" -ForegroundColor Cyan

    # Add the network printer
    Add-Printer -ConnectionName $PrinterPath -ErrorAction Stop

    Write-Host "Successfully added printer: $PrinterPath" -ForegroundColor Green

    # Set as default if requested
    if ($SetAsDefault) {
        (New-Object -ComObject WScript.Network).SetDefaultPrinter($PrinterPath)
        Write-Host "Set '$PrinterPath' as the default printer." -ForegroundColor Green
    }

} catch [System.InvalidOperationException] {
    Write-Error "Could not connect to printer. Verify the path is correct and the print server is reachable."
} catch {
    Write-Error "An error occurred: $_"
}
