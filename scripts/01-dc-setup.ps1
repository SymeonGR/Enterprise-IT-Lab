<#
.SYNOPSIS
    Builds DC01: static IP and hostname, AD DS forest with DNS, and a DNS forwarder.

.DESCRIPTION
    Runs in three stages because the rename and the forest promotion each reboot the server.
    Every stage checks the current state first and only changes what is missing, so it is safe to re-run.

.PARAMETER Stage
    Network : static IP, DNS client and hostname (reboots if the name changes)
    Forest  : installs AD DS and promotes the server to a new forest (reboots)
    Post    : adds the DNS forwarder and verifies the DC services

.EXAMPLE
    .\01-dc-setup.ps1 -Stage Network -WhatIf
    .\01-dc-setup.ps1 -Stage Network
    .\01-dc-setup.ps1 -Stage Forest
    .\01-dc-setup.ps1 -Stage Post
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Network', 'Forest', 'Post')]
    [string]$Stage,

    [string]$InterfaceAlias = 'Ethernet',
    [ipaddress]$IPAddress = '192.168.64.10',
    [ValidateRange(8, 30)]
    [int]$PrefixLength = 24,
    [ipaddress]$Gateway = '192.168.64.1',
    [string]$ComputerName = 'DC01',
    [string]$DomainName = 'corp.internal',
    [string]$NetbiosName = 'CORP',
    [ipaddress]$Forwarder = '192.168.64.1'
)

$ErrorActionPreference = 'Stop'

switch ($Stage) {
    'Network' {
        $existing = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object IPAddress -eq $IPAddress.IPAddressToString
        if ($existing) {
            Write-Verbose "IP $IPAddress already set on $InterfaceAlias."
        }
        elseif ($PSCmdlet.ShouldProcess($InterfaceAlias, "Set static IP $IPAddress/$PrefixLength, gateway $Gateway")) {
            New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $IPAddress.IPAddressToString `
                -PrefixLength $PrefixLength -DefaultGateway $Gateway.IPAddressToString | Out-Null
            # Temporary DNS until the server hosts its own zone
            Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $Gateway.IPAddressToString
        }

        if ($env:COMPUTERNAME -ne $ComputerName -and $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Rename to $ComputerName and restart")) {
            Rename-Computer -NewName $ComputerName -Restart
        }
    }

    'Forest' {
        # DomainRole 4/5 = backup/primary domain controller
        if ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) {
            Write-Verbose 'Server is already a domain controller.'
            return
        }
        if ((Get-WindowsFeature AD-Domain-Services).InstallState -ne 'Installed' -and
            $PSCmdlet.ShouldProcess('AD-Domain-Services', 'Install Windows feature')) {
            Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null
        }
        if ($PSCmdlet.ShouldProcess($DomainName, 'Create new forest with DNS (server will restart)')) {
            $dsrm = Read-Host 'DSRM (Safe Mode Administrator) password' -AsSecureString
            Install-ADDSForest -DomainName $DomainName -DomainNetbiosName $NetbiosName -InstallDns `
                -SafeModeAdministratorPassword $dsrm -Force
        }
    }

    'Post' {
        $forwarders = (Get-DnsServerForwarder).IPAddress.IPAddressToString
        if ($forwarders -contains $Forwarder.IPAddressToString) {
            Write-Verbose "Forwarder $Forwarder already configured."
        }
        elseif ($PSCmdlet.ShouldProcess('DNS Server', "Add forwarder $Forwarder")) {
            Add-DnsServerForwarder -IPAddress $Forwarder.IPAddressToString
        }

        Get-ADDomain | Select-Object DNSRoot, NetBIOSName
        Get-Service ADWS, KDC, Netlogon, DNS | Select-Object Name, Status
    }
}
