#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Point the Windows 11 Pro client at DC01 and join it to corp.internal as WS01.
.DESCRIPTION
    Run on the client. The pre-flight checks must pass, otherwise the script stops before joining.
.PARAMETER JoinAccount
    Account used for the join. WS01 was originally joined with CORP\Administrator; once step 08
    has delegated join rights, use CORP\svc-domainjoin.
.EXAMPLE
    .\03-client-join.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$InterfaceAlias = 'Ethernet',
    [string]$NewName = 'WS01',
    [string]$JoinAccount = 'CORP\svc-domainjoin'
)

$ErrorActionPreference = 'Stop'

$dc     = '192.168.64.10'
$domain = 'corp.internal'

if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
    Write-Host "Already joined to $((Get-CimInstance Win32_ComputerSystem).Domain)"
    return
}

# The join finds the domain through the client's own DNS, so it must use DC01
if ($PSCmdlet.ShouldProcess($InterfaceAlias, "Set DNS server $dc")) {
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $dc
    Clear-DnsClientCache
}

# Pre-flight: both must succeed before joining. Skipped under -WhatIf, where DNS wasn't changed.
if ($WhatIfPreference) {
    Write-Host 'Skipping pre-flight checks (-WhatIf): client DNS was not changed'
}
else {
    Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 | Format-Table InterfaceAlias, ServerAddresses -AutoSize
    Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$domain" -Type SRV | Format-Table Name, NameTarget, Port -AutoSize
    nltest /dsgetdc:$domain
    if ($LASTEXITCODE) { throw "nltest could not locate a domain controller for $domain" }
}

if ($PSCmdlet.ShouldProcess($domain, "Join as $NewName using $JoinAccount and restart")) {
    $join = @{
        DomainName = $domain
        Credential = Get-Credential -UserName $JoinAccount -Message "Account to join $domain"
        Restart    = $true
    }
    if ($env:COMPUTERNAME -ne $NewName) { $join.NewName = $NewName }
    Add-Computer @join
}

# After reboot - the reboot alone doesn't prove the join worked:
# Get-CimInstance Win32_ComputerSystem | Select-Object Name, Domain, PartOfDomain
