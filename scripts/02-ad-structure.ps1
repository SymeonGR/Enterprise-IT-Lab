<#
.SYNOPSIS
    Creates the lab OU structure, computer redirection, users and groups.

.DESCRIPTION
    Idempotent: each object is created only if it does not already exist, and group
    membership is only added where missing. Safe to re-run; use -WhatIf to preview.

.EXAMPLE
    .\02-ad-structure.ps1 -WhatIf
    .\02-ad-structure.ps1 -Verbose
#>
#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RootOU = 'LAB',
    [string[]]$ChildOUs = @('Users', 'Groups', 'Workstations', 'Servers'),

    # Group name => members
    [hashtable]$Groups = @{
        'GG_IT'    = @('nikos')
        'GG_Sales' = @('maria', 'giorgos')
    }
)

$ErrorActionPreference = 'Stop'

$domain = Get-ADDomain
$domainDN = $domain.DistinguishedName
$rootDN = "OU=$RootOU,$domainDN"

function Test-ADObject([string]$DistinguishedName) {
    [bool](Get-ADObject -Filter "DistinguishedName -eq '$DistinguishedName'")
}

# OUs
if (-not (Test-ADObject $rootDN) -and $PSCmdlet.ShouldProcess($rootDN, 'Create OU')) {
    New-ADOrganizationalUnit -Name $RootOU -Path $domainDN
}
foreach ($ou in $ChildOUs) {
    $dn = "OU=$ou,$rootDN"
    if (-not (Test-ADObject $dn) -and $PSCmdlet.ShouldProcess($dn, 'Create OU')) {
        New-ADOrganizationalUnit -Name $ou -Path $rootDN
    }
}

# New computer accounts go to Workstations instead of CN=Computers
$workstationsDN = "OU=Workstations,$rootDN"
if ($domain.ComputersContainer -ne $workstationsDN -and $PSCmdlet.ShouldProcess($workstationsDN, 'Redirect default computer container')) {
    redircmp $workstationsDN | Out-Null
}

# Users (one shared lab password, prompted only if a user needs creating)
$allUsers = $Groups.Values | ForEach-Object { $_ } | Sort-Object -Unique
$missingUsers = $allUsers | Where-Object { -not (Get-ADUser -Filter "SamAccountName -eq '$_'") }
if ($missingUsers) {
    $password = $null
    foreach ($user in $missingUsers) {
        if ($PSCmdlet.ShouldProcess($user, 'Create user')) {
            if (-not $password) { $password = Read-Host 'Password for new lab users' -AsSecureString }
            New-ADUser -Name $user -SamAccountName $user -UserPrincipalName "$user@$($domain.DNSRoot)" `
                -Path "OU=Users,$rootDN" -AccountPassword $password -Enabled $true
        }
    }
}

# Groups and membership
foreach ($group in $Groups.Keys) {
    if (-not (Get-ADGroup -Filter "Name -eq '$group'") -and $PSCmdlet.ShouldProcess($group, 'Create global group')) {
        New-ADGroup -Name $group -GroupScope Global -Path "OU=Groups,$rootDN"
    }
    $current = @()
    if (Get-ADGroup -Filter "Name -eq '$group'") {
        $current = Get-ADGroupMember $group | Select-Object -ExpandProperty SamAccountName
    }
    $toAdd = $Groups[$group] | Where-Object { $_ -notin $current }
    if ($toAdd -and $PSCmdlet.ShouldProcess($group, "Add members: $($toAdd -join ', ')")) {
        Add-ADGroupMember -Identity $group -Members $toAdd
    }
}

Get-ADUser -Filter * -SearchBase $rootDN | Select-Object Name, Enabled
