<#
.SYNOPSIS
    Creates the "USR - Sales Restrictions" GPO: Control Panel and Settings blocked, Sales only.

.DESCRIPTION
    Creates and links the GPO only if missing, sets the policy value, and applies security
    filtering so only the target group gets Apply. Authenticated Users keep Read (not Apply):
    since MS16-072 user GPOs are read in the computer's context, and without Read the GPO
    applies to nobody. Ends by printing the permissions for verification.

.EXAMPLE
    .\05-gpo-sales-restrictions.ps1 -WhatIf
    .\05-gpo-sales-restrictions.ps1 -Verbose
#>
#Requires -Modules GroupPolicy, ActiveDirectory
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GpoName = 'USR - Sales Restrictions',
    [string]$TargetOU = "OU=Users,OU=LAB,$((Get-ADDomain).DistinguishedName)",
    [string]$ApplyGroup = 'GG_Sales'
)

$ErrorActionPreference = 'Stop'

$gpo = Get-GPO -All | Where-Object DisplayName -eq $GpoName
if (-not $gpo -and $PSCmdlet.ShouldProcess($GpoName, 'Create GPO')) {
    $gpo = New-GPO -Name $GpoName
}

$linked = (Get-GPInheritance -Target $TargetOU).GpoLinks | Where-Object DisplayName -eq $GpoName
if (-not $linked -and $PSCmdlet.ShouldProcess($TargetOU, "Link $GpoName")) {
    New-GPLink -Name $GpoName -Target $TargetOU | Out-Null
}

# User Configuration > Administrative Templates > Control Panel >
# Prohibit access to Control Panel and PC settings
if ($PSCmdlet.ShouldProcess($GpoName, 'Set NoControlPanel = 1')) {
    Set-GPRegistryValue -Name $GpoName `
        -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
        -ValueName 'NoControlPanel' -Type DWord -Value 1 | Out-Null
}

# Security filtering
if ($PSCmdlet.ShouldProcess($GpoName, "Apply to $ApplyGroup only; Authenticated Users Read")) {
    Set-GPPermission -Name $GpoName -TargetName $ApplyGroup -TargetType Group -PermissionLevel GpoApply | Out-Null
    Set-GPPermission -Name $GpoName -TargetName 'Authenticated Users' -TargetType Group -PermissionLevel GpoRead -Replace | Out-Null
}

Get-GPPermission -Name $GpoName -All |
    Where-Object { $_.Trustee.Name -in @($ApplyGroup, 'Authenticated Users') } |
    Select-Object @{ n = 'Trustee'; e = { $_.Trustee.Name } }, Permission
