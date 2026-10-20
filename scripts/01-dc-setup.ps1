# DC01 setup: static IP, rename, AD DS forest, DNS forwarder
# Run in an elevated PowerShell on the server. The rename and the promotion both reboot,
# so run each block separately.

# --- Block 1: network + rename ---
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.64.10 -PrefixLength 24 -DefaultGateway 192.168.64.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.64.1
Rename-Computer -NewName "DC01" -Restart

# --- Block 2: AD DS (take a VM backup first) ---
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName "corp.internal" -DomainNetbiosName "CORP" -InstallDns

# --- Block 3: after reboot, sign in as CORP\Administrator ---
Add-DnsServerForwarder -IPAddress 192.168.64.1
Get-ADDomain | Select-Object DNSRoot, NetBIOSName
Get-Service adws, kdc, netlogon, dns | Select-Object Name, Status
Resolve-DnsName microsoft.com
