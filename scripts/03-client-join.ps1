<#
.SYNOPSIS
    Points a Windows 11 client at the DC, runs pre-flight checks and joins it to the domain.

.DESCRIPTION
    Exits early if the machine is already domain-joined. The join only runs if DNS can
    resolve the domain's DC locator SRV record and nltest finds a domain controller.

.EXAMPLE
    .\03-client-join.ps1 -WhatIf
    .\03-client-join.ps1 -NewName WS01
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$DomainName = 'corp.internal',
    [ipaddress]$DnsServer = '192.168.64.10',
    [string]$InterfaceAlias = 'Ethernet',
    [string]$NewName = 'WS01',
    [pscredential]$Credential
)

$ErrorActionPreference = 'Stop'

$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.PartOfDomain -and $cs.Domain -eq $DomainName) {
    Write-Output "$($cs.Name) is already joined to $DomainName."
    return
}

$currentDns = (Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4).ServerAddresses
if ($currentDns -notcontains $DnsServer.IPAddressToString -and
    $PSCmdlet.ShouldProcess($InterfaceAlias, "Set DNS server to $DnsServer")) {
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DnsServer.IPAddressToString
    Clear-DnsClientCache
}

# Pre-flight: the join uses the client's own DNS to find a DC
try {
    Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$DomainName" -Type SRV | Out-Null
}
catch {
    throw "DC locator SRV record not resolvable via $DnsServer. Check client DNS before joining. $_"
}
nltest /dsgetdc:$DomainName | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "nltest could not locate a domain controller for $DomainName."
}

if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Join $DomainName as $NewName and restart")) {
    if (-not $Credential) { $Credential = Get-Credential -Message "Account allowed to join computers to $DomainName" }
    $joinParams = @{ DomainName = $DomainName; Credential = $Credential; Restart = $true }
    if ($env:COMPUTERNAME -ne $NewName) { $joinParams.NewName = $NewName }
    Add-Computer @joinParams
}
