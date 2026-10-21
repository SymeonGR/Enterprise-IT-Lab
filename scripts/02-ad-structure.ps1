<#
.SYNOPSIS
    Creates the OU structure, computer redirection, users and groups defined in the configuration.

.DESCRIPTION
    Idempotent: each object is created only if it does not already exist, and group membership
    is only added where missing. Stops if the configuration is for a different domain.

.PARAMETER ConfigPath
    Environment configuration file. Defaults to config/lab.psd1.

.PARAMETER RootOU
    Overrides OUs.Root from the configuration (e.g. to build a throw-away test tree).

.PARAMETER Groups
    Overrides the Groups section: hashtable of group name = member sAMAccountNames.

.PARAMETER UserPassword
    Initial password for users that need creating. Prompted only if a user is missing.

.EXAMPLE
    .\02-ad-structure.ps1 -WhatIf

.EXAMPLE
    .\02-ad-structure.ps1 -RootOU TEST -Groups @{ 'GG_Test' = @('testuser') } -Verbose
#>
#Requires -Modules ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\lab.psd1'),
    [string]$RootOU,
    [hashtable]$Groups,
    [securestring]$UserPassword
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabConfig.psm1') -Force

$config = Import-LabConfig -Path $ConfigPath -Required Domain, OUs, Groups
if ($RootOU) { $config.OUs.Root = $RootOU }
if ($Groups) { $config.Groups = $Groups }

$domain = Assert-LabDomain -Config $config
$domainDN = $domain.DistinguishedName
$rootDN = Get-LabOUPath -Config $config -DomainDN $domainDN

function Test-ADObject([string]$DistinguishedName) {
    [bool](Get-ADObject -Filter "DistinguishedName -eq '$DistinguishedName'")
}

# OUs
if (-not (Test-ADObject $rootDN) -and $PSCmdlet.ShouldProcess($rootDN, 'Create OU')) {
    New-ADOrganizationalUnit -Name $config.OUs.Root -Path $domainDN
}
foreach ($ou in $config.OUs.Children) {
    $dn = Get-LabOUPath -Config $config -DomainDN $domainDN -Name $ou
    if (-not (Test-ADObject $dn) -and $PSCmdlet.ShouldProcess($dn, 'Create OU')) {
        New-ADOrganizationalUnit -Name $ou -Path $rootDN
    }
}

# Default container for new computer accounts (only for the main tree, not a -RootOU test tree)
if (-not $RootOU) {
    $computersDN = Get-LabOUPath -Config $config -DomainDN $domainDN -Name $config.OUs.Computers
    if ($domain.ComputersContainer -ne $computersDN -and
        $PSCmdlet.ShouldProcess($computersDN, 'Redirect default computer container')) {
        redircmp $computersDN | Out-Null
    }
}

# Users
$usersDN = Get-LabOUPath -Config $config -DomainDN $domainDN -Name $config.OUs.Users
$allUsers = $config.Groups.Values | ForEach-Object { $_ } | Sort-Object -Unique
foreach ($user in $allUsers) {
    if (Get-ADUser -Filter "SamAccountName -eq '$user'") { continue }
    if ($PSCmdlet.ShouldProcess($user, "Create user in $usersDN")) {
        if (-not $UserPassword) { $UserPassword = Read-Host 'Initial password for new users' -AsSecureString }
        New-ADUser -Name $user -SamAccountName $user -UserPrincipalName "$user@$($domain.DNSRoot)" `
            -Path $usersDN -AccountPassword $UserPassword -Enabled $true
    }
}

# Groups and membership
$groupsDN = Get-LabOUPath -Config $config -DomainDN $domainDN -Name $config.OUs.Groups
foreach ($group in $config.Groups.Keys) {
    $exists = [bool](Get-ADGroup -Filter "Name -eq '$group'")
    if (-not $exists -and $PSCmdlet.ShouldProcess($group, "Create global group in $groupsDN")) {
        New-ADGroup -Name $group -GroupScope Global -Path $groupsDN
        $exists = $true
    }
    $current = @()
    if ($exists) { $current = @(Get-ADGroupMember $group | Select-Object -ExpandProperty SamAccountName) }
    $toAdd = @($config.Groups[$group] | Where-Object { $_ -notin $current })
    if ($toAdd -and $PSCmdlet.ShouldProcess($group, "Add members: $($toAdd -join ', ')")) {
        Add-ADGroupMember -Identity $group -Members $toAdd
    }
}

Get-ADUser -Filter * -SearchBase $rootDN | Select-Object Name, Enabled
