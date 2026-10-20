# 01 — Domain Controller (DC01)

## Before you start
Shut the VM down and copy its `.utm` bundle to the backup location (e.g. `Server-before-AD.utm`).
UTM's built-in *Clone* writes to the internal disk, so a manual Finder copy to the external drive is used instead.
To restore, open the copied `.utm` with UTM.

## 1. Static IP and hostname

```powershell
Get-NetAdapter   # note the adapter name, usually "Ethernet"

New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.64.10 -PrefixLength 24 -DefaultGateway 192.168.64.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.64.1
```

The RDP session drops when the IP changes; reconnect to `192.168.64.10`.
DNS points to the UTM gateway for now; after promotion the DC uses itself.

```powershell
Rename-Computer -NewName "DC01" -Restart
```

Check from macOS when the VM is back up:
```bash
nc -vz 192.168.64.10 3389
```

Verify:
```powershell
hostname
ipconfig /all
```

## 2. Install AD DS and create the forest

Take another backup first — a failed promotion is hard to roll back.

```powershell
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName "corp.internal" -DomainNetbiosName "CORP" -InstallDns
```

- Set and record the **DSRM** (Safe Mode Administrator) password.
- Yellow warnings about DNS delegation and cryptography algorithms are expected in a lab.
- The server reboots automatically. Under x86 emulation this took 20–40 minutes.
- After reboot, sign in as `CORP\Administrator`.

**Why `.internal`:** it is reserved for private use and will never collide with a public domain. `.local` conflicts with mDNS and causes problems.

## 3. Verify

```powershell
Get-ADDomain | Select-Object DNSRoot, NetBIOSName
Get-Service adws, kdc, netlogon, dns | Select-Object Name, Status
nslookup corp.internal
```

All services should be `Running` and `corp.internal` should resolve to `192.168.64.10`.

> `DNS request timed out` / `Server: UnKnown` in `nslookup` is harmless: there is no reverse lookup zone, so nslookup cannot resolve the DNS server's own name before answering.

SYSVOL health:
```powershell
Get-SmbShare | Where-Object Name -in "SYSVOL","NETLOGON"
dcdiag /q
```

`dcdiag` failures in **DFSREvent** and **SystemLog** on a fresh DC only count recent event-log errors; `Advertising`, `SysVolCheck` and `NetLogons` passing is what matters. Event **4602** confirms SYSVOL initialised.

## 4. DNS forwarder for internet access

```powershell
Add-DnsServerForwarder -IPAddress 192.168.64.1
Resolve-DnsName microsoft.com
```
