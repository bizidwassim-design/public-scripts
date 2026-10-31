<#
.SYNOPSIS
    Lists the sessions on an RDS/RemoteApp host and logs off the chosen user's session (fixes a frozen RemoteApp).
.DESCRIPTION
    Runs "query user /server:<host>" to show the current sessions, prompts for the user name,
    resolves the session ID and runs "logoff <id> /server:<host>". Can be run by the user or by
    an admin from another machine. Main use case: a RemoteApp that is frozen or will not start.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : rights to query/log off sessions on the target host
    Impact      : Modifies the remote host (logs off one interactive session)
    License     : MIT
.EXAMPLE
    .\Invoke-RemoteSessionLogoff.ps1 -server SRV-RDS01
#>

# Log off remote session

param(
    [Parameter(Mandatory = $true)]
    [string]$server
)

$userlist = query user /server:$server

if ($userlist) {
    Write-Host "Current users:"
}
else {
    Write-Error "Cannot find the server, maybe you wrote it wrong?"
    throw $userlist
}

foreach ($line in $userlist) {
    Write-Host $line
}

$user = Read-Host -Prompt "Please enter the name of the user to logoff"

foreach ($line in $userlist[1..$userlist.Count]) {
    if ($line -like "*$user*") {
        $userid = (-split $line)[1]
    }
}

if ($userid) {
    $result = logoff $userid /server:$server
    if ($result) {
        throw $result
    }
    else {
        Write-Host "Successfully logged off" $user "."
    }
}
else {
    Write-Host $user "is not logged on."
}
