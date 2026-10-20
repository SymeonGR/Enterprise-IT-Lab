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

## What went wrong on the way

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

**Group change not taking effect**

After adding `Domain Admins` to `GG_LAPS_Readers`, the Administrator still needed a **sign-out and sign-in**: group membership is read into the logon token. Closing the RDP window only disconnects the session and keeps the old token — use *Sign out*. (`klist purge` refreshes Kerberos tickets as an alternative.)

## Key takeaways

- LAPS needs two separate rights: **read** on the OU and **decrypt** via the GPO. One without the other fails.
- Least privilege: helpdesk gets read access to workstation passwords only — not Domain Admin.
- Always test as a non-admin member and as a non-member; testing as Domain Admin proves nothing.
