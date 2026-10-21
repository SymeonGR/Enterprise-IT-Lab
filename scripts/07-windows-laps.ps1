#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory, LAPS
<#
.SYNOPSIS
    Windows LAPS: schema, permissions and reader group. Run on DC01.
.DESCRIPTION
    The GPO "WS - LAPS" was configured in GPMC (see docs/07-windows-laps.md); step 08 sets
    the hardened values by script. Safe to re-run.
.EXAMPLE
    .\07-windows-laps.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

$ou       = "OU=Workstations,OU=LAB,DC=corp,DC=internal"
$groupsOu = "OU=Groups,OU=LAB,DC=corp,DC=internal"

# Password encryption requires domain functional level 2016 or later
$mode = (Get-ADDomain).DomainMode
if ($mode -lt [Microsoft.ActiveDirectory.Management.ADDomainMode]::Windows2016Domain) {
    throw "Domain functional level is $mode; LAPS password encryption needs Windows2016Domain or later"
}

# One-time and irreversible: back up the DC first
$schemaNc = (Get-ADRootDSE).schemaNamingContext
if (Get-ADObject -SearchBase $schemaNc -Filter "lDAPDisplayName -eq 'msLAPS-EncryptedPassword'") {
    Write-Host 'Schema already has the Windows LAPS attributes'
}
elseif ($PSCmdlet.ShouldProcess('AD schema', 'Add Windows LAPS attributes (irreversible)')) {
    Update-LapsADSchema -Verbose
}

# Step 08 converts GG_LAPS_Readers to DL_LAPS_Readers (same object and SID); use the new name if so
$readers = if (Get-ADGroup -Filter "Name -eq 'DL_LAPS_Readers'") { 'DL_LAPS_Readers' } else { 'GG_LAPS_Readers' }
if (-not (Get-ADGroup -Filter "Name -eq '$readers'")) {
    if ($PSCmdlet.ShouldProcess($readers, 'Create security group')) {
        New-ADGroup -Name $readers -GroupScope Global -GroupCategory Security -Path $groupsOu
    }
}
if ($PSCmdlet.ShouldProcess($readers, 'Add members: GG_IT, Domain Admins')) {
    Add-ADGroupMember -Identity $readers -Members GG_IT, "Domain Admins"
}

# Computers may write their own password; the reader group may read it - Workstations OU only
if ($PSCmdlet.ShouldProcess($ou, "Grant self-write to computers, read to CORP\$readers")) {
    Set-LapsADComputerSelfPermission -Identity $ou | Out-Null
    Set-LapsADReadPasswordPermission -Identity $ou -AllowedPrincipals "CORP\$readers" | Out-Null
}

# Who else holds "All extended rights" on the OU? Expect only built-in admin principals.
Find-LapsADExtendedRights -Identity $ou

# Verify after the GPO has applied on WS01 (does not reveal the password):
# Get-LapsADPassword -Identity WS01 | Format-List
