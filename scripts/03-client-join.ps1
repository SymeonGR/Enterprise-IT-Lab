<#
.SYNOPSIS
    Points a Windows client at the domain's DNS, runs pre-flight checks and joins the domain.

.DESCRIPTION
    Values come from the configuration file (Domain and Client sections).
    Exits early if the machine is already joined to the domain. The join runs only if the
    DC locator SRV record resolves and nltest finds a domain controller.

.PARAMETER ConfigPath
    Environment configuration file. Defaults to config/lab.psd1.

.PARAMETER ComputerName
    Overrides Client.ComputerName, e.g. when joining a second workstation.

.PARAMETER Credential
    Account allowed to join computers to the domain. Prompted if omitted, pre-filled with
    Client.JoinAccount (the delegated account from step 08) when the configuration sets it.

.EXAMPLE
    .\03-client-join.ps1 -WhatIf

.EXAMPLE
    .\03-client-join.ps1 -ComputerName WS02
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\lab.psd1'),
    [string]$ComputerName,
    [pscredential]$Credential
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabConfig.psm1') -Force

$config = Import-LabConfig -Path $ConfigPath -Required Domain, Client
$domainName = $config.Domain.Name
$client = $config.Client
if ($ComputerName) { $client.ComputerName = $ComputerName }

$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.PartOfDomain -and $cs.Domain -eq $domainName) {
    Write-Output "$($cs.Name) is already joined to $domainName. Nothing to do."
    return
}

$currentDns = (Get-DnsClientServerAddress -InterfaceAlias $client.InterfaceAlias -AddressFamily IPv4).ServerAddresses
if ($currentDns -notcontains $client.DnsServer -and
    $PSCmdlet.ShouldProcess($client.InterfaceAlias, "Set DNS server to $($client.DnsServer)")) {
    Set-DnsClientServerAddress -InterfaceAlias $client.InterfaceAlias -ServerAddresses $client.DnsServer
    Clear-DnsClientCache
}

# Pre-flight: the join uses the client's own DNS to find a DC
try {
    Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.$domainName" -Type SRV | Out-Null
}
catch {
    throw "DC locator SRV record for $domainName not resolvable via $($client.DnsServer). Check client DNS. $_"
}
nltest /dsgetdc:$domainName | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "nltest could not locate a domain controller for $domainName."
}

if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Join $domainName as $($client.ComputerName) and restart")) {
    if (-not $Credential) {
        $prompt = @{ Message = "Account allowed to join computers to $domainName" }
        if ($client.JoinAccount) { $prompt.UserName = $client.JoinAccount }
        $Credential = Get-Credential @prompt
    }
    $joinParams = @{ DomainName = $domainName; Credential = $Credential; Restart = $true }
    if ($env:COMPUTERNAME -ne $client.ComputerName) { $joinParams.NewName = $client.ComputerName }
    Add-Computer @joinParams
}
