<#
.SYNOPSIS
    Prepares AD for Windows LAPS: schema, reader group, and scoped OU permissions.

.DESCRIPTION
    Values come from the configuration file (Laps section).
    - Extends the schema (one-time, forest-wide, irreversible; skipped if already done)
    - Creates the reader group and adds the members that need password access
    - Lets computers in the target OU write their own password
    - Grants the reader group read access on that OU only
    The LAPS GPO itself is configured in GPMC (see docs/07-windows-laps.md).

.PARAMETER ConfigPath
    Environment configuration file. Defaults to config/lab.psd1.

.EXAMPLE
    .\07-windows-laps.ps1 -WhatIf
#>
#Requires -Modules ActiveDirectory, LAPS
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\lab.psd1')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabConfig.psm1') -Force

$config = Import-LabConfig -Path $ConfigPath -Required Domain, OUs, Laps
$domain = Assert-LabDomain -Config $config
$laps = $config.Laps
$targetOU = Get-LabOUPath -Config $config -DomainDN $domain.DistinguishedName -Name $laps.TargetOU
$groupsOU = Get-LabOUPath -Config $config -DomainDN $domain.DistinguishedName -Name $config.OUs.Groups
$readerGroup = $laps.ReaderGroup

# Schema: present once the msLAPS-Password attribute exists
$schemaNC = (Get-ADRootDSE).schemaNamingContext
if (Get-ADObject -SearchBase $schemaNC -Filter "lDAPDisplayName -eq 'msLAPS-Password'") {
    Write-Verbose 'Windows LAPS schema already present.'
}
elseif ($PSCmdlet.ShouldProcess('AD schema', 'Extend for Windows LAPS (irreversible)')) {
    Update-LapsADSchema -Confirm:$false
}

# Reader group and membership
$exists = [bool](Get-ADGroup -Filter "Name -eq '$readerGroup'")
if (-not $exists -and $PSCmdlet.ShouldProcess($readerGroup, "Create global group in $groupsOU")) {
    New-ADGroup -Name $readerGroup -GroupScope Global -Path $groupsOU
    $exists = $true
}
$current = @()
if ($exists) { $current = @(Get-ADGroupMember $readerGroup | Select-Object -ExpandProperty Name) }
$toAdd = @($laps.ReaderMembers | Where-Object { $_ -notin $current })
if ($toAdd -and $PSCmdlet.ShouldProcess($readerGroup, "Add members: $($toAdd -join ', ')")) {
    Add-ADGroupMember -Identity $readerGroup -Members $toAdd
}

# OU permissions (both cmdlets are safe to re-apply)
if ($PSCmdlet.ShouldProcess($targetOU, 'Allow computers to update their own LAPS password')) {
    Set-LapsADComputerSelfPermission -Identity $targetOU | Out-Null
}
if ($PSCmdlet.ShouldProcess($targetOU, "Grant $readerGroup read access to LAPS passwords")) {
    Set-LapsADReadPasswordPermission -Identity $targetOU -AllowedPrincipals "$($domain.NetBIOSName)\$readerGroup" | Out-Null
}

Find-LapsADExtendedRights -Identity $targetOU

# After the GPO has applied on a client (shows status, not the password):
#   Get-LapsADPassword -Identity <computer> | Format-List
