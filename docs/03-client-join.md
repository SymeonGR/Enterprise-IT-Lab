# 03 — Windows 11 client (WS01) and domain join

Script: [`scripts/03-client-join.ps1`](../scripts/03-client-join.ps1) — stops before joining if a pre-flight check fails.

## Build the VM

- ISO downloaded with **CrystalFetch** (official Microsoft media): Windows 11, **ARM64**, **Pro**.
  Home edition cannot join a domain.
- Runs natively on Apple Silicon (ARM on ARM), so it is far faster than the emulated DC.
- UTM Shared Network, same subnet as DC01.

## Point DNS at the DC

The join locates the domain through the client's own DNS, so it must use DC01:

```powershell
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.64.10
Clear-DnsClientCache
```

Pre-flight checks:
```powershell
Get-DnsClientServerAddress | Where-Object ServerAddresses | Format-Table InterfaceAlias, AddressFamily, ServerAddresses
Resolve-DnsName -Name "_ldap._tcp.dc._msdcs.corp.internal" -Type SRV
nltest /dsgetdc:corp.internal      # should return DC: \\DC01.corp.internal
```

## Join and rename in one step

```powershell
Add-Computer -DomainName "corp.internal" -NewName "WS01" -Credential CORP\Administrator -Restart
```

WS01 was joined with `CORP\Administrator`. That's more privilege than a join needs; [step 08](08-least-privilege.md) adds a delegated `svc-domainjoin` account, which the script uses by default (`-JoinAccount`).

## Verify

On the client:
```powershell
Get-CimInstance Win32_ComputerSystem | Select-Object Name, Domain, PartOfDomain
```
`PartOfDomain : True`, `Domain : corp.internal`. The logon screen shows **Sign in to: CORP** under *Other user*.

On DC01:
```powershell
Get-ADComputer WS01 | Select-Object Name, DistinguishedName
```
Expected: `CN=WS01,OU=Workstations,OU=LAB,DC=corp,DC=internal` (confirms `redircmp` worked).

Sign in as `CORP\nikos`:
```powershell
whoami                 # corp\nikos
echo $env:LOGONSERVER  # \\DC01
gpresult /r
```

Backup both VMs after a successful join (`Server-after-join.utm`, `WS01-after-join.utm`).
