<#
.SYNOPSIS
    Least-privilege fixes on top of steps 01-07: delegated domain join, AGDLP for LAPS, LAPS policy.

.DESCRIPTION
    Values come from the configuration file (JoinDelegation and Laps sections).
    1. Creates the join account and lets it create computers in the target OU only.
    2. Sets ms-DS-MachineAccountQuota (default 10 per user) so ordinary users can't join computers.
    3. Converts the pre-AGDLP Global reader group to the Domain Local ReaderGroup in place.
       Same object and SID, so the OU permission and already-encrypted passwords stay valid.
    4. Sets the LAPS GPO values: password length, explicit post-authentication reset, and
       automatic account management, so LAPS manages an enabled account instead of the
       built-in Administrator, which Windows 11 disables.
    Every step checks the current state first. See docs/08-least-privilege.md for the tests.

.PARAMETER ConfigPath
    Environment configuration file. Defaults to config/lab.psd1.

.PARAMETER JoinAccountPassword
    Password for the join account if it needs creating. Prompted if omitted.

.EXAMPLE
    .\08-least-privilege.ps1 -WhatIf
#>
#Requires -Modules ActiveDirectory, GroupPolicy
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\lab.psd1'),
    [securestring]$JoinAccountPassword
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabConfig.psm1') -Force

$config = Import-LabConfig -Path $ConfigPath -Required Domain, OUs, Laps, JoinDelegation
$domain = Assert-LabDomain -Config $config
$domainDN = $domain.DistinguishedName
$netbios = $domain.NetBIOSName
$join = $config.JoinDelegation
$laps = $config.Laps

# --- 1. Delegated domain join ---
$accountOU = Get-LabOUPath -Config $config -DomainDN $domainDN -Name $join.AccountOU
$targetOU = Get-LabOUPath -Config $config -DomainDN $domainDN -Name $join.TargetOU

if (-not (Get-ADObject -Filter "DistinguishedName -eq '$accountOU'") -and
    $PSCmdlet.ShouldProcess($accountOU, 'Create OU')) {
    New-ADOrganizationalUnit -Name $join.AccountOU -Path (Get-LabOUPath -Config $config -DomainDN $domainDN)
}

if (-not (Get-ADUser -Filter "SamAccountName -eq '$($join.Account)'") -and
    $PSCmdlet.ShouldProcess($join.Account, "Create join account in $accountOU")) {
    if (-not $JoinAccountPassword) { $JoinAccountPassword = Read-Host "Password for $($join.Account)" -AsSecureString }
    New-ADUser -Name $join.Account -SamAccountName $join.Account -UserPrincipalName "$($join.Account)@$($domain.DNSRoot)" `
        -Path $accountOU -AccountPassword $JoinAccountPassword -Enabled $true `
        -Description "Joins computers to $($join.TargetOU) only. Not for interactive use."
}

# Create/delete computer objects in the OU, plus what a join writes on the computer it creates.
# No delegation cmdlet exists; dsacls is the scripted form of ADUC's Delegate Control wizard.
# Safe to re-apply: AD merges identical entries.
$principal = "$netbios\$($join.Account)"
$aces = @(
    @('/I:T', "${principal}:CCDC;computer")
    @('/I:S', "${principal}:CA;Reset Password;computer")
    @('/I:S', "${principal}:WP;Account Restrictions;computer")
    @('/I:S', "${principal}:WS;Validated write to DNS host name;computer")
    @('/I:S', "${principal}:WS;Validated write to service principal name;computer")
)
if ($PSCmdlet.ShouldProcess($targetOU, "Delegate computer join rights to $principal")) {
    foreach ($ace in $aces) {
        dsacls $targetOU $ace[0] /G $ace[1] | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "dsacls failed ($LASTEXITCODE) granting $($ace[1])" }
    }
}

# --- 2. Machine account quota ---
$quota = (Get-ADObject $domainDN -Properties 'ms-DS-MachineAccountQuota').'ms-DS-MachineAccountQuota'
if ($quota -eq $join.MachineAccountQuota) {
    Write-Verbose "ms-DS-MachineAccountQuota already $quota."
}
elseif ($PSCmdlet.ShouldProcess($domainDN, "Set ms-DS-MachineAccountQuota $quota -> $($join.MachineAccountQuota)")) {
    Set-ADObject $domainDN -Replace @{ 'ms-DS-MachineAccountQuota' = $join.MachineAccountQuota }
}

# --- 3. AGDLP: convert the Global reader group to Domain Local in place ---
# Global -> Domain Local must go through Universal. Keeping the object keeps the SID.
$legacy = if ($laps.LegacyReaderGroup) { Get-ADGroup -Filter "Name -eq '$($laps.LegacyReaderGroup)'" }
if (-not $legacy) {
    Write-Verbose 'No legacy reader group to convert.'
}
elseif (Get-ADGroup -Filter "Name -eq '$($laps.ReaderGroup)'") {
    throw "Both $($laps.LegacyReaderGroup) and $($laps.ReaderGroup) exist; resolve manually before converting."
}
elseif ($PSCmdlet.ShouldProcess($legacy.DistinguishedName, "Convert to Domain Local and rename to $($laps.ReaderGroup)")) {
    Set-ADGroup -Identity $legacy.ObjectGUID -GroupScope Universal
    Set-ADGroup -Identity $legacy.ObjectGUID -GroupScope DomainLocal -SamAccountName $laps.ReaderGroup
    Rename-ADObject -Identity $legacy.ObjectGUID -NewName $laps.ReaderGroup
}

# --- 4. LAPS GPO values ---
# The same registry values GPMC writes, so GPMC still shows them as the LAPS settings. The
# automatic account management values need the Windows 11 24H2 / Server 2025 LAPS.admx; with an
# older template GPMC lists them under "Extra Registry Settings", but clients still apply them.
$policy = $laps.Policy
if (-not (Get-GPO -All | Where-Object DisplayName -eq $policy.GpoName)) {
    throw "GPO '$($policy.GpoName)' not found. Build it first (docs/07-windows-laps.md)."
}
$key = 'HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS'
$values = [ordered]@{
    BackupDirectory                         = 2   # Active Directory
    PasswordComplexity                      = $policy.PasswordComplexity
    PasswordLength                          = $policy.PasswordLength
    PasswordAgeDays                         = $policy.PasswordAgeDays
    ADPasswordEncryptionEnabled             = 1
    ADPasswordEncryptionPrincipal           = "$netbios\$($laps.ReaderGroup)"
    PostAuthenticationResetDelay            = $policy.PostAuthenticationResetDelay
    PostAuthenticationActions               = $policy.PostAuthenticationActions
    AutomaticAccountManagementEnabled       = 1
    AutomaticAccountManagementTarget        = 1   # new account, not the built-in Administrator
    AutomaticAccountManagementNameOrPrefix  = $policy.ManagedAccountName
    AutomaticAccountManagementEnableAccount = 1
    AutomaticAccountManagementRandomizeName = 0
}
foreach ($name in $values.Keys) {
    $value = $values[$name]
    $type = if ($value -is [string]) { 'String' } else { 'DWord' }
    $current = Get-GPRegistryValue -Name $policy.GpoName -Key $key -ValueName $name -ErrorAction SilentlyContinue
    if ($current -and "$($current.Value)" -eq "$value") { continue }
    if ($PSCmdlet.ShouldProcess("$($policy.GpoName): $name", "Set $type $value")) {
        Set-GPRegistryValue -Name $policy.GpoName -Key $key -ValueName $name -Type $type -Value $value | Out-Null
    }
}

if ($WhatIfPreference) { return }

(dsacls $targetOU) -match [regex]::Escape($principal)
Get-ADGroup $laps.ReaderGroup | Select-Object Name, GroupScope, SID
Get-GPRegistryValue -Name $policy.GpoName -Key $key | Select-Object ValueName, Value

# Then on each workstation, elevated: gpupdate /force; Invoke-LapsPolicyProcessing; Reset-LapsPassword
# The new length and account only take effect at the next rotation, hence the reset.
