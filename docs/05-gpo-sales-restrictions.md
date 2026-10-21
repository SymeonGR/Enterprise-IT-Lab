# 05 — GPO: Sales restrictions (user policy, PowerShell)

| | |
|---|---|
| Name | `USR - Sales Restrictions` |
| Linked to | `OU=Users,OU=LAB` |
| Type | User |
| Scope | `GG_Sales` only (security filtering) |
| Effect | Prohibit access to Control Panel and PC settings |

Script: [`scripts/05-gpo-sales-restrictions.ps1`](../scripts/05-gpo-sales-restrictions.ps1) — re-runnable, and fails if the permissions don't end up as expected below.

## Build it

```powershell
New-GPO -Name "USR - Sales Restrictions" | New-GPLink -Target "OU=Users,OU=LAB,DC=corp,DC=internal"

Set-GPRegistryValue -Name "USR - Sales Restrictions" `
  -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
  -ValueName "NoControlPanel" -Type DWord -Value 1
```

`Set-GPRegistryValue` only works for Administrative Template settings, which are registry values under the hood. This one equals
*User Configuration → Administrative Templates → Control Panel → Prohibit access to Control Panel and PC settings*.

## Security filtering

```powershell
Set-GPPermission -Name "USR - Sales Restrictions" -TargetName "GG_Sales" -TargetType Group -PermissionLevel GpoApply
Set-GPPermission -Name "USR - Sales Restrictions" -TargetName "Authenticated Users" -TargetType Group -PermissionLevel GpoRead -Replace
```

Verify:
```powershell
Get-GPPermission -Name "USR - Sales Restrictions" -All | Select-Object Trustee, Permission
```
Expected: `GG_Sales` → **GpoApply**, `Authenticated Users` → **GpoRead**.

In GPMC: *Scope → Security Filtering* shows only `GG_Sales`; *Delegation* shows `Authenticated Users` with **Read**.

### The MS16-072 trap

Since MS16-072 (2016), the computer reads user GPOs with its **own** account. Removing *Authenticated Users* entirely means the computer can't read the GPO, so it applies to **nobody** — not even the filtered group. Keep *Authenticated Users* with **Read** but without **Apply**.

GUI equivalent: remove *Authenticated Users* from Security Filtering, then add it back on the **Delegation** tab with **Read**. Adding it in Security Filtering grants Apply again.

## Test on WS01

| User | Group | Expected |
|------|-------|----------|
| `CORP\maria` | GG_Sales | `control` / Settings blocked; `gpresult /r` lists the GPO under *Applied* |
| `CORP\nikos` | GG_IT | Control Panel opens; `gpresult /r` lists the GPO as *filtered out — Denied (Security)* |

If a user was hit before filtering was fixed: `gpupdate /force`, sign out, sign in.

## Issues and resolutions

| Symptom | Cause | Fix | Prevention |
|---|---|---|---|
| GPO applied to all users, not only Sales | The `-Replace` call removing *Apply* from *Authenticated Users* never executed | Corrected in GPMC: *Authenticated Users* moved from Security Filtering to Delegation with **Read** | The script now checks `Get-GPPermission -All` itself and stops if *Authenticated Users* still has Apply |
