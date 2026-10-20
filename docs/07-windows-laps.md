# 07 — Windows LAPS

Every workstation's built-in local Administrator gets a unique, random password that rotates automatically and is stored **encrypted** in AD. Only a dedicated group can read and decrypt it.

| | |
|---|---|
| GPO | `WS - LAPS` |
| Linked to | `OU=Workstations,OU=LAB` |
| Backup directory | Active Directory |
| Password | 14 chars, full complexity, rotates every 30 days |
| Encryption | Enabled |
| Who can read/decrypt | `GG_LAPS_Readers` (contains `GG_IT` and `Domain Admins`) |
| Method | PowerShell (schema, permissions, group) + GPMC (policy) |

## 1. Prerequisites

Windows LAPS is built into up-to-date Windows Server and Windows 11. Check on both DC01 and WS01:

```powershell
Get-ComputerInfo | Select-Object OsName, OsBuildNumber
Get-Command -Module LAPS | Select-Object -First 5 Name
```

If the LAPS cmdlets are listed, no install is needed. If not, the OS needs updating.

## 2. Extend the AD schema

One-time, forest-wide, and **not reversible** — take a DC backup first.

```powershell
Update-LapsADSchema -Verbose
```

Adds the `msLAPS-*` attributes to computer objects.

## 3. Permissions

A dedicated reader group, so access never depends on a single team group:

```powershell
New-ADGroup -Name "GG_LAPS_Readers" -GroupScope Global -Path "OU=Groups,OU=LAB,DC=corp,DC=internal"
Add-ADGroupMember GG_LAPS_Readers -Members GG_IT, "Domain Admins"
```

Computers may write their own password; the reader group may read it — scoped to the Workstations OU only:

```powershell
$ou = "OU=Workstations,OU=LAB,DC=corp,DC=internal"
Set-LapsADComputerSelfPermission -Identity $ou
Set-LapsADReadPasswordPermission -Identity $ou -AllowedPrincipals "CORP\GG_LAPS_Readers"
Find-LapsADExtendedRights -Identity $ou
```

## 4. GPO `WS - LAPS`

*Computer Configuration → Policies → Administrative Templates → System → LAPS*

| Setting | Value |
|---|---|
| Configure password backup directory | Enabled — **Active Directory** |
| Password Settings | Enabled — large + small letters + numbers + specials, length **14**, age **30** days |
| Enable password encryption | Enabled |
| Configure authorized password decryptors | Enabled — `CORP\GG_LAPS_Readers` |

Apply on WS01 (elevated):

```powershell
gpupdate /force
Invoke-LapsPolicyProcessing -Verbose
```

## 5. Verify

Safe to share — shows status without revealing the password:

```powershell
Get-LapsADPassword -Identity WS01 | Format-List
```

Expected: `Source : EncryptedPassword`, `DecryptionStatus : Success`, `AuthorizedDecryptor : CORP\GG_LAPS_Readers`.

`-AsPlainText` reveals the actual password — never paste that output anywhere.

## 6. Tests

| Test | As | Result |
|---|---|---|
| Read password | `CORP\nikos` (GG_IT → GG_LAPS_Readers), standard prompt | `DecryptionStatus : Success` ✓ |
| Read password | `CORP\maria` (Sales) | Nothing returned — no read right on the OU ✓ |
| Read password | `CORP\Administrator` (Domain Admins → GG_LAPS_Readers) | `Success` ✓ |
| Rotation | `Reset-LapsPassword` on WS01, then check `PasswordUpdateTime` on DC01 | Timestamp updated ✓ |

## 7. Where the helpdesk reads the password

**PowerShell** — works on any domain-joined Windows 11, no extra tools:

```powershell
Get-LapsADPassword -Identity WS01 -AsPlainText
```

**GUI (ADUC)** — *Active Directory Users and Computers* → computer object → **Properties** → **LAPS** tab: *Show password*, *Copy password*, *Expire now*, last change and expiry.

Getting ADUC on the **Windows 11 ARM64** workstation:

- RSAT is **not** available as a Feature on Demand on Arm64 — `Get-WindowsCapability -Online -Name "Rsat*"` returns nothing.
- On **Windows 11 25H2 Arm64**, RSAT is installed from **Turn Windows features on or off** (`optionalfeatures`). AD DS tools sit under **RSAT: Server Manager Tools**; *RSAT: Group Policy Management Tools* was added too.

Tested as `CORP\nikos` (standard user): LAPS tab shows the password. ✓

Production note: admin tools usually live on a dedicated admin workstation or jump host, not on every helpdesk PC.

## Open items

**Admin rights on an everyday account.** `GG_LAPS_Readers` currently contains `GG_IT`, so `nikos` reads LAPS passwords with the same account he uses for email and browsing. A compromised daily account would expose every workstation's local admin password. Planned fix: a separate `adm-nikos` account in a dedicated `Admin Accounts` OU, with `GG_Helpdesk_Admins` replacing `GG_IT` in `GG_LAPS_Readers`.

**Built-in Administrator is disabled.** LAPS manages the **built-in Administrator** (RID 500), which is **disabled** by default on Windows 11 — the password is stored and rotated, but can't be used to sign in yet. Next step: a dedicated local admin account managed by LAPS.

## Issues and resolutions

**Domain Admins locked out of the password**

The first policy set the authorized decryptor to `CORP\GG_IT`. After a rotation, the DC returned:

```
Source              : EncryptedPassword
DecryptionStatus    : Unauthorized
AuthorizedDecryptor : CORP\GG_IT
```

even for `CORP\Administrator`.

- The authorized decryptor **replaces** the default (Domain Admins); it isn't added to it.
- The decryptor is fixed **when the password is encrypted**. A password written before a policy change keeps the old decryptor until the next rotation — which is why it had worked a few minutes earlier.
- Tying recovery to one team group is fragile: if `GG_IT` is emptied or changed, nobody can recover the password.

Fix: dedicated `GG_LAPS_Readers` group containing `GG_IT` and `Domain Admins`, used for both the read permission and the decryptor; `Reset-LapsPassword` to re-encrypt.

**`Get-WindowsCapability`: "The requested operation requires elevation"**

*Run as different user* gives another identity, **not** an elevated token — UAC still filters it. Elevate with `Start-Process powershell -Verb RunAs`; the title bar then shows *Administrator:*.

**Group change not taking effect**

After adding `Domain Admins` to `GG_LAPS_Readers`, the Administrator still needed a **sign-out and sign-in**: group membership is read into the logon token. Closing the RDP window only disconnects the session and keeps the old token — use *Sign out*. (`klist purge` refreshes Kerberos tickets as an alternative.)

## Design notes

- LAPS needs two separate rights: **read** on the OU and **decrypt** via the GPO. One without the other fails.
- Least privilege: helpdesk gets read access to workstation passwords only — not Domain Admin.
- Always test as a non-admin member and as a non-member; testing as Domain Admin proves nothing.
- Working is not the same as secure: the first version worked, but gave password access to everyday accounts.
