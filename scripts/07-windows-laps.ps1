<#
.SYNOPSIS
    Prepares AD for Windows LAPS: schema, reader group, and scoped OU permissions.

.DESCRIPTION
    - Extends the schema (one-time, forest-wide, irreversible; skipped if already done)
    - Creates the reader group and adds the members that need password access
    - Lets computers in the target OU write their own password
    - Grants the reader group read access on that OU only
    The "WS - LAPS" GPO itself is configured in GPMC (see docs/07-windows-laps.md).

.EXAMPLE
    .\07-windows-laps.ps1 -WhatIf
    .\07-windows-laps.ps1 -Verbose
#>
#Requires -Modules ActiveDirectory, LAPS
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$TargetOU = "OU=Workstations,OU=LAB,$((Get-ADDomain).DistinguishedName)",
    [string]$ReaderGroup = 'GG_LAPS_Readers',
    [string]$GroupsOU = "OU=Groups,OU=LAB,$((Get-ADDomain).DistinguishedName)",
    [string[]]$ReaderMembers = @('GG_IT', 'Domain Admins')
)

$ErrorActionPreference = 'Stop'
$netbios = (Get-ADDomain).NetBIOSName

# Schema: present once the msLAPS-Password attribute exists
$schemaNC = (Get-ADRootDSE).schemaNamingContext
$hasSchema = [bool](Get-ADObject -SearchBase $schemaNC -Filter "lDAPDisplayName -eq 'msLAPS-Password'")
if ($hasSchema) {
    Write-Verbose 'Windows LAPS schema already present.'
}
elseif ($PSCmdlet.ShouldProcess('AD schema', 'Extend for Windows LAPS (irreversible)')) {
    Update-LapsADSchema -Confirm:$false
}

# Reader group and membership
if (-not (Get-ADGroup -Filter "Name -eq '$ReaderGroup'") -and $PSCmdlet.ShouldProcess($ReaderGroup, 'Create global group')) {
    New-ADGroup -Name $ReaderGroup -GroupScope Global -Path $GroupsOU
}
$current = @()
if (Get-ADGroup -Filter "Name -eq '$ReaderGroup'") {
    $current = Get-ADGroupMember $ReaderGroup | Select-Object -ExpandProperty Name
}
$toAdd = $ReaderMembers | Where-Object { $_ -notin $current }
if ($toAdd -and $PSCmdlet.ShouldProcess($ReaderGroup, "Add members: $($toAdd -join ', ')")) {
    Add-ADGroupMember -Identity $ReaderGroup -Members $toAdd
}

# OU permissions (both cmdlets are safe to re-apply)
if ($PSCmdlet.ShouldProcess($TargetOU, 'Allow computers to update their own LAPS password')) {
    Set-LapsADComputerSelfPermission -Identity $TargetOU | Out-Null
}
if ($PSCmdlet.ShouldProcess($TargetOU, "Grant $ReaderGroup read access to LAPS passwords")) {
    Set-LapsADReadPasswordPermission -Identity $TargetOU -AllowedPrincipals "$netbios\$ReaderGroup" | Out-Null
}

Find-LapsADExtendedRights -Identity $TargetOU

# After the GPO has applied on a client (shows status, not the password):
#   Get-LapsADPassword -Identity WS01 | Format-List
