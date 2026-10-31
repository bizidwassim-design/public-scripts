<#
.SYNOPSIS
    Synchronise les réservations DHCP d'un serveur source vers un serveur cible (toutes les étendues).
.DESCRIPTION
    Le failover DHCP ne réplique pas les réservations. Pour chaque étendue du serveur source, le script
    ajoute sur le serveur cible les réservations manquantes (IP, ClientId, Nom, Description) et supprime
    sur la cible celles qui n'existent plus sur la source. Pensé pour une tâche planifiée (ex. 2x/jour).
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : DhcpServer module | DHCP Administrators on both servers
    Impact      : Modifies DHCP (adds/removes reservations on the target server)
    License     : MIT
.EXAMPLE
    .\Sync-DhcpReservations.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
$SourceDHCP = "DHCP02.corp.contoso.local"
$CibleDHCP  = "DHCP01.corp.contoso.local"
# -------------------------------------------------------------------------

# Récupération de toutes les plages DHCP du serveur source
$Scopes = Get-DhcpServerv4Scope -ComputerName $SourceDHCP

# Boucle sur chaque plage DHCP
foreach ($Scope in $Scopes) {
    $ScopeID = $Scope.ScopeId
    Write-Host "Synchronisation du ScopeID $ScopeID"

    # Récupération des réservations sur le serveur source et cible
    $ReservationsSource = Get-DhcpServerv4Reservation -ComputerName $SourceDHCP -ScopeId $ScopeID
    $ReservationsCible = Get-DhcpServerv4Reservation -ComputerName $CibleDHCP -ScopeId $ScopeID -ErrorAction SilentlyContinue

    # Création d'un dictionnaire des réservations existantes sur le serveur cible
    $ReservationsCibleHash = @{}
    foreach ($res in $ReservationsCible) {
        $ReservationsCibleHash[$res.ClientId] = $res
    }

    # Ajout des nouvelles réservations
    foreach ($res in $ReservationsSource) {
        if (-not $ReservationsCibleHash.ContainsKey($res.ClientId)) {
            Write-Host "Ajout de la réservation $($res.ClientId) sur $CibleDHCP pour le Scope $ScopeID"
            Add-DhcpServerv4Reservation -ComputerName $CibleDHCP -ScopeId $ScopeID -IPAddress $res.IPAddress -ClientId $res.ClientId -Description $res.Description -Name $res.Name
        }
    }

    # Suppression des réservations obsolètes
    foreach ($res in $ReservationsCible) {
        if ($ReservationsSource.ClientId -notcontains $res.ClientId) {
            Write-Host "Suppression de la réservation obsolète $($res.ClientId) sur $CibleDHCP pour le Scope $ScopeID"
            Remove-DhcpServerv4Reservation -ComputerName $CibleDHCP -ScopeId $ScopeID -ClientId $res.ClientId -Confirm:$false
        }
    }
}

Write-Host "Synchronisation terminée pour tous les Scopes."
