<#
.SYNOPSIS
    Creates a user GPO that blocks Control Panel and Settings, applied to one group only.

.DESCRIPTION
    Values come from the configuration file (SalesRestrictionsGpo section).
    Creates and links the GPO only if missing, sets the policy value, and applies security
    filtering so only the target group gets Apply. Authenticated Users keep Read (not Apply):
    since MS16-072 user GPOs are read in the computer's context, and without Read the GPO
    applies to nobody. Ends by checking the permissions and stops if they aren't exactly that,
    rather than leaving a GPO that applies to every user (docs/05, "Issues and resolutions").

.PARAMETER ConfigPath
    Environment configuration file. Defaults to config/lab.psd1.

.EXAMPLE
    .\05-gpo-sales-restrictions.ps1 -WhatIf
#>
#Requires -Modules GroupPolicy, ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\lab.psd1')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabConfig.psm1') -Force

$config = Import-LabConfig -Path $ConfigPath -Required Domain, OUs, SalesRestrictionsGpo
$domain = Assert-LabDomain -Config $config
$settings = $config.SalesRestrictionsGpo
$gpoName = $settings.Name
$targetOU = Get-LabOUPath -Config $config -DomainDN $domain.DistinguishedName -Name $settings.TargetOU

if (-not (Get-GPO -All | Where-Object DisplayName -eq $gpoName) -and
    $PSCmdlet.ShouldProcess($gpoName, 'Create GPO')) {
    New-GPO -Name $gpoName | Out-Null
}

$linked = (Get-GPInheritance -Target $targetOU).GpoLinks | Where-Object DisplayName -eq $gpoName
if (-not $linked -and $PSCmdlet.ShouldProcess($targetOU, "Link $gpoName")) {
    New-GPLink -Name $gpoName -Target $targetOU | Out-Null
}

# User Configuration > Administrative Templates > Control Panel >
# Prohibit access to Control Panel and PC settings
if ($PSCmdlet.ShouldProcess($gpoName, 'Set NoControlPanel = 1')) {
    Set-GPRegistryValue -Name $gpoName `
        -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
        -ValueName 'NoControlPanel' -Type DWord -Value 1 | Out-Null
}

# Security filtering
if ($PSCmdlet.ShouldProcess($gpoName, "Apply to $($settings.ApplyGroup) only; Authenticated Users Read")) {
    Set-GPPermission -Name $gpoName -TargetName $settings.ApplyGroup -TargetType Group -PermissionLevel GpoApply | Out-Null
    Set-GPPermission -Name $gpoName -TargetName 'Authenticated Users' -TargetType Group -PermissionLevel GpoRead -Replace | Out-Null
}

if ($WhatIfPreference) { return }

$expected = @{ $settings.ApplyGroup = 'GpoApply'; 'Authenticated Users' = 'GpoRead' }
$perms = Get-GPPermission -Name $gpoName -All | Where-Object { $_.Trustee.Name -in $expected.Keys }
foreach ($trustee in $expected.Keys) {
    $actual = ($perms | Where-Object { $_.Trustee.Name -eq $trustee }).Permission
    if ("$actual" -ne $expected[$trustee]) {
        throw "$trustee has '$actual' on '$gpoName', expected $($expected[$trustee])."
    }
}
$perms | Select-Object @{ n = 'Trustee'; e = { $_.Trustee.Name } }, Permission
