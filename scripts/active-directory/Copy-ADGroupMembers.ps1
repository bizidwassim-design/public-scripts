<#
.SYNOPSIS
    Copies all members of one AD group into another AD group.
.DESCRIPTION
    Reads the direct members of the source group and adds each of them to the destination group.
    Handy when rolling out a new GPO-filtering group that must start with the same scope as an
    existing one (e.g. Defender ASR rule groups). Existing members of the destination are kept.
.NOTES
    Author      : Wassim Bizid
    Repository  : https://github.com/bizidwassim-design/public-scripts
    Requires    : ActiveDirectory module
    Impact      : Modifies AD (adds members to the destination group)
    License     : MIT
.EXAMPLE
    .\Copy-ADGroupMembers.ps1
#>

# ---- EDIT ME ------------------------------------------------------------
# Define the source and destination group names
$sourceGroupName      = "GPO-Defender-ASR-Rules-Source"
$destinationGroupName = "GPO-Defender-ASR-Rules-Target"
# -------------------------------------------------------------------------

# Get members of the source group
$sourceGroupMembers = Get-ADGroupMember -Identity $sourceGroupName

# Add members to the destination group
foreach ($member in $sourceGroupMembers) {
    Add-ADGroupMember -Identity $destinationGroupName -Members $member
}
