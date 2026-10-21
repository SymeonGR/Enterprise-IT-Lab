# 08 — Least-privilege fixes: delegated join, AGDLP, LAPS hardening

> **Status: scripted, not yet run in the lab.** The tests below are the plan; results get filled in after the run.

Fixes for gaps found when reviewing steps 01–07:

| Gap | Fix |
|---|---|
| WS01 was joined with `CORP\Administrator` — a Domain Admin used for a task that needs one delegated right | `svc-domainjoin` may create computers in `OU=Workstations` only |
| Every user can join up to 10 computers (`ms-DS-MachineAccountQuota` default) — `maria` could add a machine to the domain | Quota set to **0** |
| `GG_LAPS_Readers` is a Global group holding a resource permission — breaks the AGDLP model the naming suggests | Converted to Domain Local `DL_LAPS_Readers` |
| LAPS manages the built-in Administrator, which is disabled on Windows 11 — the password exists but can't be used | LAPS automatic account management creates and manages `lapsadmin` |
| 14-character passwords (the default minimum) | 20 characters |
| Post-authentication reset relies on the default (24 h) | Explicit: reset and sign out **8 h** after use |

Script: [`scripts/08-least-privilege.ps1`](../scripts/08-least-privilege.ps1) — run with `-WhatIf` first. Values come from the `JoinDelegation` and `Laps` sections of [`config/lab.psd1`](../config/lab.psd1).

## 1. Delegated domain join

`svc-domainjoin` lives in a new `OU=Service Accounts` and gets, on `OU=Workstations` only:

| Right | Applies to | Why |
|---|---|---|
| Create / delete computer objects | the OU | Create the account during the join |
| Reset password | computer objects | Set the machine password |
| Write *Account Restrictions* | computer objects | `userAccountControl` |
| Validated write: DNS host name, SPN | computer objects | `dNSHostName`, `servicePrincipalName` |

Granted with `dsacls`, since there's no cmdlet for delegation. GUI equivalent: ADUC → right-click `Workstations` → *Delegate Control*.

Then `ms-DS-MachineAccountQuota = 0` on the domain, so joining *requires* a delegated account.

Re-using an existing computer object (re-joining WS01) is also subject to the KB5020276 join hardening; the test below covers new computers only.

## 2. AGDLP for LAPS

Accounts → **G**lobal groups (who people are: `GG_IT`) → **D**omain **L**ocal groups (what they may do: `DL_LAPS_Readers`) → **P**ermissions.

The existing group is converted in place: Global → Universal → Domain Local (a direct Global → Domain Local change isn't allowed), then renamed. The **SID doesn't change**, so:
- the read permission on `OU=Workstations` stays valid without re-granting it;
- passwords already encrypted to the group stay decryptable — unlike the decryptor change in [07](07-windows-laps.md#issues-and-resolutions), which locked out Domain Admins.

The GPO's authorized decryptor is updated to the new name `CORP\DL_LAPS_Readers`, because the device resolves that name when it encrypts.

## 3. `WS - LAPS` by script

The GPO built in GPMC in step 07 is updated with `Set-GPRegistryValue`. These are the same registry values the GPMC settings write (`HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\LAPS`), so GPMC still shows them as normal LAPS settings.

| Setting | Before (07) | After |
|---|---|---|
| Password length | 14 | **20** |
| Complexity / age | large + small + numbers + specials, 30 days | unchanged |
| Encryption / decryptor | on, `CORP\GG_LAPS_Readers` | on, `CORP\DL_LAPS_Readers` |
| Post-authentication actions | not configured (default: reset + sign out after 24 h) | reset + sign out after **8 h** |
| Managed account | built-in Administrator (disabled) | **automatic account management**: new enabled account `lapsadmin` |

Automatic account management needs **Windows 11 24H2 / Windows Server 2025** or later (WS01 is 25H2). If DC01's `LAPS.admx` is older, GPMC lists those values under *Extra Registry Settings*, but they still apply on WS01.

## 4. Tests (to run)

On WS01, elevated:
```powershell
gpupdate /force
Invoke-LapsPolicyProcessing -Verbose
Reset-LapsPassword          # new length and account only apply at the next rotation
Get-LocalUser lapsadmin     # Enabled : True
```

| Test | As | Expected |
|---|---|---|
| `Get-LapsADPassword -Identity WS01` | `CORP\nikos` | `Account : lapsadmin`, `DecryptionStatus : Success`, `AuthorizedDecryptor : CORP\DL_LAPS_Readers` |
| Same | `CORP\maria` | Nothing returned |
| Sign in to WS01 as `.\lapsadmin` with the LAPS password | — | Works; password rotates ~8 h later and the session is signed out |
| Join a new VM with `svc-domainjoin` | — | Joins; object created in `OU=Workstations` |
| Join a new VM with `CORP\maria` | — | Fails: quota 0, no delegated rights |
| `dsacls "OU=Servers,OU=LAB,DC=corp,DC=internal"` | — | No entry for `svc-domainjoin` (scope is Workstations only) |
