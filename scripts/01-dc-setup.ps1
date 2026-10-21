#Requires -RunAsAdministrator
<#
.SYNOPSIS
    DC01 setup: static IP, rename, AD DS forest, DNS forwarder, time source.
.DESCRIPTION
    Run on the server, one stage at a time. Network and Forest each end with a reboot.

      Network        static IP, DNS, rename to DC01             (reboots)
      Forest         AD DS role + new forest corp.internal      (reboots; take a VM backup first)
      PostPromotion  DNS forwarder, NTP, health checks          (sign in as CORP\Administrator)

    Each stage skips steps that are already done, so re-running it is safe.
.EXAMPLE
    .\01-dc-setup.ps1 -Stage Network -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Network', 'Forest', 'PostPromotion')]
    [string]$Stage,

    [string]$InterfaceAlias = 'Ethernet'
)

$ErrorActionPreference = 'Stop'

$ip       = '192.168.64.10'
$gateway  = '192.168.64.1'
$name     = 'DC01'
$domain   = 'corp.internal'
$netbios  = 'CORP'
$ntpPeers = 'time.windows.com,0x8'

switch ($Stage) {
    'Network' {
        if (Get-NetIPAddress -IPAddress $ip -ErrorAction SilentlyContinue) {
            Write-Host "IP $ip already configured"
        }
        elseif ($PSCmdlet.ShouldProcess($InterfaceAlias, "Set static IP $ip/24, gateway $gateway")) {
            # The RDP session drops here; reconnect to $ip
            New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $ip -PrefixLength 24 -DefaultGateway $gateway | Out-Null
        }

        # Gateway for now; Install-ADDSForest points the DC at itself
        if ($PSCmdlet.ShouldProcess($InterfaceAlias, "Set DNS server $gateway")) {
            Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $gateway
        }

        if ($env:COMPUTERNAME -eq $name) {
            Write-Host "Already named $name"
        }
        elseif ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Rename to $name and restart")) {
            Rename-Computer -NewName $name -Restart
        }
    }

    'Forest' {
        if ((Get-WindowsFeature AD-Domain-Services).Installed) {
            Write-Host 'AD DS role already installed'
        }
        elseif ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Install AD DS role')) {
            Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null
        }

        # DomainRole 4 = backup DC, 5 = primary DC
        if ((Get-CimInstance Win32_ComputerSystem).DomainRole -ge 4) {
            Write-Host 'Already a domain controller'
        }
        elseif ($PSCmdlet.ShouldProcess($domain, 'Create new AD DS forest and restart')) {
            $dsrm = Read-Host 'DSRM (Safe Mode Administrator) password - record it' -AsSecureString
            Install-ADDSForest -DomainName $domain -DomainNetbiosName $netbios -InstallDns -SafeModeAdministratorPassword $dsrm
        }
    }

    'PostPromotion' {
        $forwarders = (Get-DnsServerForwarder).IPAddress.IPAddressToString
        if ($forwarders -contains $gateway) {
            Write-Host "DNS forwarder $gateway already set"
        }
        elseif ($PSCmdlet.ShouldProcess('DNS Server', "Add forwarder $gateway")) {
            Add-DnsServerForwarder -IPAddress $gateway
        }

        # The PDC emulator is the time source for the whole forest. The emulated VM clock drifts,
        # and more than 5 minutes of skew breaks Kerberos, so sync from an external NTP server.
        if ($PSCmdlet.ShouldProcess('W32Time', "Sync from $ntpPeers")) {
            w32tm /config /manualpeerlist:$ntpPeers /syncfromflags:manual /reliable:yes /update | Out-Null
            if ($LASTEXITCODE) { throw "w32tm /config failed ($LASTEXITCODE)" }
            Restart-Service w32time
            w32tm /resync /rediscover | Out-Null
        }

        # Verify
        Get-ADDomain | Format-Table DNSRoot, NetBIOSName, DomainMode -AutoSize
        Get-Service adws, kdc, netlogon, dns | Format-Table Name, Status -AutoSize

        $dns = (Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4).ServerAddresses
        if ($dns -contains $gateway) {
            Write-Warning "$name still uses $gateway for DNS. Point it at itself ($ip or 127.0.0.1)."
        }

        w32tm /query /status
        Resolve-DnsName microsoft.com | Select-Object -First 1 Name, IPAddress
    }
}
