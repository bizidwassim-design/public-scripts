<#
.SYNOPSIS
    Check every AD user's NT hash against the Have I Been Pwned NTLM range API (k-anonymity).
.DESCRIPTION
    Replicates account hashes from a domain controller with DSInternals (Get-ADReplAccount),
    converts each NT hash to hex and queries https://api.pwnedpasswords.com/range/<prefix>
    (only the first 5 hex characters leave the network). Prints the users whose password hash
    appears in a known breach.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : DSInternals module | Domain Admin / replication rights (DCSync)
    Impact      : Read-only (highly sensitive: handles password hashes, run on a secured host)
    License     : MIT
.EXAMPLE
    .\Find-CompromisedADPasswords.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$DomainController = "dc01.corp.contoso.local"
# -------------------------------------------------------------------------

function Convert-BytesToHexString {
    param (
        [Parameter(Mandatory=$true)]
        [byte[]]$bytes
    )
    return -join ($bytes | ForEach-Object { "{0:X2}" -f $_ })
}

function Check-HIBPHash {
    param (
        [Parameter(Mandatory=$true)][string]$NTLMHash
    )
    $HashPrefix = $NTLMHash.Substring(0, 5)  # First 5 characters of the hash
    $HashSuffix = $NTLMHash.Substring(5)     # The rest of the hash

    # Query HIBP API for this hash prefix (NTLM mode)
    $apiUrl = "https://api.pwnedpasswords.com/range/$HashPrefix?mode=ntlm"
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get

    # Check if our full hash suffix is in the response
    if ($response -match $HashSuffix) {
        Write-Host "Compromised password found for hash: $NTLMHash" -ForegroundColor Yellow
        return $true
    } else {
        #Write-Host "Password is safe for hash: $NTLMHash"
        return $false
    }
}

# Check if any of your AD users have compromised passwords
$ADUsers = Get-ADReplAccount -All -Server $DomainController | Select-Object SamAccountName, NTHash

foreach ($user in $ADUsers) {
if ($user.NTHash -eq $null){continue}
    # Convert the NTHash byte array to a hexadecimal string
    $ntlmHashHex = Convert-BytesToHexString -bytes $user.NTHash

    $isCompromised = Check-HIBPHash -NTLMHash $ntlmHashHex
    if ($isCompromised) {
        Write-Host "User $($user.SamAccountName) has a compromised password."
    }
}
