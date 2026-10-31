#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes the GPO-deployed outbound firewall rules that block mshta.exe (rollback of an MSHTML hardening GPO).
.DESCRIPTION
    Looks for the named block rules in every firewall policy store (local, persistent, active,
    system defaults), removes them, scans the stores for any other outbound Block rule whose
    program is mshta.exe, runs a netsh fallback for the GPO store and optionally forces gpupdate.
    If the GPO is still linked the rules will come back at the next refresh: unlink it first.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : run as admin | NetSecurity module (built-in) | tested on Windows 10/11, Server 2019/2022
    Impact      : Modifies the local firewall (removes rules); optional gpupdate /force
    License     : MIT
.EXAMPLE
    .\Remove-MshtaFirewallRules.ps1
#>

<#
.SYNOPSIS
    Removes outbound firewall rules blocking mshta.exe that were created via GPO.

.DESCRIPTION
    This script removes Windows Defender Firewall outbound rules that block
    mshta.exe (both System32 and SysWOW64 variants) and optionally forces a
    Group Policy refresh. Run this on each affected machine, or deploy it via
    your preferred remote execution method.

.NOTES
    - Must be run as Administrator.
    - If the original GPO is still linked and enforced, the rules will return
      after the next Group Policy refresh. Remove or unlink the GPO first.
    - Tested on Windows 10/11 and Windows Server 2019/2022.
#>

# ---- EDIT ME ------------------------------------------------------------
# Adjust these if you used different names when creating the rules.
$RuleNames = @(
    "Block mshta.exe outbound via GPO",          # System32 variant
    "Block mshta.exe outbound via GPO (WOW64)"   # SysWOW64 variant (64-bit systems)
)

# Paths covered by the rules
$MshtaPaths = @(
    "%systemroot%\System32\mshta.exe",
    "%systemroot%\SysWOW64\mshta.exe"
)
# -------------------------------------------------------------------------

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] $Message" -ForegroundColor $Color
}

Write-Status "=== mshta.exe Outbound Firewall Block — Removal Script ===" "Yellow"
Write-Status "Checking for matching firewall rules..."

$removed   = 0
$notFound  = 0

# GPO rules are stored in a different policy store than local rules.
# Get-NetFirewallRule defaults to the local store and will not find GPO-deployed
# rules. We must explicitly target the Group Policy store.
$PolicyStores = @(
    "localhost"                    # Local policy store  (covers manually added rules)
    "PersistentStore"              # Persistent store    (merged view, catches some GPO rules)
    "ActiveStore"                  # Active/merged store (what the firewall actually enforces)
    "SystemDefaults"               # System defaults
)

# Additionally query the GPO store directly via netsh for discovery,
# but use Remove-NetFirewallRule -PolicyStore for deletion.

# 1. Remove rules by the exact name(s) used during GPO creation, across all stores
foreach ($store in $PolicyStores) {
    foreach ($name in $RuleNames) {
        try {
            $rules = Get-NetFirewallRule -DisplayName $name -PolicyStore $store -ErrorAction SilentlyContinue
            if ($rules) {
                foreach ($rule in $rules) {
                    Write-Status "Removing rule: '$($rule.DisplayName)' from store '$store' (ID: $($rule.Name))"
                    Remove-NetFirewallRule -Name $rule.Name -PolicyStore $store -ErrorAction Stop
                    $removed++
                }
            }
        } catch {
            # Store may not be accessible on all systems — silently continue
        }
    }
}

# 2. Safety net — scan all stores for any remaining Outbound/Block rules targeting mshta.exe
Write-Status "Scanning all policy stores for any remaining outbound block rules targeting mshta.exe..."

foreach ($store in $PolicyStores) {
    try {
        $allOutboundBlockRules = Get-NetFirewallRule -Direction Outbound -Action Block -PolicyStore $store -ErrorAction SilentlyContinue
        foreach ($rule in $allOutboundBlockRules) {
            $appFilter = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
            if ($appFilter) {
                $normalizedPath = $appFilter.Program.ToLower()
                if ($normalizedPath -like "*\mshta.exe") {
                    Write-Status "Found additional mshta.exe block rule: '$($rule.DisplayName)' in store '$store' — removing..." "Magenta"
                    Remove-NetFirewallRule -Name $rule.Name -PolicyStore $store -ErrorAction Stop
                    $removed++
                }
            }
        }
    } catch {
        # Store may not be accessible — silently continue
    }
}

# 3. Fallback: use netsh to delete from the GPO store, which PowerShell CIM
#    cmdlets sometimes cannot reach even with -PolicyStore specified.
Write-Status "Running netsh fallback for GPO store rules..."
foreach ($name in $RuleNames) {
    $netshOutput = netsh advfirewall firewall delete rule name="$name" dir=out 2>&1
    if ($netshOutput -match "Deleted \d+ rule") {
        Write-Status "netsh removed rule: '$name'" "Green"
        $removed++
    } elseif ($netshOutput -match "No rules match") {
        Write-Status "netsh: rule not found: '$name'" "DarkGray"
    } else {
        Write-Status "netsh output for '$name': $netshOutput" "DarkGray"
    }
}

# 4. Summary
Write-Host ""
if ($removed -gt 0) {
    Write-Status "$removed rule(s) successfully removed." "Green"
} else {
    Write-Status "No matching rules were found. Nothing was removed." "Yellow"
}

# 5. Optional: force Group Policy refresh so local policy stays in sync
$refresh = Read-Host "`nRun 'gpupdate /force' now? (y/n)"
if ($refresh -match '^[Yy]') {
    Write-Status "Running gpupdate /force ..."
    gpupdate /force
    Write-Status "Group Policy refresh complete." "Green"
} else {
    Write-Status "Skipped gpupdate. Remember: if the GPO is still active, rules will reapply on the next refresh." "Yellow"
}

Write-Host ""
Write-Status "Done." "Green"
