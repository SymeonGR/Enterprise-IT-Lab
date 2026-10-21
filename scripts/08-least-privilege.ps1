#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory, GroupPolicy
<#
.SYNOPSIS
    Least-privilege fixes on top of steps 01-07. Run on DC01.
.DESCRIPTION
    1. Delegated domain join: svc-domainjoin may create computers in OU=Workstations only.
    2. ms-DS-MachineAccountQuota = 0: ordinary users can no longer join computers.
    3. AGDLP: GG_LAPS_Readers becomes the Domain Local group DL_LAPS_Readers. Same object and
       SID, so the OU permission and already-encrypted passwords stay valid.
    4. WS - LAPS hardened by script: 20-character passwords, explicit post-authentication
       reset, and a LAPS-created local admin account (Windows 11 24H2+) that can be used to
       sign in, instead of the disabled built-in Administrator.

    Safe to re-run. See docs/08-least-privilege.md for the tests to run afterwards.
.EXAMPLE
    .\08-least-privilege.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

$domainDn = 'DC=corp,DC=internal'
$base     = "OU=LAB,$domainDn"
$wsOu     = "OU=Workstations,$base"
$svcOu    = "OU=Service Accounts,$base"
$joinUser = 'svc-domainjoin'

# --- 1. Delegated domain join ---
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$svcOu'")) {
    if ($PSCmdlet.ShouldProcess($svcOu, 'Create OU')) {
        New-ADOrganizationalUnit -Name 'Service Accounts' -Path $base
    }
}

if (-not (Get-ADUser -Filter "SamAccountName -eq '$joinUser'")) {
    if ($PSCmdlet.ShouldProcess($joinUser, 'Create domain join account')) {
        $pw = Read-Host "Password for $joinUser" -AsSecureString
        New-ADUser -Name $joinUser -SamAccountName $joinUser -UserPrincipalName "$joinUser@corp.internal" `
          -Path $svcOu -AccountPassword $pw -Enabled $true `
          -Description 'Joins computers to OU=Workstations only. Not for interactive use.'
    }
}

# Create/delete computer objects in the OU, plus the rights a join needs on the computer it creates
$aces = @(
    @('/I:T', "CORP\${joinUser}:CCDC;computer")
    @('/I:S', "CORP\${joinUser}:CA;Reset Password;computer")
    @('/I:S', "CORP\${joinUser}:WP;Account Restrictions;computer")
    @('/I:S', "CORP\${joinUser}:WS;Validated write to DNS host name;computer")
    @('/I:S', "CORP\${joinUser}:WS;Validated write to service principal name;computer")
)
if ($PSCmdlet.ShouldProcess($wsOu, "Delegate computer join rights to CORP\$joinUser")) {
    foreach ($ace in $aces) {
        dsacls $wsOu $ace[0] /G $ace[1] | Out-Null
        if ($LASTEXITCODE) { throw "dsacls failed ($LASTEXITCODE) granting $($ace[1])" }
    }
}

# --- 2. Stop ordinary users from joining computers (default quota is 10 per user) ---
$quota = (Get-ADObject $domainDn -Properties 'ms-DS-MachineAccountQuota').'ms-DS-MachineAccountQuota'
if ($quota -eq 0) {
    Write-Host 'ms-DS-MachineAccountQuota already 0'
}
elseif ($PSCmdlet.ShouldProcess($domainDn, "Set ms-DS-MachineAccountQuota $quota -> 0")) {
    Set-ADObject $domainDn -Replace @{ 'ms-DS-MachineAccountQuota' = 0 }
}

# --- 3. AGDLP: the group that holds the permission is Domain Local ---
# Global -> Domain Local must go through Universal. Renaming keeps the SID, so the ACL on
# OU=Workstations and passwords already encrypted to this group keep working.
$old = Get-ADGroup -Filter "Name -eq 'GG_LAPS_Readers'"
if (-not $old) {
    Write-Host 'GG_LAPS_Readers already converted (or not created yet - run step 07 first)'
}
elseif ($PSCmdlet.ShouldProcess($old.DistinguishedName, 'Convert to Domain Local, rename to DL_LAPS_Readers')) {
    Set-ADGroup -Identity $old.ObjectGUID -GroupScope Universal
    Set-ADGroup -Identity $old.ObjectGUID -GroupScope DomainLocal -SamAccountName 'DL_LAPS_Readers'
    Rename-ADObject -Identity $old.ObjectGUID -NewName 'DL_LAPS_Readers'
}

# --- 4. WS - LAPS policy values ---
# Same registry values the GPMC settings write, so GPMC shows them as the normal LAPS settings.
# The automatic account management settings need the Windows 11 24H2 / Server 2025 LAPS.admx;
# with an older template GPMC lists them under "Extra Registry Settings", but they still apply.
$gpo = 'WS - LAPS'
$key = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'
$dword = [ordered]@{
    BackupDirectory                         = 2   # Active Directory
    PasswordComplexity                      = 4   # large + small letters + numbers + specials
    PasswordLength                          = 20
    PasswordAgeDays                         = 30
    ADPasswordEncryptionEnabled             = 1
    PostAuthenticationResetDelay            = 8   # hours after a sign-in with the managed account
    PostAuthenticationActions               = 3   # reset password and sign out
    AutomaticAccountManagementEnabled       = 1
    AutomaticAccountManagementTarget        = 1   # new custom account, not the built-in Administrator
    AutomaticAccountManagementEnableAccount = 1
    AutomaticAccountManagementRandomizeName = 0
}
$string = [ordered]@{
    ADPasswordEncryptionPrincipal           = 'CORP\DL_LAPS_Readers'
    AutomaticAccountManagementNameOrPrefix  = 'lapsadmin'
}

if (-not (Get-GPO -Name $gpo -ErrorAction SilentlyContinue)) {
    throw "GPO '$gpo' not found - build it first (docs/07-windows-laps.md)"
}
foreach ($name in $dword.Keys) {
    if ($PSCmdlet.ShouldProcess("$gpo : $name", "Set DWORD $($dword[$name])")) {
        Set-GPRegistryValue -Name $gpo -Key $key -ValueName $name -Type DWord -Value $dword[$name] | Out-Null
    }
}
foreach ($name in $string.Keys) {
    if ($PSCmdlet.ShouldProcess("$gpo : $name", "Set String '$($string[$name])'")) {
        Set-GPRegistryValue -Name $gpo -Key $key -ValueName $name -Type String -Value $string[$name] | Out-Null
    }
}

# --- Verify ---
if (-not $WhatIfPreference) {
    dsacls $wsOu | Select-String $joinUser
    Get-ADGroup DL_LAPS_Readers | Format-Table Name, GroupScope, SID -AutoSize
    Get-GPRegistryValue -Name $gpo -Key $key | Format-Table ValueName, Value -AutoSize
}

# Then on WS01, elevated: gpupdate /force; Invoke-LapsPolicyProcessing; Reset-LapsPassword
# The new length and account only take effect at the next rotation, hence the reset.
