# Run on the Windows 11 Pro client, elevated

Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.64.10
Clear-DnsClientCache

# Pre-flight: both must succeed before joining
Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.corp.internal" -Type SRV
nltest /dsgetdc:corp.internal

Add-Computer -DomainName "corp.internal" -NewName "WS01" -Credential CORP\Administrator -Restart

# After reboot:
# Get-CimInstance Win32_ComputerSystem | Select-Object Name, Domain, PartOfDomain
