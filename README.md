# Active Directory Home Lab — `corp.internal`

A hands-on Active Directory lab built from scratch on an Apple Silicon Mac using UTM.
The goal is to practise the day-to-day work of an endpoint / infrastructure engineer:
building a domain, structuring it properly, joining clients, and delivering and troubleshooting Group Policy.
The lab will later be extended into a hybrid setup (Entra ID, Intune).

**Approach:** PowerShell-first. Everything from IP configuration to domain join and the Sales GPO was done in PowerShell.
Two GPOs (logon banner, Remote Desktop) were built deliberately in the GPMC GUI, to practise both ways of working and to cover settings like Group Policy Preferences, which have no native PowerShell cmdlets.
The *Method* column below shows which is which.

## Topology

| Host | OS | Role | IP |
|------|----|------|----|
| `DC01` | Windows Server (x86, emulated) | AD DS, DNS | `192.168.64.10` (static) |
| `WS01` | Windows 11 Pro (ARM64) | Domain-joined workstation | DHCP, DNS → DC01 |

- **Domain:** `corp.internal` (NetBIOS `CORP`)
- **Network:** UTM Shared Network `192.168.64.0/24`, gateway `192.168.64.1`
- **DNS:** DC01 is authoritative for `corp.internal`, forwards external queries to `192.168.64.1`
- **Access:** both VMs are managed over RDP from macOS (Windows App), not through the UTM console
- **Storage:** VMs and backups live on an external drive; a backup copy of each `.utm` bundle is taken before every major change

```
            macOS (Apple Silicon) — UTM Shared Network 192.168.64.0/24
   ┌──────────────────────────┐         ┌──────────────────────────┐
   │ DC01  192.168.64.10      │◄───────►│ WS01  (DHCP)             │
   │ AD DS + DNS              │  LDAP,  │ Windows 11 Pro ARM64     │
   │ corp.internal / CORP     │  Kerb,  │ OU=Workstations          │
   └──────────────────────────┘  SMB    └──────────────────────────┘
```

## What's built

| # | Area | Method | Doc |
|---|------|--------|-----|
| 1 | Static IP, rename, AD DS forest, DNS forwarder | PowerShell | [01-domain-controller.md](docs/01-domain-controller.md) |
| 2 | OU structure, computer redirection, users, groups | PowerShell | [02-ad-structure.md](docs/02-ad-structure.md) |
| 3 | Windows 11 client domain join | PowerShell | [03-client-join.md](docs/03-client-join.md) |
| 4 | GPO: logon banner (computer policy) | GPMC (GUI) | [04-gpo-logon-banner.md](docs/04-gpo-logon-banner.md) |
| 5 | GPO: Control Panel lockdown, security-filtered to Sales (user policy) | PowerShell | [05-gpo-sales-restrictions.md](docs/05-gpo-sales-restrictions.md) |
| 6 | GPO: RDP + firewall + local group membership via Preferences | GPMC (GUI) | [06-gpo-remote-desktop.md](docs/06-gpo-remote-desktop.md) |
| 7 | Windows LAPS: encrypted, rotating local admin passwords in AD | PowerShell + GPMC | [07-windows-laps.md](docs/07-windows-laps.md) |
| — | Problems hit and how they were solved | — | [troubleshooting.md](docs/troubleshooting.md) |

Scripts used are in [`scripts/`](scripts/).

## AD layout

```
corp.internal
└── LAB
    ├── Users          nikos, maria, giorgos
    ├── Groups         GG_IT (nikos), GG_Sales (maria, giorgos),
    │                  GG_LAPS_Readers (GG_IT, Domain Admins)
    ├── Workstations   WS01   ← default location for new computers (redircmp)
    └── Servers
```

## GPOs

| GPO | Linked to | Type | Scope | Effect |
|-----|-----------|------|-------|--------|
| `WS - Logon Banner` | `OU=Workstations` | Computer | All workstations | Legal notice before logon |
| `USR - Sales Restrictions` | `OU=Users` | User | `GG_Sales` only (security filtering) | Blocks Control Panel and Settings |
| `WS - Remote Desktop` | `OU=Workstations` | Computer | All workstations | Enables RDP, opens firewall for the lab subnet, adds `GG_IT` to *Remote Desktop Users* |
| `WS - LAPS` | `OU=Workstations` | Computer | All workstations | Local admin password backed up to AD, encrypted, 14 chars, 30-day rotation; decryptable by `GG_LAPS_Readers` |

**Verified results**
- Banner shown on WS01 after reboot.
- `maria` (Sales): Control Panel blocked. `nikos` (IT): unaffected — `gpresult` shows the GPO as *filtered out, Denied (Security)*.
- `nikos` can RDP to WS01; `maria` is denied.
- LAPS: `nikos` and Domain Admins can read and decrypt WS01's password; `maria` gets nothing; `Reset-LapsPassword` rotates it.
- RSAT (ADUC) on the Arm64 workstation: `nikos` reads the password from the LAPS tab.

## Key takeaways

- Computer policies must be linked to the OU where the **computer** object lives; user policies to where the **user** lives.
- Since MS16-072, user GPOs are read in the computer's context: when security-filtering, keep *Authenticated Users* with **Read** (but not Apply), or the GPO applies to nobody.
- Use GPP *Local Users and Groups* with **Update** to add members; Restricted Groups replaces membership and can wipe existing members fleet-wide.
- Never type group names by hand in GPO editors — browse and resolve them, so they're bound to a SID.
- Computer-side `gpresult` needs an elevated prompt; a standard user only sees user settings.
- LAPS needs both **read** permission on the OU and **decrypt** rights; setting an authorized decryptor replaces Domain Admins rather than adding to them.
- Group membership lives in the logon token: after a group change, sign out and back in.

## Roadmap

- [x] Windows LAPS — rotating local admin password stored in AD
- [ ] LAPS-managed local admin account usable for sign-in (built-in Administrator is disabled on Windows 11)
- [ ] BitLocker on WS01 with recovery keys escrowed to AD
- [ ] Hybrid identity — Entra Connect, hybrid Entra join
- [ ] Intune enrollment and co-management
- [ ] AD Certificate Services (PKI)
- [ ] Move DC to native x86 hardware or Azure (x86 emulation on Apple Silicon is very slow)
