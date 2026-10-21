<#
.SYNOPSIS
    Builds the first domain controller: static IP and hostname, AD DS forest with DNS, DNS forwarder.

.DESCRIPTION
    Values come from the configuration file (Domain and DomainController sections).
    Runs in three stages because the rename and the forest promotion each reboot the server.
    Every stage checks the current state first and only changes what is missing.

.PARAMETER Stage
    Network : static IP, DNS client and hostname (reboots if the name changes)
    Forest  : installs AD DS and promotes the server to a new forest (reboots)
    Post    : adds the DNS forwarder, sets the external time source, checks DC health

.PARAMETER ConfigPath
    Environment configuration file. Defaults to config/lab.psd1.

.PARAMETER DsrmPassword
    Directory Services Restore Mode password for the Forest stage. Prompted if omitted.

.EXAMPLE
    .\01-dc-setup.ps1 -Stage Network -WhatIf

.EXAMPLE
    .\01-dc-setup.ps1 -Stage Forest -ConfigPath ..\config\my-env.psd1
#>
#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Network', 'Forest', 'Post')]
    [string]$Stage,

    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\lab.psd1'),

    [securestring]$DsrmPassword
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabConfig.psm1') -Force

$config = Import-LabConfig -Path $ConfigPath -Required Domain, DomainController
$dc = $config.DomainController

switch ($Stage) {
    'Network' {
        $existing = Get-NetIPAddress -InterfaceAlias $dc.InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object IPAddress -eq $dc.IPAddress
        if ($existing) {
            Write-Verbose "IP $($dc.IPAddress) already set on $($dc.InterfaceAlias)."
        }
        elseif ($PSCmdlet.ShouldProcess($dc.InterfaceAlias, "Set static IP $($dc.IPAddress)/$($dc.PrefixLength), gateway $($dc.Gateway)")) {
            New-NetIPAddress -InterfaceAlias $dc.InterfaceAlias -IPAddress $dc.IPAddress `
                -PrefixLength $dc.PrefixLength -DefaultGateway $dc.Gateway | Out-Null
            # Temporary DNS until the server hosts its own zone
            Set-DnsClientServerAddress -InterfaceAlias $dc.InterfaceAlias -ServerAddresses $dc.Gateway
        }

        if ($env:COMPUTERNAME -ne $dc.ComputerName -and
            $PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Rename to $($dc.ComputerName) and restart")) {
            Rename-Computer -NewName $dc.ComputerName -Restart
        }
    }

    'Forest' {
        # DomainRole 4/5 = backup/primary domain controller
        if ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) {
            Write-Output 'Server is already a domain controller. Nothing to do.'
            return
        }
        if ((Get-WindowsFeature AD-Domain-Services).InstallState -ne 'Installed' -and
            $PSCmdlet.ShouldProcess('AD-Domain-Services', 'Install Windows feature')) {
            Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null
        }
        if ($PSCmdlet.ShouldProcess($config.Domain.Name, 'Create new forest with DNS (server will restart)')) {
            if (-not $DsrmPassword) {
                $DsrmPassword = Read-Host 'DSRM (Safe Mode Administrator) password' -AsSecureString
            }
            Install-ADDSForest -DomainName $config.Domain.Name -DomainNetbiosName $config.Domain.NetBIOS `
                -InstallDns -SafeModeAdministratorPassword $DsrmPassword -Force
        }
    }

    'Post' {
        $forwarders = @((Get-DnsServerForwarder).IPAddress | ForEach-Object { $_.IPAddressToString })
        if ($forwarders -contains $dc.DnsForwarder) {
            Write-Verbose "Forwarder $($dc.DnsForwarder) already configured."
        }
        elseif ($PSCmdlet.ShouldProcess('DNS Server', "Add forwarder $($dc.DnsForwarder)")) {
            Add-DnsServerForwarder -IPAddress $dc.DnsForwarder
        }

        # The PDC emulator is the time source for the whole forest. An emulated VM's clock drifts,
        # and more than 5 minutes of skew breaks Kerberos, so sync from an external NTP server.
        $peer = "$($dc.NtpServer),0x8"
        $configured = @(w32tm /query /configuration) -match "NtpServer:\s*$([regex]::Escape($dc.NtpServer))"
        if ($configured) {
            Write-Verbose "Time source $($dc.NtpServer) already configured."
        }
        elseif ($PSCmdlet.ShouldProcess('W32Time', "Sync from $($dc.NtpServer)")) {
            w32tm /config /manualpeerlist:$peer /syncfromflags:manual /reliable:yes /update | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "w32tm /config failed ($LASTEXITCODE)" }
            Restart-Service W32Time
            w32tm /resync /rediscover | Out-Null
        }

        # The DC must resolve through itself, not the gateway, or it can't register its SRV records
        $dns = (Get-DnsClientServerAddress -InterfaceAlias $dc.InterfaceAlias -AddressFamily IPv4).ServerAddresses
        if ($dns -contains $dc.Gateway) {
            Write-Warning "$($dc.ComputerName) still uses $($dc.Gateway) for DNS. Point it at itself ($($dc.IPAddress) or 127.0.0.1)."
        }

        Get-ADDomain | Select-Object DNSRoot, NetBIOSName, DomainMode
        Get-Service ADWS, KDC, Netlogon, DNS | Select-Object Name, Status
        w32tm /query /source
    }
}
