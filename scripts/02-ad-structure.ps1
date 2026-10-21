#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    OUs, computer redirection, users and groups for corp.internal. Run on DC01.
.DESCRIPTION
    Existing objects are skipped, so re-running against the live lab is safe.
.EXAMPLE
    .\02-ad-structure.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

$domainDn = 'DC=corp,DC=internal'
$base     = "OU=LAB,$domainDn"

# --- OUs ---
$ous = @(
    @{ Name = 'LAB'; Path = $domainDn }
    'Users', 'Groups', 'Workstations', 'Servers' | ForEach-Object { @{ Name = $_; Path = $base } }
)
foreach ($ou in $ous) {
    $dn = "OU=$($ou.Name),$($ou.Path)"
    if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'") {
        Write-Host "OU exists: $dn"
    }
    elseif ($PSCmdlet.ShouldProcess($dn, 'Create OU')) {
        New-ADOrganizationalUnit -Name $ou.Name -Path $ou.Path
    }
}

# --- New computers land in OU=Workstations, not CN=Computers ---
$wsOu = "OU=Workstations,$base"
if ((Get-ADDomain).ComputersContainer -eq $wsOu) {
    Write-Host "Computers already redirected to $wsOu"
}
elseif ($PSCmdlet.ShouldProcess($wsOu, 'Redirect default computer container (redircmp)')) {
    redircmp $wsOu
    if ($LASTEXITCODE) { throw "redircmp failed ($LASTEXITCODE)" }
}

# --- Users ---
# No -ChangePasswordAtLogon: the test users sign in over RDP with NLA, which cannot
# change an expired password. In production, force the change at first sign-in.
$missing = 'nikos', 'maria', 'giorgos' | Where-Object { -not (Get-ADUser -Filter "SamAccountName -eq '$_'") }
if ($missing) {
    $pw = if (-not $WhatIfPreference) { Read-Host 'Password for lab users' -AsSecureString }
    foreach ($u in $missing) {
        if ($PSCmdlet.ShouldProcess($u, 'Create user')) {
            New-ADUser -Name $u -SamAccountName $u -UserPrincipalName "$u@corp.internal" `
              -Path "OU=Users,$base" -AccountPassword $pw -Enabled $true
        }
    }
}

# --- Groups ---
$groups = [ordered]@{
    GG_IT    = @('nikos')
    GG_Sales = @('maria', 'giorgos')
}
foreach ($g in $groups.Keys) {
    if (-not (Get-ADGroup -Filter "Name -eq '$g'")) {
        if ($PSCmdlet.ShouldProcess($g, 'Create global security group')) {
            New-ADGroup -Name $g -GroupScope Global -GroupCategory Security -Path "OU=Groups,$base"
        }
    }
    if ($PSCmdlet.ShouldProcess($g, "Add members: $($groups[$g] -join ', ')")) {
        Add-ADGroupMember -Identity $g -Members $groups[$g]
    }
}

# --- Verify ---
if (-not $WhatIfPreference) {
    Get-ADUser -Filter * -SearchBase $base | Format-Table Name, Enabled -AutoSize
    foreach ($g in $groups.Keys) {
        "$g : " + ((Get-ADGroupMember -Identity $g).Name -join ', ')
    }
}
