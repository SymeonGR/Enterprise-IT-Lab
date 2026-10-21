#Requires -RunAsAdministrator
#Requires -Modules GroupPolicy
<#
.SYNOPSIS
    USR - Sales Restrictions: block Control Panel / Settings for GG_Sales only. Run on DC01.
.DESCRIPTION
    Safe to re-run. Fails loudly if the security filtering doesn't end up as intended, instead
    of leaving a GPO that applies to every user (see docs/05, "Issues and resolutions").
.EXAMPLE
    .\05-gpo-sales-restrictions.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

$gpo    = 'USR - Sales Restrictions'
$target = 'OU=Users,OU=LAB,DC=corp,DC=internal'

if (-not (Get-GPO -Name $gpo -ErrorAction SilentlyContinue)) {
    if ($PSCmdlet.ShouldProcess($gpo, 'Create GPO')) {
        New-GPO -Name $gpo | Out-Null
    }
}

if ((Get-GPInheritance -Target $target).GpoLinks.DisplayName -contains $gpo) {
    Write-Host "Already linked to $target"
}
elseif ($PSCmdlet.ShouldProcess($target, "Link $gpo")) {
    New-GPLink -Name $gpo -Target $target | Out-Null
}

# = User Configuration > Administrative Templates > Control Panel >
#   Prohibit access to Control Panel and PC settings
if ($PSCmdlet.ShouldProcess($gpo, 'Set NoControlPanel = 1')) {
    Set-GPRegistryValue -Name $gpo `
      -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
      -ValueName "NoControlPanel" -Type DWord -Value 1 | Out-Null
}

# Security filtering: GG_Sales gets Apply; Authenticated Users keep Read only (MS16-072)
if ($PSCmdlet.ShouldProcess($gpo, 'GG_Sales = GpoApply, Authenticated Users = GpoRead')) {
    Set-GPPermission -Name $gpo -TargetName "GG_Sales" -TargetType Group -PermissionLevel GpoApply -Replace | Out-Null
    Set-GPPermission -Name $gpo -TargetName "Authenticated Users" -TargetType Group -PermissionLevel GpoRead -Replace | Out-Null
}

# Verify: expect GG_Sales = GpoApply, Authenticated Users = GpoRead
if (-not $WhatIfPreference) {
    $perms = Get-GPPermission -Name $gpo -All
    $expected = @{ 'GG_Sales' = 'GpoApply'; 'Authenticated Users' = 'GpoRead' }
    foreach ($trustee in $expected.Keys) {
        $actual = ($perms | Where-Object { $_.Trustee.Name -eq $trustee }).Permission
        if ("$actual" -ne $expected[$trustee]) {
            throw "$trustee has '$actual' on '$gpo', expected $($expected[$trustee])"
        }
    }
    $perms | Format-Table @{ n = 'Trustee'; e = { $_.Trustee.Name } }, Permission -AutoSize
}
