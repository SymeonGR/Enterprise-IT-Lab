# 04 — GPO: Logon banner (computer policy, GUI)

| | |
|---|---|
| Name | `WS - Logon Banner` |
| Linked to | `OU=Workstations,OU=LAB` |
| Type | Computer |
| Method | Group Policy Management Console |

## Steps

1. Server Manager → Tools → **Group Policy Management**.
2. Forest → Domains → `corp.internal` → `LAB`.
3. Right-click **Workstations** → *Create a GPO in this domain, and Link it here…* → `WS - Logon Banner`.
4. Right-click the GPO → **Edit**.
5. *Computer Configuration → Policies → Windows Settings → Security Settings → Local Policies → Security Options*
   - **Interactive logon: Message title for users attempting to log on** → `CORP Lab`
   - **Interactive logon: Message text for users attempting to log on** → `Authorized users only.`
6. Close the editor (changes save automatically).

## Test on WS01

From an **elevated** prompt (`CORP\Administrator`):
```powershell
gpupdate /force
gpresult /r /scope computer
```
`WS - Logon Banner` appears under *Applied Group Policy Objects*.
Restart, then the banner appears before the logon screen.

## Notes

- Linked to the OU holding the **computer** objects; a computer policy linked to a user OU never applies.
- Computer-side results need an elevated `gpresult` — a standard user only sees user settings.
- The banner is a Security Option applied at boot, so verification needs a restart, not just `gpupdate`.
